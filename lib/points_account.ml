open! Core

type t =
  { user : User_id.t
  ; balance : int
  ; lifetime_earned : int
  ; length : int
  ; rev_entries : Entry.t list
  ; by_key : Entry.t String.Map.t
  }
[@@deriving sexp_of]

let empty user =
  { user
  ; balance = 0
  ; lifetime_earned = 0
  ; length = 0
  ; rev_entries = []
  ; by_key = String.Map.empty
  }
;;

let user t = t.user
let balance t = t.balance
let lifetime_earned t = t.lifetime_earned
let length t = t.length
let entries t = List.rev t.rev_entries
let find t cause = Map.find t.by_key (Cause.key cause)

let refunds_of t ~purchase =
  List.filter (entries t) ~f:(fun (e : Entry.t) ->
    match e.cause with
    | Card_refund { purchase = p; refund = _ } -> Source_id.equal p purchase
    | _ -> false)
;;

module Applied = struct
  type nonrec t =
    | Appended of t
    | Duplicate of Entry.t
  [@@deriving sexp_of]
end

let apply t (entry : Entry.t) : (Applied.t, Refusal.t) Result.t =
  if not (User_id.equal entry.user t.user)
  then
    Error
      (Invalid
         (Error.create_s
            [%message
              "entry for another customer"
                ~expected:(t.user : User_id.t)
                ~got:(entry.user : User_id.t)]))
  else (
    match Map.find t.by_key (Entry.key entry) with
    | Some existing ->
      if Entry.same_request existing entry
      then Ok (Duplicate existing)
      else Error (Cause_conflict { key = Entry.key entry })
    | None ->
      if entry.seq <> t.length
      then
        Error
          (Invalid
             (Error.create_s
                [%message
                  "out of sequence" ~expected:(t.length : int) ~got:(entry.seq : int)]))
      else (
        let balance = t.balance + entry.points in
        if balance < 0
        then Error (Insufficient_points { balance = t.balance; requested = -entry.points })
        else (
          let lifetime_earned =
            match Entry.kind entry with
            | Earn | Bonus -> t.lifetime_earned + entry.points
            | Reversal | Redeem | Adjustment | Expire -> t.lifetime_earned
          in
          Ok
            (Appended
               { t with
                 balance
               ; lifetime_earned
               ; length = t.length + 1
               ; rev_entries = entry :: t.rev_entries
               ; by_key = Map.set t.by_key ~key:(Entry.key entry) ~data:entry
               }))))
;;

let of_entries user entries =
  List.fold_result entries ~init:(empty user) ~f:(fun t entry ->
    match apply t entry with
    | Ok (Appended t) -> Ok t
    | Ok (Duplicate _) ->
      Or_error.error_s
        [%message "duplicate cause in a stored ledger" ~key:(Entry.key entry : string)]
    | Error refusal -> Error (Refusal.to_error refusal))
;;

let prepare t ~cause ~points ~at ?earning ?note () =
  let open Result.Let_syntax in
  let%bind entry =
    Entry.create ~user:t.user ~seq:t.length ~cause ~points ~at ?earning ?note ()
    |> Refusal.of_or_error
  in
  match%map apply t entry with
  | Appended _ -> `New entry
  | Duplicate existing -> `Duplicate existing
;;
