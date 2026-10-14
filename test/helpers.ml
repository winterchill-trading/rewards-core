open! Core
open Rewards_core
module Amount = Money.Amount
module Currency = Money.Currency

let eur s = Amount.of_decimal_string Currency.eur s |> Or_error.ok_exn
let usd s = Amount.of_decimal_string Currency.usd s |> Or_error.ok_exn
let gbp s = Amount.of_decimal_string Currency.gbp s |> Or_error.ok_exn
let time s = Time_ns.of_string_with_utc_offset s
let t0 = time "2026-03-01 10:00:00Z"
let user = User_id.of_string "user-1"
let src = Source_id.of_string
let cat = Category.of_string
let act = Action.of_string

let rate ~base ~quote price =
  Money.Rate.create
    ~base
    ~quote
    ~price:(Money.Rate.price_of_string price |> Or_error.ok_exn)
    ~at:t0
    ~source:"test"
  |> Or_error.ok_exn
;;

(* 1 EUR = 1.10 USD and 1 EUR = 0.85 GBP. *)
let eur_usd = rate ~base:Currency.eur ~quote:Currency.usd "1.10"
let eur_gbp = rate ~base:Currency.eur ~quote:Currency.gbp "0.85"

let earn_rules =
  Earn_rules.create
    ~basis:Currency.eur
    ~multipliers:[ cat "travel", 3; cat "groceries", 2; cat "cash", 0 ]
    ~bonuses:[ act "first_exchange", 250; act "first_goal", 300 ]
    ()
  |> Or_error.ok_exn
;;

let tier ?(benefits = []) code threshold =
  Tier.create ~code ~name:(String.capitalize code) ~threshold ~benefits ()
  |> Or_error.ok_exn
;;

let tiers =
  Tiers.create
    ~window:(Time_ns.Span.of_day 90.)
    [ tier "bronze" 0
    ; tier "silver" 1_500 ~benefits:[ Fx_spread_cap { bps = 35 } ]
    ; tier
        "gold"
        5_000
        ~benefits:
          [ Fx_spread_cap { bps = 20 }
          ; Fee_schedule
              { product = "exchange"
              ; fee = Money.Fee.create Currency.eur ~bps:10 |> Or_error.ok_exn
              }
          ; Perk "priority support"
          ]
    ]
  |> Or_error.ok_exn
;;

let cashback =
  Cashback.Rules.create
    ~step:100
    ~value_per_step:(eur "0.50")
    ~minimum:1_000
    ~maximum:1_000_000
  |> Or_error.ok_exn
;;

let program ?(expiry = Expiry.Policy.Never) () =
  Program.create ~earn:earn_rules ~tiers ~cashback ~expiry |> Or_error.ok_exn
;;

module Store_types = Store
module Store = Store_memory.Make (Monad.Ident)
module Rewards = Engine.Make (Monad.Ident) (Store)

let engine ?expiry () = Rewards.create (program ?expiry ()) (Store.create ())

let print_outcome r =
  match r with
  | Ok (Engine.Outcome.Booked e) -> printf "booked %+d (%s)\n" e.points (Entry.key e)
  | Ok (Already_booked e) -> printf "already booked %+d (%s)\n" e.points (Entry.key e)
  | Ok Nothing_to_book -> print_endline "nothing to book"
  | Error refusal -> print_s [%message "refused" (refusal : Refusal.t)]
;;

let balance engine user =
  (Rewards.account engine user |> Or_error.ok_exn |> Points_account.balance : int)
;;
