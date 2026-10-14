open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Card_purchase of Source_id.Stable.V1.t
      | Card_refund of
          { refund : Source_id.Stable.V1.t
          ; purchase : Source_id.Stable.V1.t
          }
      | Action of Action.Stable.V1.t
      | Redemption of Redemption_id.Stable.V1.t
      | Adjustment of Source_id.Stable.V1.t
      | Expiry of Date.Stable.V1.t
    [@@deriving bin_io, sexp, compare, equal, hash]
  end
end

type t = Stable.V1.t =
  | Card_purchase of Source_id.t
  | Card_refund of
      { refund : Source_id.t
      ; purchase : Source_id.t
      }
  | Action of Action.t
  | Redemption of Redemption_id.t
  | Adjustment of Source_id.t
  | Expiry of Date.t
[@@deriving sexp, compare, equal, hash, quickcheck]

let kind : t -> Kind.t = function
  | Card_purchase _ -> Earn
  | Card_refund _ -> Reversal
  | Action _ -> Bonus
  | Redemption _ -> Redeem
  | Adjustment _ -> Adjustment
  | Expiry _ -> Expire
;;

let key = function
  | Card_purchase id -> "card_purchase:" ^ Source_id.to_string id
  | Card_refund { refund; purchase = _ } -> "card_refund:" ^ Source_id.to_string refund
  | Action a -> "action:" ^ Action.to_string a
  | Redemption id -> "redemption:" ^ Redemption_id.to_string id
  | Adjustment id -> "adjustment:" ^ Source_id.to_string id
  | Expiry date -> "expiry:" ^ Date.to_string date
;;
