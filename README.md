# rewards-core

Loyalty points for banks, in OCaml: an append-only points ledger per customer, earn
rules for settled card spend with category multipliers, proportional clawback on
refunds, one-off action bonuses, tiers over a rolling window with benefits (an FX spread
cap, a cheaper fee schedule), cashback redemption booked as balanced
[`ledger`](https://github.com/winterchill-trading/ledger) entries, an expiry policy and
points statements. Amounts come from [`money`](https://github.com/winterchill-trading/money):
exact minor units, no floats anywhere. The library targets the
[OxCaml](https://oxcaml.org) compiler and the Jane Street `core` stack.

## Why separate

A card programme's points behave like a second currency that the bank owes its
customers: they need the same guarantees as money (a balance that never goes below
zero, every event booked once however often it is delivered, corrections as new entries,
a statement that adds up) and they turn into money on redemption, which must land in
the bank's books exactly once. Keeping those rules in a small library, with no storage,
transport or card-network code, means they are tested once with properties and every
service that runs a programme gets them for free. The library knows customers, causes,
points and rules; it does not know about databases, webhooks or HTTP.

## Install

Not on opam yet. With an OxCaml switch (`5.2.0+ox`) that has the ox opam repository,
pin the library and its organisation dependencies in order:

```sh
opam pin add fixed-decimal https://github.com/winterchill-trading/fixed-decimal.git
opam pin add money https://github.com/winterchill-trading/money.git
opam pin add ledger https://github.com/winterchill-trading/ledger.git
opam pin add rewards-core https://github.com/winterchill-trading/rewards-core.git
```

Then add `rewards-core` to the `libraries` of a dune stanza. Build: `dune build`, test:
`dune test`. No environment variables, no network.

## Quick start

```ocaml
open! Core
open Rewards_core

(* [program] and [eur] are defined in examples/quickstart.ml. *)
module Store = Store_memory.Make (Monad.Ident)
module Rewards = Engine.Make (Monad.Ident) (Store)

let () =
  let rewards = Rewards.create program (Store.create ()) in
  let user = User_id.of_string "customer-42" in
  (* 420.00 EUR of travel at 3x earns 1,260 points; a second delivery books nothing. *)
  ignore
    (Rewards.settle_purchase rewards ~user
       ~purchase:(Source_id.of_string "card-tx-1")
       ~spend:(eur "420.00") ~category:(Category.of_string "travel")
       ~rate:None ~at:(Time_ns.now ()));
  (* A refund of a quarter of it takes back 315 points. *)
  ignore
    (Rewards.refund_purchase rewards ~user
       ~refund:(Source_id.of_string "card-rf-1")
       ~purchase:(Source_id.of_string "card-tx-1")
       ~amount:(eur "105.00") ~at:(Time_ns.now ()));
  (* 1,200 points become 6.00 EUR; the ledger entry is keyed rewards:redemption:<id>. *)
  match
    Rewards.redeem rewards ~id:(Redemption_id.of_string "redeem-req-1") ~user
      ~account:(Ledger.Account_id.of_string "customer:42/eur")
      ~currency:Money.Currency.eur ~points:1_200 ~rate:None ~now:(Time_ns.now ())
  with
  | Ok ({ status = Completed; _ } as r) ->
    let entry =
      Booking.cashback Booking.Chart.default r ~recorded_at:(Time_ns.now ())
      |> Or_error.ok_exn
    in
    ignore (entry : Ledger.Entry.t) (* append it to the journal *)
  | Ok _ | Error _ -> ()
;;
```

The complete program, with the programme definition and its output checked by
`dune test`, is [examples/quickstart.ml](examples/quickstart.ml):

```text
card_purchase:card-tx-1       +1260
card_purchase:card-tx-1      (already booked)
card_purchase:card-tx-2         +38
nothing to book
card_refund:card-rf-1          -315
action:first_exchange          +250
cashback 6.00 EUR, ledger key rewards:redemption:redeem-req-1
balance 33, tier Standard (1233 window points, 82% of the way to the next), redeemable 0
```

## Modules

| Module | What it is |
| --- | --- |
| `User_id`, `Source_id`, `Redemption_id`, `Action`, `Category` | Validated ids in the ledger's alphabet, at most 100 characters |
| `Kind` | Earn, Bonus, Reversal, Redeem, Adjustment, Expire, with the sign each requires |
| `Cause` | Why an entry exists (a purchase, a refund, an action, a redemption, an adjustment, an expiry date); its key is unique per customer |
| `Entry`, `Earning` | One ledger line, with how a purchase's points were computed |
| `Points_account` | A customer's entries folded: balance, lifetime earned, causes; `apply` enforces the rules |
| `Earn_rules` | Basis currency, points per unit, category multipliers, action bonuses; purchase and clawback arithmetic |
| `Benefit`, `Tier`, `Tiers` | Tier ladder over a rolling window; spread caps, fee schedules (`Money.Fee.t`) and perks |
| `Cashback` | Steps, value per step, minimum and maximum; quotes converted and rounded down |
| `Expiry` | `Never` or `After_days n`, with lots spent earliest-expiring first |
| `Program` | The whole configuration, loadable from a sexp |
| `Redemption`, `Booking` | Redemption state machine; the balanced ledger entry that pays it |
| `Summary`, `Statement` | Balance, tier, redeemable and expiring points; statements with running balances |
| `Store`, `Store_memory`, `Store_conformance` | Persistence as a module type, an in-memory store and the scenarios any store must pass |
| `Engine` | The operations over any store and monad |
| `Refusal` | Every refusal as data with a stable code |

## Rules

Enforced by `Points_account.apply` and the store contract, so they hold after any
accepted sequence of operations (a Quickcheck property drives random streams of
purchases, refunds, bonuses, adjustments, redemptions and expiry runs through the engine
and checks them after every step):

- Entries are append-only and numbered per customer without gaps. Corrections are new
  `Adjustment` entries.
- The balance never goes below zero. A clawback is capped at the balance; a negative
  adjustment or a redemption that would overdraw is refused.
- Each cause is booked at most once per customer. The same event again is
  `Already_booked` with the first entry; the same cause with different content (another
  amount for the same purchase) is `Cause_conflict`.
- Points are earned on settlement only: the settled amount converted to the basis
  currency at the caller's rate, floored to whole units, times the category multiplier.
  A foreign purchase without a rate is refused (`RATE_UNAVAILABLE`) and earns once when
  retried with a rate.
- Refunds claw back in proportion to the refunded share, cumulatively, so partial
  refunds never add up to more than the purchase earned. Every refund is recorded, even
  at zero points, so a series of small refunds cannot dodge the clawback.
- A tier is measured over a rolling window on earned points net of clawbacks;
  redemptions and expiry never lower it.
- Cashback is priced in whole steps between a minimum and a maximum and rounded down
  in the account's currency, so it never pays more than the points are worth.
- Spending takes the points that expire first. An expiry run books once per date.

### Concurrency and retries

The engine is written against a `Store.S` that guarantees two things atomically per
customer: one entry per cause key, and an entry lands only at the sequence number it
was decided against. A decision taken on a ledger that changed meanwhile is made again
(a few times, then `CONTENDED`). A redemption is recorded `Accepted` with its price
before its points are spent, so a retry after a crash finishes the same redemption at
the same price; it then moves to `Completed` (pay it with `Booking.cashback`) or
`Refused` when the points were gone by then. The cash entry's idempotency key is
`rewards:redemption:<id>`, so a journal books it once.

### Refusal codes

`INSUFFICIENT_POINTS`, `TOO_SMALL`, `TOO_LARGE`, `STEP`, `RATE_UNAVAILABLE`,
`RATE_MISMATCH`, `ROUNDS_TO_ZERO`, `UNKNOWN_ACTION`, `CAUSE_CONFLICT`,
`REDEMPTION_CONFLICT`, `CURRENCY_MISMATCH`, `PURCHASE_NOT_FOUND`, `CONTENDED`,
`INVALID`.

## Storage

The library never persists. A service implements `Store.S` over its database (a unique
index on (customer, cause key) and on (customer, sequence number), plus a redemptions
table keyed by id) and runs `Store_conformance` against it next to `Store_memory`.
`Entry`, `Redemption`, `Program` and the other records have `Stable.V1` bin_prot and
sexp forms whose digests are pinned in `test/test_stable.ml`; their readers validate.

## Known gaps

- Partner redemptions (points transferred to another scheme) are not modelled.
- The money ledger is not driven by the engine: the caller appends the cashback entry.
  A service that wants both in one transaction does that in its own store.
- Tier windows count entries by event time; a very late settlement counts in the
  window of its event date, not of its arrival.

## Docs

- API documentation: `dune build @doc`.
- [CHANGES.md](CHANGES.md).
- [AGENTS.md](AGENTS.md) for automated contributors.

## Licence

MIT.
