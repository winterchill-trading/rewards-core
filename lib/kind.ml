open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Earn
      | Bonus
      | Reversal
      | Redeem
      | Adjustment
      | Expire
    [@@deriving bin_io, sexp, compare, equal, hash, enumerate, quickcheck]
  end
end

include Stable.V1

let to_string t = String.lowercase (Sexp.to_string (sexp_of_t t))

let accepts t ~points =
  match t with
  | Earn | Bonus -> points > 0
  | Reversal | Redeem | Expire -> points < 0
  | Adjustment -> points <> 0
;;

let counts_for_tier = function
  | Earn | Bonus | Reversal | Adjustment -> true
  | Redeem | Expire -> false
;;
