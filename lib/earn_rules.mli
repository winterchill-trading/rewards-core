(** How points are earned.

    {b Purchases.} Points are earned when card spend settles, not when it is authorised,
    so a reversed authorisation never earns. The settled amount is converted to the
    programme's basis currency at the rate the caller supplies (typically the mid rate
    of the settlement date), the result is floored to whole basis units, and each unit
    earns [points_per_unit] times the category's multiplier. A category with
    multiplier 0 (cash withdrawals, say) earns nothing. Without a rate for a foreign
    purchase the purchase is refused with [Rate_unavailable]; booking it later, once a
    rate exists, still earns once because the cause is the purchase id.

    {b Refunds.} A refund claws back points in proportion to the refunded share of the
    purchase: after refunds totalling [r] of a purchase of [s] that earned [p], the
    purchase has given back [floor (p * min (r, s) / s)] points in all, so a full refund
    returns exactly [p] and partial refunds never add up to more. A clawback is capped
    at the customer's balance at the time; points already spent are not recovered
    later.

    {b Actions.} A one-off action (first exchange, first goal reached) earns its bonus
    once per customer, whatever the number of times the event is reported. *)

open! Core

type t = private
  { basis : Money.Currency.t
  ; points_per_unit : int (** per whole unit of [basis] *)
  ; default_multiplier : int (** for categories not listed in [multipliers] *)
  ; multipliers : int Category.Map.t
  ; bonuses : int Action.Map.t
  }
[@@deriving sexp_of, compare, equal]

(** Fails on a negative multiplier or [points_per_unit], a bonus that is not positive,
    or a category or action listed twice. *)
val create
  :  basis:Money.Currency.t
  -> ?points_per_unit:int (** default 1 *)
  -> ?default_multiplier:int (** default 1 *)
  -> ?multipliers:(Category.t * int) list
  -> ?bonuses:(Action.t * int) list
  -> unit
  -> t Or_error.t

(** The multiplier for a category. *)
val multiplier : t -> Category.t -> int

(** The bonus for an action, if one is configured. *)
val bonus : t -> Action.t -> int option

(** The points a settled purchase earns, with the details to keep on the entry. Zero
    points (a zero multiplier, or spend below one basis unit) is a valid answer: the
    caller books nothing. Refuses a spend that is not positive and a foreign spend
    without a usable rate. *)
val purchase
  :  t
  -> spend:Money.Amount.t
  -> category:Category.t
  -> rate:Money.Rate.t option
  -> (int * Earning.t, Refusal.t) Result.t

(** The points a refund takes back from [purchase] (the purchase's [Earn] entry), given
    the refunds booked against it before ([earlier]) and the customer's [balance]. The
    result is positive or zero; the entry books its negation. Refuses a refund in another
    currency than the purchase. *)
val clawback
  :  purchase:Entry.t
  -> earlier:Entry.t list
  -> refund:Money.Amount.t
  -> balance:int
  -> (int * Earning.t, Refusal.t) Result.t

module Stable : sig
  module V1 : sig
    (** Maps are written as lists of pairs; reading validates like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
