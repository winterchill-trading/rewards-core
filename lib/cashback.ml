open! Core
module Amount = Money.Amount

module Rules = struct
  module Repr = struct
    type t =
      { step : int
      ; value_per_step : Money.Amount.Stable.V1.t
      ; minimum : int
      ; maximum : int
      }
    [@@deriving bin_io, sexp, compare, equal]
  end

  type t = Repr.t =
    { step : int
    ; value_per_step : Money.Amount.t
    ; minimum : int
    ; maximum : int
    }
  [@@deriving sexp_of, compare, equal]

  let validate t =
    if t.step <= 0
    then Or_error.error_s [%message "step must be positive" ~step:(t.step : int)]
    else if not (Amount.is_positive t.value_per_step)
    then Or_error.error_s [%message "value per step must be positive"]
    else if t.minimum % t.step <> 0 || t.maximum % t.step <> 0
    then Or_error.error_s [%message "minimum and maximum must be multiples of the step"]
    else if t.minimum < t.step || t.maximum < t.minimum
    then Or_error.error_s [%message "need step <= minimum <= maximum"]
    else Ok t
  ;;

  let create ~step ~value_per_step ~minimum ~maximum =
    validate { step; value_per_step; minimum; maximum }
  ;;

  let basis t = Amount.currency t.value_per_step

  let redeemable t ~balance =
    let points = Int.min (balance - (balance % t.step)) t.maximum in
    if points < t.minimum then 0 else points
  ;;

  module Stable = struct
    module V1 = struct
      include Repr

      let t_of_sexp s = Or_error.ok_exn (validate (t_of_sexp s))

      include
        Binable.Of_binable_without_uuid [@alert "-legacy"]
          (Repr)
          (struct
            type nonrec t = t

            let to_binable = Fn.id
            let of_binable t = Or_error.ok_exn (validate t)
          end)
    end
  end
end

module Quote = struct
  module Stable = struct
    module V1 = struct
      type t =
        { points : int
        ; value : Money.Amount.Stable.V1.t
        ; amount : Money.Amount.Stable.V1.t
        ; rate : Money.Rate.Stable.V1.t option
        }
      [@@deriving bin_io, sexp, compare, equal]
    end
  end

  include Stable.V1
end

let quote (rules : Rules.t) ~points ~balance ~currency ~rate
  : (Quote.t, Refusal.t) Result.t
  =
  let open Result.Let_syntax in
  if points < rules.minimum
  then Error (Too_small { minimum = rules.minimum })
  else if points > rules.maximum
  then Error (Too_large { maximum = rules.maximum })
  else if points % rules.step <> 0
  then Error (Not_a_step { step = rules.step })
  else if points > balance
  then Error (Insufficient_points { balance; requested = points })
  else (
    let value = Amount.scale rules.value_per_step (points / rules.step) in
    let basis = Rules.basis rules in
    let%bind q = Convert.major_units value ~to_:currency ~rate in
    let amount = Amount.of_q ~rounding:Down currency q in
    let rate =
      if Money.Currency.equal basis currency
      then None
      else Option.bind rate ~f:(fun r -> Convert.orient r ~from:basis ~to_:currency)
    in
    if Amount.is_positive amount
    then Ok { Quote.points; value; amount; rate }
    else Error Rounds_to_zero)
;;
