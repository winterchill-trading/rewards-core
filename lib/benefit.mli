(** What a tier gives its members. *)

open! Core

type t =
  | Fx_spread_cap of { bps : int }
  (** currency exchanges are priced with at most this spread over the mid rate *)
  | Fee_schedule of
      { product : string (** what the schedule prices, e.g. ["exchange"] or ["atm"] *)
      ; fee : Money.Fee.t (** replaces the standard schedule in [fee]'s currency *)
      }
  | Perk of string (** anything else, described in words for display *)
[@@deriving sexp, compare, equal]

(** Fails on a negative spread cap, an empty product or an empty perk. *)
val validate : t -> unit Or_error.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
