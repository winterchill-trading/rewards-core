(** When points stop being spendable.

    Every entry that adds points ([Earn], [Bonus], a positive [Adjustment]) opens a lot.
    Every entry that takes points away ([Redeem], [Reversal], [Expire], a negative
    [Adjustment]) consumes the open lots that expire first, so the points that leave first
    are the ones closest to expiring, even when entries were recorded out of time order.
    Under [After_days n], a lot expires at the end of the UTC day [n] days after the day
    it was earned; an expiry run on date [d] books one [Expire] entry for what is left of
    every lot whose expiry date is on or before [d]. The cause is [Expiry d], so running
    twice for the same date books once. *)

open! Core

module Policy : sig
  type t =
    | Never
    | After_days of int (** at least 1 *)
  [@@deriving sexp, compare, equal]

  (** Fails for [After_days n] with [n < 1]. *)
  val validate : t -> unit Or_error.t

  module Stable : sig
    module V1 : sig
      (** Reading validates. *)
      type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
    end
  end
end

(** The points still open, grouped by the date they expire, earliest first. Empty under
    [Never]. *)
val schedule : Policy.t -> Entry.t list -> (Date.t * int) list

(** What an expiry run on [as_of] takes: the open points of every lot expiring on or
    before [as_of]. *)
val due : Policy.t -> Entry.t list -> as_of:Date.t -> int
