(** Where points entries and redemptions live. Libraries never persist: a service
    implements this signature over its database, and {!Store_memory} serves tests and
    offline modes.

    Two guarantees make the ledger safe under concurrent writers, and an implementation
    must provide both atomically per customer (a unique index on (customer, cause key)
    and on (customer, seq), or a row lock on the customer):
    - {!S.append} refuses a second entry for the same cause key, answering
      [Cause_taken] with the stored entry, whatever its sequence number;
    - it refuses an entry whose [seq] is not the customer's current length, answering
      [Stale]. The engine decided the entry against that length (including the
      balance check), so a stale entry is re-decided rather than written.

    Redemptions are inserted once per id ({!S.insert_redemption}, first writer wins) and
    then updated in place as their status moves forward. *)

open! Core

module Append : sig
  type t =
    | Appended
    | Cause_taken of Entry.t (** the entry already stored for the cause key *)
    | Stale of { length : int } (** the customer's ledger has [length] entries now *)
  [@@deriving sexp_of, compare, equal]
end

module Insert : sig
  type t =
    | Inserted
    | Exists of Redemption.t (** the redemption already stored under the id *)
  [@@deriving sexp_of, compare, equal]
end

module type S = sig
  type 'a io
  type t

  (** A customer's entries, in sequence order. *)
  val entries : t -> User_id.t -> Entry.t list io

  (** See the guarantees above. Checks the cause key first, then the sequence number. *)
  val append : t -> Entry.t -> Append.t io

  (** Every customer with at least one entry, in id order. *)
  val users : t -> User_id.t list io

  val find_redemption : t -> Redemption_id.t -> Redemption.t option io

  (** Stores a new redemption unless its id is taken. *)
  val insert_redemption : t -> Redemption.t -> Insert.t io

  (** Replaces a stored redemption. Fails when none is stored under its id. *)
  val update_redemption : t -> Redemption.t -> unit Or_error.t io
end
