open! Core

module Stable = struct
  module V1 = struct
    type t =
      { spend : Money.Amount.Stable.V1.t
      ; basis_amount : Money.Amount.Stable.V1.t
      ; rate : Money.Rate.Stable.V1.t option
      ; category : Category.Stable.V1.t
      ; multiplier : int
      }
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1
