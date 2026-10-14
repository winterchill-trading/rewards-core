(** Where a customer stands: balance, tier, what they can redeem now and what expires
    when. Pure, from the programme and the customer's ledger. *)

open! Core

type t =
  { balance : int
  ; lifetime_earned : int
  ; tier : Tiers.Status.t
  ; redeemable : int (** see {!Cashback.Rules.redeemable} *)
  ; expiring : (Date.t * int) list (** see {!Expiry.schedule} *)
  }
[@@deriving sexp_of]

val compute : Program.t -> Points_account.t -> now:Time_ns.t -> t
