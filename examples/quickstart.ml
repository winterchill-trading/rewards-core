(* A small card programme: earn on settled spend, claw back a refund, redeem cashback and
   book it into a ledger. *)

open! Core
open Rewards_core

let eur s = Money.Amount.of_decimal_string Money.Currency.eur s |> Or_error.ok_exn
let at s = Time_ns.of_string_with_utc_offset s

let program =
  let ok = Or_error.ok_exn in
  Program.create
    ~earn:
      (Earn_rules.create
         ~basis:Money.Currency.eur
         ~multipliers:[ Category.of_string "travel", 3; Category.of_string "cash", 0 ]
         ~bonuses:[ Action.of_string "first_exchange", 250 ]
         ()
       |> ok)
    ~tiers:
      (Tiers.create
         ~window:(Time_ns.Span.of_day 90.)
         [ Tier.create ~code:"standard" ~name:"Standard" ~threshold:0 () |> ok
         ; Tier.create
             ~code:"plus"
             ~name:"Plus"
             ~threshold:1_500
             ~benefits:[ Fx_spread_cap { bps = 35 } ]
             ()
           |> ok
         ]
       |> ok)
    ~cashback:
      (Cashback.Rules.create
         ~step:100
         ~value_per_step:(eur "0.50")
         ~minimum:1_000
         ~maximum:1_000_000
       |> ok)
    ~expiry:(After_days 365)
  |> ok
;;

module Store = Store_memory.Make (Monad.Ident)
module Rewards = Engine.Make (Monad.Ident) (Store)

let () =
  let rewards = Rewards.create program (Store.create ()) in
  let user = User_id.of_string "customer-42" in
  let show = function
    | Ok (Engine.Outcome.Booked e) -> printf "%-28s %+6d\n" (Entry.key e) e.points
    | Ok (Already_booked e) -> printf "%-28s (already booked)\n" (Entry.key e)
    | Ok Nothing_to_book -> print_endline "nothing to book"
    | Error refusal -> printf "refused: %s\n" (Refusal.code refusal)
  in
  let settle id amount category =
    Rewards.settle_purchase
      rewards
      ~user
      ~purchase:(Source_id.of_string id)
      ~spend:(eur amount)
      ~category:(Category.of_string category)
      ~rate:None
      ~at:(at "2026-05-02 09:00:00Z")
    |> show
  in
  settle "card-tx-1" "420.00" "travel";
  settle "card-tx-1" "420.00" "travel" (* the settlement webhook, delivered twice *);
  settle "card-tx-2" "38.75" "groceries";
  settle "card-tx-3" "200.00" "cash";
  Rewards.refund_purchase
    rewards
    ~user
    ~refund:(Source_id.of_string "card-rf-1")
    ~purchase:(Source_id.of_string "card-tx-1")
    ~amount:(eur "105.00")
    ~at:(at "2026-05-04 12:00:00Z")
  |> show;
  Rewards.complete_action
    rewards
    ~user
    ~action:(Action.of_string "first_exchange")
    ~at:(at "2026-05-05 08:00:00Z")
  |> show;
  (* Redeem 1,200 points: 6.00 EUR into the customer's account. *)
  let customer = Ledger.Account_id.of_string "customer:42/eur" in
  let redemption =
    Rewards.redeem
      rewards
      ~id:(Redemption_id.of_string "redeem-req-1")
      ~user
      ~account:customer
      ~currency:Money.Currency.eur
      ~points:1_200
      ~rate:None
      ~now:(at "2026-05-06 10:00:00Z")
    |> Result.map_error ~f:Refusal.to_error
    |> Or_error.ok_exn
  in
  let entry =
    Booking.cashback Booking.Chart.default redemption ~recorded_at:redemption.created_at
    |> Or_error.ok_exn
  in
  printf
    "cashback %s, ledger key %s\n"
    (Money.Amount.to_string redemption.quote.amount)
    (Ledger.Idempotency_key.to_string entry.idempotency_key);
  let summary =
    Rewards.summary rewards ~user ~now:(at "2026-05-06 10:00:00Z") |> Or_error.ok_exn
  in
  printf
    "balance %d, tier %s (%d window points, %d%% of the way to the next), redeemable %d\n"
    summary.balance
    summary.tier.tier.name
    summary.tier.window_points
    summary.tier.progress_percent
    summary.redeemable
;;
