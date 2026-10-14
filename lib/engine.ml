open! Core

module Outcome = struct
  type t =
    | Booked of Entry.t
    | Already_booked of Entry.t
    | Nothing_to_book
  [@@deriving sexp_of, compare, equal]
end

(* How often a decision is re-made after another writer changed the ledger first. *)
let max_attempts = 5

module Make (M : Monad.S) (Store : Store.S with type 'a io := 'a M.t) = struct
  open M.Let_syntax

  type t =
    { program : Program.t
    ; store : Store.t
    }

  let create program store = { program; store }
  let program t = t.program

  let account t user =
    let%map entries = Store.entries t.store user in
    Points_account.of_entries user entries
  ;;

  type decision =
    { points : int
    ; earning : Earning.t option
    ; note : string
    }

  let found ~cause ~matches existing : (Outcome.t, Refusal.t) Result.t =
    if matches existing
    then Ok (Already_booked existing)
    else Error (Cause_conflict { key = Cause.key cause })
  ;;

  (* The shared write path: idempotency by cause first, then the decision, then an append
     that only lands on the ledger the decision was made against. *)
  let book t ~user ~cause ~at ~matches ~decide =
    let rec attempt n =
      match%bind account t user with
      | Error e -> return (Error (Refusal.Invalid e))
      | Ok acct ->
        (match Points_account.find acct cause with
         | Some existing -> return (found ~cause ~matches existing)
         | None ->
           (match decide acct with
            | Error _ as e -> return e
            | Ok None -> return (Ok Outcome.Nothing_to_book)
            | Ok (Some { points; earning; note }) ->
              (match Points_account.prepare acct ~cause ~points ~at ?earning ~note () with
               | Error _ as e -> return e
               | Ok (`Duplicate existing) -> return (found ~cause ~matches existing)
               | Ok (`New entry) ->
                 (match%bind Store.append t.store entry with
                  | Appended -> return (Ok (Outcome.Booked entry))
                  | Cause_taken existing -> return (found ~cause ~matches existing)
                  | Stale _ ->
                    if n >= max_attempts
                    then return (Error Refusal.Contended)
                    else attempt (n + 1)))))
    in
    attempt 1
  ;;

  let positive points ~earning ~note =
    Ok (if points > 0 then Some { points; earning; note } else None)
  ;;

  let settle_purchase t ~user ~purchase ~spend ~category ~rate ~at =
    let matches (e : Entry.t) =
      match e.earning with
      | Some x -> Money.Amount.equal x.spend spend && Category.equal x.category category
      | None -> false
    in
    book t ~user ~cause:(Card_purchase purchase) ~at ~matches ~decide:(fun _ ->
      let open Result.Let_syntax in
      let%bind points, earning =
        Earn_rules.purchase t.program.earn ~spend ~category ~rate
      in
      positive points ~earning:(Some earning) ~note:"")
  ;;

  let refund_purchase t ~user ~refund ~purchase ~amount ~at =
    let matches (e : Entry.t) =
      match e.earning with
      | Some x -> Money.Amount.equal x.spend amount
      | None -> false
    in
    book
      t
      ~user
      ~cause:(Card_refund { refund; purchase })
      ~at
      ~matches
      ~decide:(fun acct ->
        match Points_account.find acct (Card_purchase purchase) with
        | None -> Ok None
        | Some purchase_entry ->
          let open Result.Let_syntax in
          let%bind points, earning =
            Earn_rules.clawback
              ~purchase:purchase_entry
              ~earlier:(Points_account.refunds_of acct ~purchase)
              ~refund:amount
              ~balance:(Points_account.balance acct)
          in
          (* Booked even at zero points: later refunds of the purchase are measured
             against everything refunded so far, which only the entries record. *)
          Ok (Some { points = -points; earning = Some earning; note = "" }))
  ;;

  let complete_action t ~user ~action ~at =
    book t ~user ~cause:(Action action) ~at ~matches:(Fn.const true) ~decide:(fun _ ->
      match Earn_rules.bonus t.program.earn action with
      | None -> Error (Refusal.Unknown_action action)
      | Some points -> positive points ~earning:None ~note:"")
  ;;

  let adjust t ~user ~id ~points ~reason ~at =
    let matches (e : Entry.t) = e.points = points && String.equal e.note reason in
    book t ~user ~cause:(Adjustment id) ~at ~matches ~decide:(fun _ ->
      if points = 0
      then Error (Refusal.Invalid (Error.of_string "an adjustment needs points"))
      else Ok (Some { points; earning = None; note = reason }))
  ;;

  let expire t ~user ~as_of ~at =
    book t ~user ~cause:(Expiry as_of) ~at ~matches:(Fn.const true) ~decide:(fun acct ->
      let due =
        Expiry.due t.program.expiry (Points_account.entries acct) ~as_of
        |> Int.min (Points_account.balance acct)
      in
      Ok (if due > 0 then Some { points = -due; earning = None; note = "" } else None))
  ;;

  let expire_all t ~as_of ~at =
    let%bind users = Store.users t.store in
    List.fold users ~init:(return []) ~f:(fun acc user ->
      let%bind acc in
      let%map outcome = expire t ~user ~as_of ~at in
      (user, outcome) :: acc)
    >>| List.rev
  ;;

  let quote_cashback t ~user ~points ~currency ~rate =
    match%map account t user with
    | Error e -> Error (Refusal.Invalid e)
    | Ok acct ->
      Cashback.quote
        t.program.cashback
        ~points
        ~balance:(Points_account.balance acct)
        ~currency
        ~rate
  ;;

  let save t r =
    match%map Store.update_redemption t.store r with
    | Ok () -> Ok r
    | Error e -> Error (Refusal.Invalid e)
  ;;

  (* Spends the points of an accepted redemption and moves it forward. *)
  let finish t (r : Redemption.t) =
    match r.status with
    | Completed | Refused _ -> return (Ok r)
    | Accepted ->
      let points = r.quote.points in
      (match%bind
         book
           t
           ~user:r.user
           ~cause:(Redemption.cause r)
           ~at:r.created_at
           ~matches:(fun e -> e.points = -points)
           ~decide:(fun _ -> Ok (Some { points = -points; earning = None; note = "" }))
       with
       | Ok (Booked _ | Already_booked _) ->
         (match Redemption.complete r with
          | Ok r -> save t r
          | Error e -> return (Error (Refusal.Invalid e)))
       | Ok Nothing_to_book ->
         return (Error (Refusal.Invalid (Error.of_string "unreachable")))
       | Error (Insufficient_points _ as refusal) ->
         (match Redemption.refuse r refusal with
          | Ok r -> save t r
          | Error e -> return (Error (Refusal.Invalid e)))
       | Error _ as e -> return e)
  ;;

  let resume t (r : Redemption.t) ~user ~account ~points =
    if Redemption.same_request r ~user ~account ~points
    then finish t r
    else return (Error (Refusal.Redemption_conflict { id = r.id }))
  ;;

  let redeem t ~id ~user ~account ~currency ~points ~rate ~now =
    match%bind Store.find_redemption t.store id with
    | Some r -> resume t r ~user ~account ~points
    | None ->
      (match%bind quote_cashback t ~user ~points ~currency ~rate with
       | Error _ as e -> return e
       | Ok quote ->
         let r = Redemption.create ~id ~user ~account ~quote ~created_at:now in
         (match%bind Store.insert_redemption t.store r with
          | Inserted -> finish t r
          | Exists r -> resume t r ~user ~account ~points))
  ;;

  let summary t ~user ~now =
    let%map acct = account t user in
    Or_error.map acct ~f:(fun acct -> Summary.compute t.program acct ~now)
  ;;

  let statement t ~user ~from ~until =
    let%map entries = Store.entries t.store user in
    Statement.create ~user ~from ~until entries
  ;;
end
