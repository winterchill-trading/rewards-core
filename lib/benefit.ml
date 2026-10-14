open! Core

module Stable = struct
  module V1 = struct
    type t =
      | Fx_spread_cap of { bps : int }
      | Fee_schedule of
          { product : string
          ; fee : Money.Fee.Stable.V2.t
          }
      | Perk of string
    [@@deriving bin_io, sexp, compare, equal]
  end
end

include Stable.V1

let validate = function
  | Fx_spread_cap { bps } when bps < 0 ->
    Or_error.error_s [%message "negative spread cap" (bps : int)]
  | Fee_schedule { product = ""; fee = _ } -> Or_error.error_s [%message "empty product"]
  | Perk "" -> Or_error.error_s [%message "empty perk"]
  | Fx_spread_cap _ | Fee_schedule _ | Perk _ -> Ok ()
;;
