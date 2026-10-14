open! Core
module Currency = Money.Currency

let orient rate ~from ~to_ =
  let base = Money.Rate.base rate
  and quote = Money.Rate.quote rate in
  if Currency.equal base from && Currency.equal quote to_
  then Some rate
  else if Currency.equal base to_ && Currency.equal quote from
  then Some (Money.Rate.inverse rate)
  else None
;;

let major_units amount ~to_ ~rate =
  let from = Money.Amount.currency amount in
  if Currency.equal from to_
  then Ok (Money.Amount.to_q amount)
  else (
    match rate with
    | None -> Error (Refusal.Rate_unavailable { from; to_ })
    | Some rate ->
      (match orient rate ~from ~to_ with
       | Some rate -> Ok (Q.mul (Money.Amount.to_q amount) (Money.Rate.price rate))
       | None ->
         Error
           (Rate_mismatch
              { from
              ; to_
              ; rate_base = Money.Rate.base rate
              ; rate_quote = Money.Rate.quote rate
              })))
;;
