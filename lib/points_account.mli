(** One customer's points ledger folded into a state: the balance, the causes already
    booked and the entries in order. Pure: {!apply} decides whether an entry may be
    appended, and a [Store.S] keeps the entries.

    Rules enforced by {!apply}, so they hold for any accepted sequence:
    - every entry belongs to this customer and carries the next sequence number;
    - a cause is booked at most once: the same event again is a [Duplicate] of the first
      entry, the same cause with other content is refused;
    - the balance never goes below zero. *)

open! Core

type t [@@deriving sexp_of]

(** A customer with no entries. *)
val empty : User_id.t -> t

val user : t -> User_id.t

(** The sum of every entry's points; never negative. *)
val balance : t -> int

(** Points added by [Earn] and [Bonus] entries, before any spending, clawback or expiry. *)
val lifetime_earned : t -> int

(** The number of entries, which is also the next entry's [seq]. *)
val length : t -> int

(** Every entry, oldest first. *)
val entries : t -> Entry.t list

(** The entry booked for this cause, if any (by {!Cause.key}). *)
val find : t -> Cause.t -> Entry.t option

(** The refund entries booked against a purchase, oldest first. *)
val refunds_of : t -> purchase:Source_id.t -> Entry.t list

module Applied : sig
  type nonrec t =
    | Appended of t (** the new state *)
    | Duplicate of Entry.t (** the entry booked earlier for the same event *)
  [@@deriving sexp_of]
end

(** Checks [entry] against the rules above and returns the new state. A duplicate leaves
    the state unchanged and is checked before the sequence number, so a redelivered event
    is recognised whatever [seq] it was given. *)
val apply : t -> Entry.t -> (Applied.t, Refusal.t) Result.t

(** [apply] for every entry, refusing duplicates (a stored ledger has none). *)
val of_entries : User_id.t -> Entry.t list -> t Or_error.t

(** Builds the next entry for [cause] (with [seq = length t]) and checks it with {!apply}:
    [`New entry] to append, or [`Duplicate entry] when the event is booked already. *)
val prepare
  :  t
  -> cause:Cause.t
  -> points:int
  -> at:Time_ns.t
  -> ?earning:Earning.t
  -> ?note:string
  -> unit
  -> ([ `New of Entry.t | `Duplicate of Entry.t ], Refusal.t) Result.t
