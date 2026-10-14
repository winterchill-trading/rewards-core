(** Exact currency conversion for earn rules and cashback: the value stays a rational
    until the caller rounds it once, in the direction its rule names. *)

open! Core

(** [major_units amount ~to_ ~rate] is the value of [amount] in major units of [to_]:
    exact, unrounded. With [amount] already in [to_] the rate is ignored. Otherwise the
    rate must convert between the two currencies, in either direction (an inverse rate
    is used as [1 / price]). *)
val major_units
  :  Money.Amount.t
  -> to_:Money.Currency.t
  -> rate:Money.Rate.t option
  -> (Q.t, Refusal.t) Result.t

(** The rate oriented from [from] to [to_], if [rate] links the two currencies. *)
val orient
  :  Money.Rate.t
  -> from:Money.Currency.t
  -> to_:Money.Currency.t
  -> Money.Rate.t option
