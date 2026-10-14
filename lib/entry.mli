(** One line of a customer's points ledger. Entries are never edited or removed; a
    correction is a new [Adjustment] entry. *)

open! Core

type t = private
  { user : User_id.t
  ; seq : int (** position in the customer's ledger, from 0, without gaps *)
  ; cause : Cause.t
  ; points : int (** signed: positive adds to the balance, negative spends *)
  ; at : Time_ns.Alternate_sexp.t (** when the event happened *)
  ; earning : Earning.t option (** for card purchases and refunds *)
  ; note : string (** free text, e.g. an adjustment's reason *)
  }
[@@deriving sexp_of, compare, equal]

(** Fails when [points] has the wrong sign for the cause's {!Kind.t}, when [seq] is
    negative, or when [earning] is given for a cause other than a card purchase or
    refund. *)
val create
  :  user:User_id.t
  -> seq:int
  -> cause:Cause.t
  -> points:int
  -> at:Time_ns.t
  -> ?earning:Earning.t
  -> ?note:string (** default [""] *)
  -> unit
  -> t Or_error.t

(** [Cause.kind t.cause]. *)
val kind : t -> Kind.t

(** [Cause.key t.cause]. *)
val key : t -> string

(** True when [a] and [b] describe the same event: equal except, possibly, in [seq] and
    [at]. A redelivered event is a duplicate, not a conflict, even if the caller stamped
    it with a new time. *)
val same_request : t -> t -> bool

module Stable : sig
  module V1 : sig
    (** [t_of_sexp] and the bin_prot reader validate like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
