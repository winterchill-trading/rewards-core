(** A cashback redemption and its small state machine.

    {v
      Accepted --points booked--> Completed
         |
         +--points refused------> Refused
    v}

    The record is saved [Accepted] before the points are spent, so a request retried after
    a crash finds it and finishes the same redemption (same quote, same amount) instead of
    pricing a new one. Only a [Completed] redemption is paid out ([Booking.cashback]). *)

open! Core

module Status : sig
  type t =
    | Accepted (** priced and recorded; points not yet spent *)
    | Completed (** points spent; the cash entry may be booked *)
    | Refused of { code : string }
    (** the points could not be spent (the balance fell meanwhile); a {!Refusal.code} *)
  [@@deriving sexp, compare, equal]
end

type t = private
  { id : Redemption_id.t
  ; user : User_id.t
  ; account : Ledger.Account_id.t (** the customer's account that receives the cash *)
  ; quote : Cashback.Quote.t
  ; created_at : Time_ns.Alternate_sexp.t
  ; status : Status.t
  }
[@@deriving sexp_of, compare, equal]

(** A new, [Accepted] redemption. *)
val create
  :  id:Redemption_id.t
  -> user:User_id.t
  -> account:Ledger.Account_id.t
  -> quote:Cashback.Quote.t
  -> created_at:Time_ns.t
  -> t

(** True when a request for [points] by [user] into [account] is a retry of [t]. *)
val same_request
  :  t
  -> user:User_id.t
  -> account:Ledger.Account_id.t
  -> points:int
  -> bool

(** [Accepted] to [Completed]; a [Completed] redemption stays as it is. Fails from
    [Refused]. *)
val complete : t -> t Or_error.t

(** [Accepted] to [Refused]; fails from any other state. *)
val refuse : t -> Refusal.t -> t Or_error.t

(** The points entry cause, [Redemption id]. *)
val cause : t -> Cause.t

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
