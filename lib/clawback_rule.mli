(** How many points a refund takes back from the purchase it refunds.

    A rule sees the purchase's points and spend, the amount refunded before this refund
    and this refund's amount, all in the purchase currency, and answers the points this
    refund takes back. {!Earn_rules.clawback_with} then caps the answer so a purchase
    never gives back more than it earned and a customer's balance never goes below zero,
    whatever the rule.

    Both rules here multiply before they floor: the points are
    [floor (earned * amount / spend)] computed on exact integers, never
    [earned * floor (amount / spend)], which would take back nothing for any partial
    refund. *)

open! Core

module type S = sig
  (** A short name for logs and statements, such as ["cumulative"]. *)
  val name : string

  (** Points taken back by a refund of [refund] after [refunded_before] had been refunded
      from a purchase of [spend] that earned [earned]. [spend] and [refund] are positive,
      [refunded_before] is zero or positive and may already exceed [spend]; all three are
      in the same currency. The answer should be zero or positive; a negative answer is
      treated as zero. *)
  val points
    :  earned:int
    -> spend:Money.Amount.t
    -> refunded_before:Money.Amount.t
    -> refund:Money.Amount.t
    -> int
end

(** The default rule. After refunds totalling [r] the purchase has given back
    [floor (earned * min (r, spend) / spend)] points in all; each refund takes the
    difference from the total before it. A full refund, in one piece or many, gives back
    exactly [earned]. *)
module Cumulative : S

(** Proportional, floor after multiply, per refund: each refund takes back
    [floor (earned * min (refund, spend - refunded_before) / spend)] on its own. Refunds
    beyond the spend take nothing. Every refund rounds down separately, so a purchase
    refunded in several pieces may give back a few points less than [earned]; a full
    refund in one piece gives back exactly [earned]. *)
module Proportional : S

(** {!Cumulative}. *)
val default : (module S)
