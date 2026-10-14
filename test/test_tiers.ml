open! Core
open Rewards_core
open Helpers

let entry ~seq ~cause ~points ~at =
  Entry.create ~user ~seq ~cause ~points ~at () |> Or_error.ok_exn
;;

let day n = Time_ns.add t0 (Time_ns.Span.of_day (Float.of_int n))

let show (s : Tiers.Status.t) =
  print_s
    [%message
      ""
        ~tier:s.tier.code
        ~next:(Option.map s.next ~f:(fun (t : Tier.t) -> t.code) : string option)
        ~window:(s.window_points : int)
        ~to_next:(s.points_to_next : int option)
        ~progress:(s.progress_percent : int)]
;;

let%expect_test "tier follows the window total; redemptions do not lower it" =
  let entries =
    [ entry ~seq:0 ~cause:(Adjustment (src "a1")) ~points:1_499 ~at:(day 0)
    ; entry ~seq:1 ~cause:(Action (act "first_exchange")) ~points:1 ~at:(day 1)
    ; entry
        ~seq:2
        ~cause:(Redemption (Redemption_id.of_string "r1"))
        ~points:(-1_000)
        ~at:(day 2)
    ]
  in
  show (Tiers.status tiers [] ~now:(day 0));
  show (Tiers.status tiers (List.take entries 1) ~now:(day 0));
  show (Tiers.status tiers entries ~now:(day 2));
  (* 90 days after day 0 the first entry leaves the window: (now - 90d, now]. *)
  show (Tiers.status tiers entries ~now:(day 90));
  show (Tiers.status tiers entries ~now:(day 91));
  [%expect
    {|
    ((tier bronze) (next (silver)) (window 0) (to_next (1500)) (progress 0))
    ((tier bronze) (next (silver)) (window 1499) (to_next (1)) (progress 99))
    ((tier silver) (next (gold)) (window 1500) (to_next (3500)) (progress 0))
    ((tier bronze) (next (silver)) (window 1) (to_next (1499)) (progress 0))
    ((tier bronze) (next (silver)) (window 0) (to_next (1500)) (progress 0))
    |}]
;;

let%expect_test "top tier and benefits" =
  let gold = Tiers.tier_for tiers ~points:7_000 in
  show
    (Tiers.status
       tiers
       [ entry ~seq:0 ~cause:(Adjustment (src "a1")) ~points:7_000 ~at:t0 ]
       ~now:t0);
  let standard = Money.Fee.create Money.Currency.eur ~bps:50 |> Or_error.ok_exn in
  let usd_standard = Money.Fee.create Money.Currency.usd ~bps:50 |> Or_error.ok_exn in
  print_s
    [%message
      ""
        ~gold_spread:(Tier.fx_spread_bps gold ~standard:50 : int)
        ~silver_spread:
          (Tier.fx_spread_bps (Tiers.tier_for tiers ~points:1_500) ~standard:50 : int)
        ~bronze_spread:
          (Tier.fx_spread_bps (Tiers.tier_for tiers ~points:0) ~standard:50 : int)
        ~tight_standard:(Tier.fx_spread_bps gold ~standard:10 : int)
        ~eur_fee:(Tier.fee gold ~product:"exchange" ~standard : Money.Fee.t)
        ~usd_fee:(Tier.fee gold ~product:"exchange" ~standard:usd_standard : Money.Fee.t)
        ~atm_fee:(Tier.fee gold ~product:"atm" ~standard : Money.Fee.t)];
  [%expect
    {|
    ((tier gold) (next ()) (window 7000) (to_next ()) (progress 100))
    ((gold_spread 20) (silver_spread 35) (bronze_spread 50) (tight_standard 10)
     (eur_fee ((currency EUR) (fixed "0.00 EUR") (bps 10) (min ()) (max ())))
     (usd_fee ((currency USD) (fixed "0.00 USD") (bps 50) (min ()) (max ())))
     (atm_fee ((currency EUR) (fixed "0.00 EUR") (bps 50) (min ()) (max ()))))
    |}]
;;

let%expect_test "ladder validation" =
  let show tiers =
    print_s
      [%sexp
        (Tiers.create ~window:(Time_ns.Span.of_day 90.) tiers |> Or_error.ignore_m
         : unit Or_error.t)]
  in
  show [];
  show [ tier "a" 10 ];
  show [ tier "a" 0; tier "b" 10; tier "c" 10 ];
  show [ tier "a" 0; tier "a" 10 ];
  [%expect
    {|
    (Error "no tiers")
    (Error ("the first tier's threshold must be 0" (code a)))
    (Error ("thresholds must strictly increase" (at c)))
    (Error ("repeated tier code" (code a)))
    |}]
;;
