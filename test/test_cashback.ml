open! Core
open Rewards_core
open Helpers

let show r =
  match r with
  | Ok (q : Cashback.Quote.t) ->
    print_s
      [%message
        ""
          ~points:(q.points : int)
          ~value:(Money.Amount.to_string q.value)
          ~amount:(Money.Amount.to_string q.amount)]
  | Error refusal -> print_s [%message (Refusal.code refusal) (refusal : Refusal.t)]
;;

let%expect_test "quotes: 100 points = 0.50 in steps of 100, between 1,000 and 1,000,000" =
  let q ?(balance = 50_000) ?(currency = Money.Currency.eur) ?rate points =
    show (Cashback.quote cashback ~points ~balance ~currency ~rate)
  in
  q 1_000;
  q 2_300;
  q 900;
  q 1_000_100 ~balance:2_000_000;
  q 1_050;
  q 60_000;
  (* 11.50 EUR at 1 EUR = 1.10 USD is 12.65 USD exactly; at 0.85 GBP, 9.775 rounds down. *)
  q 2_300 ~currency:Money.Currency.usd ~rate:eur_usd;
  q 2_300 ~currency:Money.Currency.gbp ~rate:eur_gbp;
  q 2_300 ~currency:Money.Currency.gbp ~rate:(Money.Rate.inverse eur_gbp);
  q 2_300 ~currency:Money.Currency.gbp;
  [%expect
    {|
    ((points 1000) (value "5.00 EUR") (amount "5.00 EUR"))
    ((points 2300) (value "11.50 EUR") (amount "11.50 EUR"))
    (TOO_SMALL (refusal (Too_small (minimum 1000))))
    (TOO_LARGE (refusal (Too_large (maximum 1000000))))
    (STEP (refusal (Not_a_step (step 100))))
    (INSUFFICIENT_POINTS
     (refusal (Insufficient_points (balance 50000) (requested 60000))))
    ((points 2300) (value "11.50 EUR") (amount "12.65 USD"))
    ((points 2300) (value "11.50 EUR") (amount "9.77 GBP"))
    ((points 2300) (value "11.50 EUR") (amount "9.77 GBP"))
    (RATE_UNAVAILABLE (refusal (Rate_unavailable (from EUR) (to_ GBP))))
    |}]
;;

let%expect_test "a conversion that pays nothing is refused" =
  let rules =
    Cashback.Rules.create ~step:1 ~value_per_step:(eur "0.01") ~minimum:1 ~maximum:10
    |> Or_error.ok_exn
  in
  let tiny = rate ~base:Money.Currency.eur ~quote:Money.Currency.usd "0.5" in
  show
    (Cashback.quote
       rules
       ~points:1
       ~balance:10
       ~currency:Money.Currency.usd
       ~rate:(Some tiny));
  [%expect {| (ROUNDS_TO_ZERO (refusal Rounds_to_zero)) |}]
;;

let%expect_test "redeemable points" =
  List.iter [ 0; 999; 1_000; 1_099; 2_345; 5_000_000 ] ~f:(fun balance ->
    printf "%d -> %d\n" balance (Cashback.Rules.redeemable cashback ~balance));
  [%expect
    {|
    0 -> 0
    999 -> 0
    1000 -> 1000
    1099 -> 1000
    2345 -> 2300
    5000000 -> 1000000
    |}]
;;

let%expect_test "rules validation" =
  let show ~step ~minimum ~maximum =
    print_s
      [%sexp
        (Cashback.Rules.create ~step ~value_per_step:(eur "0.50") ~minimum ~maximum
         |> Or_error.ignore_m
         : unit Or_error.t)]
  in
  show ~step:0 ~minimum:0 ~maximum:0;
  show ~step:100 ~minimum:150 ~maximum:1_000;
  show ~step:100 ~minimum:1_000 ~maximum:500;
  [%expect
    {|
    (Error ("step must be positive" (step 0)))
    (Error "minimum and maximum must be multiples of the step")
    (Error "need step <= minimum <= maximum")
    |}]
;;
