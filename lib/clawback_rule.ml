open! Core
module Amount = Money.Amount

module type S = sig
  val name : string

  val points
    :  earned:int
    -> spend:Amount.t
    -> refunded_before:Amount.t
    -> refund:Amount.t
    -> int
end

(* [floor (earned * part / spend)]: multiply first, then floor, on exact integers. *)
let share ~earned ~part ~spend =
  let part = Z.max Z.zero (Z.min part spend) in
  Z.fdiv (Z.mul (Z.of_int earned) part) spend
;;

module Cumulative = struct
  let name = "cumulative"

  let points ~earned ~spend ~refunded_before ~refund =
    let spend = Amount.minor_units spend in
    let before = Amount.minor_units refunded_before in
    let after = Z.add before (Amount.minor_units refund) in
    (* The share for all refunds so far minus the share for those before this one, so
       rounding never adds up past the purchase. *)
    Z.to_int
      (Z.sub (share ~earned ~part:after ~spend) (share ~earned ~part:before ~spend))
  ;;
end

module Proportional = struct
  let name = "proportional"

  let points ~earned ~spend ~refunded_before ~refund =
    let spend = Amount.minor_units spend in
    let left = Z.sub spend (Amount.minor_units refunded_before) in
    Z.to_int (share ~earned ~part:(Z.min (Amount.minor_units refund) left) ~spend)
  ;;
end

let default : (module S) = (module Cumulative)
