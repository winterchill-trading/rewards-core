(** A whole programme's configuration: how points are earned, the tier ladder, the
    cashback rules and the expiry policy. Plain data, loadable from a sexp file. *)

open! Core

type t = private
  { earn : Earn_rules.t
  ; tiers : Tiers.t
  ; cashback : Cashback.Rules.t
  ; expiry : Expiry.Policy.t
  }
[@@deriving sexp_of, compare, equal]

(** Fails when the cashback value is in another currency than the earn rules' basis, or
    the expiry policy is invalid. *)
val create
  :  earn:Earn_rules.t
  -> tiers:Tiers.t
  -> cashback:Cashback.Rules.t
  -> expiry:Expiry.Policy.t
  -> t Or_error.t

(** The basis currency of earning and cashback. *)
val basis : t -> Money.Currency.t

module Stable : sig
  module V1 : sig
    (** Reading validates like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
