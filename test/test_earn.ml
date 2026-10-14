open! Core
open Rewards_core
open Helpers

let show r =
  match r with
  | Ok (points, (e : Earning.t)) ->
    print_s
      [%message
        ""
          (points : int)
          ~basis:(Money.Amount.to_string e.basis_amount)
          ~multiplier:(e.multiplier : int)]
  | Error refusal -> print_s [%message "refused" (refusal : Refusal.t)]
;;

let%expect_test "purchases earn floor(basis units) x multiplier" =
  let p spend category rate =
    show (Earn_rules.purchase earn_rules ~spend ~category:(cat category) ~rate)
  in
  p (eur "12.99") "shopping" None;
  p (eur "12.99") "travel" None;
  p (eur "12.99") "groceries" None;
  p (eur "500.00") "cash" None;
  p (eur "0.99") "shopping" None;
  [%expect
    {|
    ((points 12) (basis "12.99 EUR") (multiplier 1))
    ((points 36) (basis "12.99 EUR") (multiplier 3))
    ((points 24) (basis "12.99 EUR") (multiplier 2))
    ((points 0) (basis "500.00 EUR") (multiplier 0))
    ((points 0) (basis "0.99 EUR") (multiplier 1))
    |}]
;;

let%expect_test "foreign spend converts at the given rate, in either direction" =
  (* 110.00 USD at 1 EUR = 1.10 USD is exactly 100 EUR; 109.99 USD is 99.99... EUR. *)
  show
    (Earn_rules.purchase
       earn_rules
       ~spend:(usd "110.00")
       ~category:(cat "x")
       ~rate:(Some eur_usd));
  show
    (Earn_rules.purchase
       earn_rules
       ~spend:(usd "109.99")
       ~category:(cat "x")
       ~rate:(Some eur_usd));
  show
    (Earn_rules.purchase
       earn_rules
       ~spend:(usd "110.00")
       ~category:(cat "x")
       ~rate:(Some (Money.Rate.inverse eur_usd)));
  show
    (Earn_rules.purchase earn_rules ~spend:(usd "10.00") ~category:(cat "x") ~rate:None);
  show
    (Earn_rules.purchase
       earn_rules
       ~spend:(usd "10.00")
       ~category:(cat "x")
       ~rate:(Some eur_gbp));
  show
    (Earn_rules.purchase earn_rules ~spend:(eur "-1.00") ~category:(cat "x") ~rate:None);
  [%expect
    {|
    ((points 100) (basis "100.00 EUR") (multiplier 1))
    ((points 99) (basis "99.99 EUR") (multiplier 1))
    ((points 100) (basis "100.00 EUR") (multiplier 1))
    (refused (refusal (Rate_unavailable (from USD) (to_ EUR))))
    (refused
     (refusal
      (Rate_mismatch (from USD) (to_ EUR) (rate_base EUR) (rate_quote GBP))))
    (refused (refusal (Invalid ("spend must be positive" (spend "-1.00 EUR")))))
    |}]
;;

let purchase_entry ~points ~spend =
  let _, earning =
    Earn_rules.purchase earn_rules ~spend ~category:(cat "travel") ~rate:None
    |> Result.ok
    |> Option.value_exn
  in
  Entry.create ~user ~seq:0 ~cause:(Card_purchase (src "p1")) ~points ~at:t0 ~earning ()
  |> Or_error.ok_exn
;;

let refund_entry ~seq ~refund ~points =
  let _, earning =
    Earn_rules.purchase earn_rules ~spend:refund ~category:(cat "travel") ~rate:None
    |> Result.ok
    |> Option.value_exn
  in
  Entry.create
    ~user
    ~seq
    ~cause:(Card_refund { refund = src (sprintf "r%d" seq); purchase = src "p1" })
    ~points:(-points)
    ~at:t0
    ~earning
    ()
  |> Or_error.ok_exn
;;

let%expect_test "refunds claw back in proportion and never more than earned" =
  (* 10.00 EUR of travel earned 30 points. A refund too small for a whole point is still
     counted by the next one; refunds beyond the purchase take nothing more. *)
  let purchase = purchase_entry ~points:30 ~spend:(eur "10.00") in
  let earlier = ref [] in
  List.iter [ "0.01"; "3.32"; "3.33"; "3.33"; "0.01"; "5.00" ] ~f:(fun refund ->
    match
      Earn_rules.clawback ~purchase ~earlier:!earlier ~refund:(eur refund) ~balance:1_000
    with
    | Error refusal -> print_s [%message "refused" (refusal : Refusal.t)]
    | Ok (points, _) ->
      printf "refund %s -> %d\n" refund points;
      earlier
      := !earlier
         @ [ refund_entry ~seq:(List.length !earlier + 1) ~refund:(eur refund) ~points ]);
  [%expect
    {|
    refund 0.01 -> 0
    refund 3.32 -> 9
    refund 3.33 -> 10
    refund 3.33 -> 10
    refund 0.01 -> 1
    refund 5.00 -> 0
    |}]
;;

let%expect_test "a clawback is capped at the balance" =
  let purchase = purchase_entry ~points:30 ~spend:(eur "10.00") in
  let show r =
    match r with
    | Ok (points, _) -> printf "%d\n" points
    | Error refusal -> print_s [%message "refused" (refusal : Refusal.t)]
  in
  show (Earn_rules.clawback ~purchase ~earlier:[] ~refund:(eur "10.00") ~balance:12);
  show (Earn_rules.clawback ~purchase ~earlier:[] ~refund:(usd "10.00") ~balance:12);
  [%expect
    {|
    12
    (refused (refusal (Currency_mismatch (expected EUR) (got USD))))
    |}]
;;

let%expect_test "rule validation" =
  let show r = print_s [%sexp (Or_error.ignore_m r : unit Or_error.t)] in
  show (Earn_rules.create ~basis:Money.Currency.eur ~multipliers:[ cat "a", -1 ] ());
  show
    (Earn_rules.create
       ~basis:Money.Currency.eur
       ~multipliers:[ cat "a", 1; cat "a", 2 ]
       ());
  show (Earn_rules.create ~basis:Money.Currency.eur ~bonuses:[ act "a", 0 ] ());
  [%expect
    {|
    (Error ("negative multiplier" (c a) (x -1)))
    (Error ("category listed twice" (c a)))
    (Error ("bonus must be positive" (a a) (x 0)))
    |}]
;;
