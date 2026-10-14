(** Turning points into money on the customer's own account.

    Points are redeemed in whole [step]s, each worth [value_per_step] in the programme's
    basis currency, between [minimum] and [maximum] points. When the account is in another
    currency the basis value is converted at the rate the caller supplies (a mid rate) and
    rounded down to the account currency's minor unit, so the bank never pays more than
    the points are worth. *)

open! Core

module Rules : sig
  type t = private
    { step : int
    ; value_per_step : Money.Amount.t (** in the basis currency *)
    ; minimum : int
    ; maximum : int
    }
  [@@deriving sexp_of, compare, equal]

  (** Fails unless [step] and [value_per_step] are positive, [minimum] and [maximum] are
      multiples of [step], and [step <= minimum <= maximum]. *)
  val create
    :  step:int
    -> value_per_step:Money.Amount.t
    -> minimum:int
    -> maximum:int
    -> t Or_error.t

  (** The basis currency. *)
  val basis : t -> Money.Currency.t

  (** The most a customer with [balance] points can redeem at once: the balance rounded
      down to a step and capped at [maximum], or 0 below [minimum]. *)
  val redeemable : t -> balance:int -> int

  module Stable : sig
    module V1 : sig
      (** Reading validates like {!create}. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

module Quote : sig
  type t =
    { points : int
    ; value : Money.Amount.t (** in the basis currency *)
    ; amount : Money.Amount.t (** what the account receives, in its currency *)
    ; rate : Money.Rate.t option
    (** basis to account currency; [None] when the account is in the basis currency *)
    }
  [@@deriving sexp, compare, equal]

  module Stable : sig
    module V1 : sig
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** Prices a redemption of [points] for a customer holding [balance], paid into an account
    in [currency]. Checks, in order: [Too_small], [Too_large], [Not_a_step],
    [Insufficient_points], then the conversion ([Rate_unavailable], [Rate_mismatch]) and
    [Rounds_to_zero]. *)
val quote
  :  Rules.t
  -> points:int
  -> balance:int
  -> currency:Money.Currency.t
  -> rate:Money.Rate.t option
  -> (Quote.t, Refusal.t) Result.t
