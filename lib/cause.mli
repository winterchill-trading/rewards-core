(** Why an entry exists. A customer's ledger holds at most one entry per {!key}, which is
    what makes an event earn (or spend) once however often it is delivered: the settlement
    webhook arriving twice, a retried redemption, an expiry run started twice on the same
    day. *)

open! Core

type t =
  | Card_purchase of Source_id.t (** a settled card purchase, by its transaction id *)
  | Card_refund of
      { refund : Source_id.t (** the refund's transaction id; the key *)
      ; purchase : Source_id.t (** the purchase it refunds *)
      }
  | Action of Action.t (** a one-off action; earns once per customer *)
  | Redemption of Redemption_id.t
  | Adjustment of Source_id.t (** a manual correction, by its request id *)
  | Expiry of Date.t (** an expiry run covering lots that expired up to this date *)
[@@deriving sexp, compare, equal, hash, quickcheck]

(** The kind of entry this cause books. *)
val kind : t -> Kind.t

(** The uniqueness key: ["card_purchase:<id>"], ["card_refund:<id>"], ["action:<code>"],
    ["redemption:<id>"], ["adjustment:<id>"], ["expiry:<YYYY-MM-DD>"]. A refund's key
    names the refund only, so a refund cannot be booked against two purchases. *)
val key : t -> string

module Stable : sig
  module V1 : sig
    type nonrec t = t [@@deriving bin_io, sexp, compare, equal]
  end
end
