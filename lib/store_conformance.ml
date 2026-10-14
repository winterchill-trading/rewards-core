open! Core

(* The functor parameter below is also called [Store]; keep the result types reachable. *)
module Results = Store

module Make (M : Monad.S) (Store : Store.S with type 'a io := 'a M.t) = struct
  open M.Let_syntax

  let at = Time_ns.of_string_with_utc_offset "2026-01-01 12:00:00Z"
  let user = User_id.of_string "conformance-user"

  let entry ~seq ~cause ~points =
    Entry.create ~user ~seq ~cause ~points ~at () |> Or_error.ok_exn
  ;;

  let expect what ~sexp_of ~equal got want =
    if equal got want
    then Ok ()
    else
      Or_error.error_s
        [%message what ~got:(sexp_of got : Sexp.t) ~want:(sexp_of want : Sexp.t)]
  ;;

  let append_is what store e want =
    let%map got = Store.append store e in
    expect what ~sexp_of:Results.Append.sexp_of_t ~equal:Results.Append.equal got want
  ;;

  let ( >>=? ) a f =
    match%bind a with
    | Error _ as e -> return e
    | Ok () -> f ()
  ;;

  let quote =
    let eur s = Money.Amount.of_decimal_string Money.Currency.eur s |> Or_error.ok_exn in
    { Cashback.Quote.points = 1000; value = eur "5.00"; amount = eur "5.00"; rate = None }
  ;;

  let check store =
    let first =
      entry ~seq:0 ~cause:(Action (Action.of_string "conformance-a")) ~points:10
    in
    let second =
      entry ~seq:1 ~cause:(Card_purchase (Source_id.of_string "conformance-p")) ~points:5
    in
    append_is "first append" store first Appended
    >>=? (fun () ->
           (* The same cause again, even with the next sequence number, is the stored
              entry. *)
           append_is
             "repeated cause"
             store
             (entry ~seq:1 ~cause:(Action (Action.of_string "conformance-a")) ~points:10)
             (Cause_taken first))
    >>=? (fun () ->
           append_is
             "stale sequence number"
             store
             (entry
                ~seq:0
                ~cause:(Card_purchase (Source_id.of_string "conformance-p"))
                ~points:5)
             (Stale { length = 1 }))
    >>=? (fun () -> append_is "second append" store second Appended)
    >>=? (fun () ->
           let%map got = Store.entries store user in
           expect
             "entries in sequence order"
             ~sexp_of:[%sexp_of: Entry.t list]
             ~equal:[%equal: Entry.t list]
             got
             [ first; second ])
    >>=? (fun () ->
           let%map got = Store.users store in
           if List.mem got user ~equal:User_id.equal
           then Ok ()
           else
             Or_error.error_s
               [%message "users misses the customer" (got : User_id.t list)])
    >>=? fun () ->
    let r =
      Redemption.create
        ~id:(Redemption_id.of_string "conformance-r")
        ~user
        ~account:(Ledger.Account_id.of_string "customer:conformance/eur")
        ~quote
        ~created_at:at
    in
    let%bind inserted = Store.insert_redemption store r in
    let%bind again =
      Store.insert_redemption store (Or_error.ok_exn (Redemption.complete r))
    in
    let completed = Or_error.ok_exn (Redemption.complete r) in
    let%bind updated = Store.update_redemption store completed in
    let%bind found = Store.find_redemption store r.id in
    let%map unknown =
      Store.update_redemption
        store
        (Redemption.create
           ~id:(Redemption_id.of_string "conformance-missing")
           ~user
           ~account:r.account
           ~quote
           ~created_at:at)
    in
    Or_error.all_unit
      [ expect
          "first insert"
          ~sexp_of:Results.Insert.sexp_of_t
          ~equal:Results.Insert.equal
          inserted
          Inserted
      ; expect
          "second insert keeps the first"
          ~sexp_of:Results.Insert.sexp_of_t
          ~equal:Results.Insert.equal
          again
          (Exists r)
      ; updated
      ; expect
          "find after update"
          ~sexp_of:[%sexp_of: Redemption.t option]
          ~equal:[%equal: Redemption.t option]
          found
          (Some completed)
      ; (match unknown with
         | Error _ -> Ok ()
         | Ok () -> Or_error.error_s [%message "updating an unknown redemption succeeded"])
      ]
  ;;
end
