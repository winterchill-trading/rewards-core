open! Core
module Account_id = Ledger.Account_id

module Chart = struct
  type t = { rewards_expense : Money.Currency.t -> Account_id.t }

  let default =
    { rewards_expense =
        (fun currency ->
          (* Currency text forms ("EUR", "USDC@polygon") only use ledger id characters. *)
          Account_id.of_string ("expense:rewards/" ^ Money.Currency.to_string currency))
    }
  ;;

  let accounts t ~currencies =
    List.map currencies ~f:(fun currency ->
      Ledger.Account.create (t.rewards_expense currency) Expense)
    |> List.dedup_and_sort ~compare:(fun (a : Ledger.Account.t) b ->
      Account_id.compare a.id b.id)
  ;;
end

let idempotency_key id =
  Ledger.Idempotency_key.of_string_or_error
    ("rewards:redemption:" ^ Redemption_id.to_string id)
;;

let cashback (chart : Chart.t) (r : Redemption.t) ~recorded_at =
  let open Or_error.Let_syntax in
  match r.status with
  | Accepted | Refused _ ->
    Or_error.error_s
      [%message
        "only a completed redemption is paid"
          ~id:(r.id : Redemption_id.t)
          ~status:(r.status : Redemption.Status.t)]
  | Completed ->
    let%bind idempotency_key = idempotency_key r.id in
    let amount = r.quote.amount in
    Ledger.Entry.create
      ~idempotency_key
      ~kind:(Transfer "rewards_cashback")
      ~reference:(Redemption_id.to_string r.id)
      ~effective_at:r.created_at
      ~recorded_at
      [ Ledger.Posting.debit (chart.rewards_expense (Money.Amount.currency amount)) amount
      ; Ledger.Posting.credit r.account amount
      ]
;;

let apply balances entries =
  List.fold_result entries ~init:balances ~f:(fun b (entry : Ledger.Entry.t) ->
    Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Posted entry })
;;
