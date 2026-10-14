(** How the points of a purchase (or of its refund) were worked out, kept on the entry so
    a statement can show it and a refund can be clawed back in proportion. *)

open! Core

type t =
  { spend : Money.Amount.t (** the settled amount, in the card transaction's currency *)
  ; basis_amount : Money.Amount.t
  (** [spend] in the programme's basis currency at [rate], rounded down to a minor unit *)
  ; rate : Money.Rate.t option (** [None] when [spend] is already in the basis currency *)
  ; category : Category.t
  ; multiplier : int
  }
[@@deriving sexp, compare, equal]

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
