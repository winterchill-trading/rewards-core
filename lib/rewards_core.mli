(** Loyalty points for banks: an append-only points ledger per customer, earn rules for
    settled card spend, one-off action bonuses, tiers over a rolling window with benefits,
    cashback redemption booked through [ledger], an expiry policy and statements. Pure
    values and state machines; persistence is the {!Store.S} module type. *)

(** {1 Identifiers} *)

(** A customer of the programme. *)
module User_id = User_id

(** The id of the event behind an entry (a card transaction, an adjustment request). *)
module Source_id = Source_id

(** A redemption's id, which is also its idempotency key. *)
module Redemption_id = Redemption_id

(** A one-off action that earns a bonus once. *)
module Action = Action

(** A merchant category with its own multiplier. *)
module Category = Category

(** {1 The points ledger} *)

(** Earn, bonus, reversal, redeem, adjustment, expire. *)
module Kind = Kind

(** Why an entry exists; at most one entry per cause and customer. *)
module Cause = Cause

(** How a purchase's points were worked out. *)
module Earning = Earning

(** One line of a customer's points ledger. *)
module Entry = Entry

(** A customer's ledger folded into a balance, with the booking rules. *)
module Points_account = Points_account

(** Why an operation was refused, as data. *)
module Refusal = Refusal

(** {1 Rules} *)

(** Exact conversion between the spend, basis and payout currencies. *)
module Convert = Convert

(** How many points a refund takes back: the default cumulative rule and a per-refund
    proportional one. *)
module Clawback_rule = Clawback_rule

(** Points for purchases, clawback for refunds, bonuses for actions. *)
module Earn_rules = Earn_rules

(** What a tier grants. *)
module Benefit = Benefit

(** One level of the programme. *)
module Tier = Tier

(** The tier ladder over a rolling window. *)
module Tiers = Tiers

(** Pricing points as money. *)
module Cashback = Cashback

(** When points stop being spendable. *)
module Expiry = Expiry

(** A whole programme's configuration. *)
module Program = Program

(** {1 Redemptions and the money ledger} *)

(** A cashback redemption and its status. *)
module Redemption = Redemption

(** The ledger entry that pays a completed redemption. *)
module Booking = Booking

(** {1 Reports} *)

(** Balance, tier, redeemable points and expiry for one customer. *)
module Summary = Summary

(** A points statement over a period. *)
module Statement = Statement

(** {1 Running a programme} *)

(** Persistence as a module type. *)
module Store = Store

(** An in-memory store. *)
module Store_memory = Store_memory

(** Scenarios every store must pass. *)
module Store_conformance = Store_conformance

(** The programme's operations over a store. *)
module Engine = Engine
