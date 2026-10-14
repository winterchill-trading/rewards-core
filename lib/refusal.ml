open! Core

type t =
  | Insufficient_points of
      { balance : int
      ; requested : int
      }
  | Too_small of { minimum : int }
  | Too_large of { maximum : int }
  | Not_a_step of { step : int }
  | Rate_unavailable of
      { from : Money.Currency.t
      ; to_ : Money.Currency.t
      }
  | Rate_mismatch of
      { from : Money.Currency.t
      ; to_ : Money.Currency.t
      ; rate_base : Money.Currency.t
      ; rate_quote : Money.Currency.t
      }
  | Rounds_to_zero
  | Unknown_action of Action.t
  | Cause_conflict of { key : string }
  | Redemption_conflict of { id : Redemption_id.t }
  | Currency_mismatch of
      { expected : Money.Currency.t
      ; got : Money.Currency.t
      }
  | Purchase_not_found of Source_id.t
  | Contended
  | Invalid of Error.t
[@@deriving sexp_of]

let code = function
  | Insufficient_points _ -> "INSUFFICIENT_POINTS"
  | Too_small _ -> "TOO_SMALL"
  | Too_large _ -> "TOO_LARGE"
  | Not_a_step _ -> "STEP"
  | Rate_unavailable _ -> "RATE_UNAVAILABLE"
  | Rate_mismatch _ -> "RATE_MISMATCH"
  | Rounds_to_zero -> "ROUNDS_TO_ZERO"
  | Unknown_action _ -> "UNKNOWN_ACTION"
  | Cause_conflict _ -> "CAUSE_CONFLICT"
  | Redemption_conflict _ -> "REDEMPTION_CONFLICT"
  | Currency_mismatch _ -> "CURRENCY_MISMATCH"
  | Purchase_not_found _ -> "PURCHASE_NOT_FOUND"
  | Contended -> "CONTENDED"
  | Invalid _ -> "INVALID"
;;

let to_error t = Error.create_s [%sexp (code t : string), (t : t)]
let of_or_error r = Result.map_error r ~f:(fun e -> Invalid e)
