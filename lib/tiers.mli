(** The tier ladder and the rolling window it is measured over.

    A customer's tier is the highest tier whose threshold is at most the points they
    earned in the last [window] (entries with [now - window < at <= now]). Earned means
    [Earn], [Bonus], [Reversal] and [Adjustment] entries ({!Kind.counts_for_tier}):
    spending points on a redemption, or losing them to expiry, never lowers a tier, while
    a refunded purchase no longer counts. The window total is floored at zero. *)

open! Core

type t = private
  { window : Time_ns.Span.t
  ; tiers : Tier.t list (** ascending thresholds, the first at 0 *)
  }
[@@deriving sexp_of, compare, equal]

(** Fails on an empty ladder, a first threshold other than 0, thresholds that do not
    strictly increase, a repeated code or a window that is not positive. *)
val create : window:Time_ns.Span.t -> Tier.t list -> t Or_error.t

(** The tier with this code. *)
val find : t -> string -> Tier.t option

(** The tier for a number of window points. *)
val tier_for : t -> points:int -> Tier.t

module Status : sig
  type t =
    { tier : Tier.t
    ; next : Tier.t option (** [None] at the top *)
    ; window_points : int
    ; points_to_next : int option (** [None] at the top *)
    ; progress_percent : int
    (** through the current tier towards the next, 0 to 99; 100 at the top *)
    }
  [@@deriving sexp_of, compare, equal]
end

(** The window total of a customer's entries at [now]. *)
val window_points : t -> Entry.t list -> now:Time_ns.t -> int

(** Where a customer stands at [now]. *)
val status : t -> Entry.t list -> now:Time_ns.t -> Status.t

module Stable : sig
  module V1 : sig
    (** Reading validates like {!create}. *)
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
