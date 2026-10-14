(** What a points entry does to a balance. The kind follows from the entry's
    {!Cause.t}, so it is never stored apart from it. *)

open! Core

type t =
  | Earn (** points for settled spend; positive *)
  | Bonus (** points for a one-off action; positive *)
  | Reversal
  (** points taken back when a purchase is refunded; negative, or zero when the refund
      is too small to take a whole point back (it is still recorded, so later refunds
      of the same purchase are measured against the full refunded amount) *)
  | Redeem (** points spent on a redemption; negative *)
  | Adjustment (** a manual correction; either sign, never zero *)
  | Expire (** points that reached the end of their life; negative *)
[@@deriving sexp, compare, equal, hash, enumerate, quickcheck]

(** ["earn"], ["bonus"], ["reversal"], ["redeem"], ["adjustment"], ["expire"]. *)
val to_string : t -> string

(** Whether [points] has the sign this kind requires: positive for [Earn] and [Bonus],
    negative for [Redeem] and [Expire], zero or negative for [Reversal], non-zero for
    [Adjustment]. *)
val accepts : t -> points:int -> bool

(** Counted towards tiers: earned points net of clawbacks and adjustments. Redemptions
    and expiry spend points but do not lower a tier. *)
val counts_for_tier : t -> bool

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
