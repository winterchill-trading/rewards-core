(** Why the programme refused an operation, as data, so a service can map each case to
    its own error codes and messages. *)

open! Core

type t =
  | Insufficient_points of
      { balance : int
      ; requested : int
      } (** the entry would take the balance below zero *)
  | Too_small of { minimum : int } (** fewer points than a redemption's minimum *)
  | Too_large of { maximum : int } (** more points than a redemption's maximum *)
  | Not_a_step of { step : int } (** a redemption that is not a multiple of the step *)
  | Rate_unavailable of
      { from : Money.Currency.t
      ; to_ : Money.Currency.t
      } (** no exchange rate was given for a conversion that needs one *)
  | Rate_mismatch of
      { from : Money.Currency.t
      ; to_ : Money.Currency.t
      ; rate_base : Money.Currency.t
      ; rate_quote : Money.Currency.t
      } (** the rate given converts between other currencies *)
  | Rounds_to_zero (** the redemption would pay nothing in the account's currency *)
  | Unknown_action of Action.t (** no bonus is configured for this action *)
  | Cause_conflict of { key : string }
  (** the cause is booked already, with different content *)
  | Redemption_conflict of { id : Redemption_id.t }
  (** the redemption id is taken by a different request *)
  | Currency_mismatch of
      { expected : Money.Currency.t
      ; got : Money.Currency.t
      }
  | Purchase_not_found of Source_id.t (** a refund names a purchase that earned nothing *)
  | Contended
  (** other writers kept changing the customer's ledger; the operation can be retried *)
  | Invalid of Error.t (** malformed input, with the reason *)
[@@deriving sexp_of]

(** A stable upper-case code per case: [INSUFFICIENT_POINTS], [TOO_SMALL], [TOO_LARGE],
    [STEP], [RATE_UNAVAILABLE], [RATE_MISMATCH], [ROUNDS_TO_ZERO], [UNKNOWN_ACTION],
    [CAUSE_CONFLICT], [REDEMPTION_CONFLICT], [CURRENCY_MISMATCH], [PURCHASE_NOT_FOUND],
    [CONTENDED], [INVALID]. *)
val code : t -> string

(** The refusal as an error, its code first. *)
val to_error : t -> Error.t

(** [Ok] or [Invalid] of the error. *)
val of_or_error : 'a Or_error.t -> ('a, t) Result.t
