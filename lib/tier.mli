(** A level of the programme: reached with [threshold] points in the tier window (see
    {!Tiers}), it grants its [benefits]. *)

open! Core

type t = private
  { code : string (** stable identifier, e.g. ["silver"] *)
  ; name : string (** display name *)
  ; threshold : int (** window points needed; the first tier's is 0 *)
  ; benefits : Benefit.t list
  }
[@@deriving sexp_of, compare, equal]

(** Fails on an empty code or name, a negative threshold or an invalid benefit. *)
val create
  :  code:string
  -> name:string
  -> threshold:int
  -> ?benefits:Benefit.t list
  -> unit
  -> t Or_error.t

(** The spread to charge on a currency exchange: [standard], lowered to the tier's
    tightest [Fx_spread_cap], never raised. *)
val fx_spread_bps : t -> standard:int -> int

(** The tier's fee schedule for [product] in [currency], if it has one. *)
val fee_schedule : t -> product:string -> currency:Money.Currency.t -> Money.Fee.t option

(** [fee_schedule], or [standard] when the tier has none for the product in
    [standard]'s currency. *)
val fee : t -> product:string -> standard:Money.Fee.t -> Money.Fee.t

module Stable : sig
  module V1 : sig
    (** Reading validates like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
