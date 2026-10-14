open! Core
open Rewards_core
open Helpers

let rules : (module Clawback_rule.S) list =
  [ (module Clawback_rule.Cumulative); (module Clawback_rule.Proportional) ]
;;

let name (module R : Clawback_rule.S) = R.name

(* Runs [refunds] in order through [Earn_rules.clawback_with] and prints each clawback. *)
let run ?(balance = Int.max_value) rule ~points ~spend refunds =
  let purchase = purchase_entry ~points ~spend:(eur spend) in
  let earlier = ref [] in
  List.map refunds ~f:(fun refund ->
    let taken, _ =
      Earn_rules.clawback_with
        ~rule
        ~purchase
        ~earlier:!earlier
        ~refund:(eur refund)
        ~balance
      |> Result.ok
      |> Option.value_exn
    in
    earlier
    := !earlier
       @ [ refund_entry ~seq:(List.length !earlier + 1) ~refund:(eur refund) ~points:taken
         ];
    taken)
;;

let%expect_test "cumulative and proportional rules on the same refunds" =
  (* 10.00 EUR earned 30 points, refunded in three thirds and then once more. *)
  List.iter rules ~f:(fun rule ->
    let taken = run rule ~points:30 ~spend:"10.00" [ "3.33"; "3.33"; "3.34"; "1.00" ] in
    print_s [%sexp (name rule : string), (taken : int list)]);
  [%expect {|
    (cumulative (9 10 11 0))
    (proportional (9 9 10 0))
    |}]
;;

let%expect_test "a full refund in one piece gives back everything under both rules" =
  List.iter rules ~f:(fun rule ->
    print_s
      [%sexp
        (name rule : string), (run rule ~points:7 ~spend:"0.03" [ "0.03" ] : int list)]);
  [%expect {|
    (cumulative (7))
    (proportional (7))
    |}]
;;

let%expect_test "flooring after multiplying takes points back from small refunds" =
  (* 1.00 EUR of 10.00 EUR that earned 30 points: floor (30 * 100 / 1000) = 3. Flooring
     the share first, floor (100 / 1000) = 0, would take back nothing. *)
  List.iter rules ~f:(fun rule ->
    print_s
      [%sexp
        (name rule : string), (run rule ~points:30 ~spend:"10.00" [ "1.00" ] : int list)]);
  [%expect {|
    (cumulative (3))
    (proportional (3))
    |}]
;;

let%expect_test "a rule's answer is clamped to what is left and to the balance" =
  let greedy : (module Clawback_rule.S) =
    (module struct
      let name = "greedy"
      let points ~earned:_ ~spend:_ ~refunded_before:_ ~refund:_ = 1_000_000
    end)
  in
  let negative : (module Clawback_rule.S) =
    (module struct
      let name = "negative"
      let points ~earned:_ ~spend:_ ~refunded_before:_ ~refund:_ = -5
    end)
  in
  print_s [%sexp (run greedy ~points:30 ~spend:"10.00" [ "1.00"; "1.00" ] : int list)];
  print_s [%sexp (run greedy ~balance:12 ~points:30 ~spend:"10.00" [ "1.00" ] : int list)];
  print_s [%sexp (run negative ~points:30 ~spend:"10.00" [ "1.00" ] : int list)];
  [%expect {|
    (30 0)
    (12)
    (0)
    |}]
;;

let%test_unit "the default rule is the one clawback uses" =
  Quickcheck.test
    (Quickcheck.Generator.tuple2 (Int.gen_incl 1 10_000) (Int.gen_incl 1 100_000))
    ~f:(fun (points, refund_cents) ->
      let purchase = purchase_entry ~points ~spend:(eur "100.00") in
      let refund = Money.Amount.of_minor_units_int Money.Currency.eur refund_cents in
      let points r = Result.ok r |> Option.value_exn |> fst in
      [%test_result: int]
        (points
           (Earn_rules.clawback ~purchase ~earlier:[] ~refund ~balance:Int.max_value))
        ~expect:
          (points
             (Earn_rules.clawback_with
                ~rule:Clawback_rule.default
                ~purchase
                ~earlier:[]
                ~refund
                ~balance:Int.max_value)))
;;

let%test_unit "every rule floors after multiplying" =
  (* For one refund of [r] from a spend of [s] that earned [p]: the answer [k] satisfies
     [k * s <= p * min (r, s) < (k + 1) * s], i.e. [k = floor (p * min (r, s) / s)]. *)
  Quickcheck.test
    (Quickcheck.Generator.tuple3
       (Int.gen_incl 0 1_000_000)
       (Int.gen_incl 1 10_000_000)
       (Int.gen_incl 1 20_000_000))
    ~f:(fun (p, s, r) ->
      let amount = Money.Amount.of_minor_units_int Money.Currency.eur in
      List.iter rules ~f:(fun (module R : Clawback_rule.S) ->
        let k =
          R.points
            ~earned:p
            ~spend:(amount s)
            ~refunded_before:(amount 0)
            ~refund:(amount r)
        in
        let product = p * Int.min r s in
        if not (k * s <= product && product < (k + 1) * s)
        then
          raise_s
            [%message
              "not floor after multiply"
                ~rule:R.name
                (p : int)
                (s : int)
                (r : int)
                (k : int)]))
;;

let%test_unit "refunds in pieces never give back more than earned" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind points = Int.gen_incl 1 5_000 in
    let%bind spend = Int.gen_incl 1 100_000 in
    let%map refunds = List.gen_non_empty (Int.gen_incl 1 50_000) in
    points, spend, refunds
  in
  Quickcheck.test gen ~trials:500 ~f:(fun (points, spend, refunds) ->
    let to_string c =
      Money.Amount.of_minor_units_int Money.Currency.eur c
      |> Money.Amount.to_decimal_string
    in
    let refunds = List.map refunds ~f:to_string in
    List.iter rules ~f:(fun rule ->
      let taken = run rule ~points ~spend:(to_string spend) refunds in
      let total = List.sum (module Int) taken ~f:Fn.id in
      assert (List.for_all taken ~f:(fun k -> k >= 0));
      assert (total <= points)))
;;

let%test_unit "the cumulative rule gives back everything once the spend is refunded" =
  let open Quickcheck.Generator.Let_syntax in
  let gen =
    let%bind points = Int.gen_incl 1 5_000 in
    let%bind spend = Int.gen_incl 1 100_000 in
    let%map cuts = List.gen_with_length 3 (Int.gen_incl 0 spend) in
    points, spend, cuts
  in
  Quickcheck.test gen ~trials:500 ~f:(fun (points, spend, cuts) ->
    (* Split the spend at the cut points into pieces; drop empty ones. *)
    let bounds = List.sort ~compare:Int.compare ((0 :: cuts) @ [ spend ]) in
    let pieces =
      List.zip_exn (List.drop_last_exn bounds) (List.tl_exn bounds)
      |> List.filter_map ~f:(fun (a, b) -> if b > a then Some (b - a) else None)
    in
    let to_string c =
      Money.Amount.of_minor_units_int Money.Currency.eur c
      |> Money.Amount.to_decimal_string
    in
    let taken =
      run
        Clawback_rule.default
        ~balance:Int.max_value
        ~points
        ~spend:(to_string spend)
        (List.map pieces ~f:to_string)
    in
    [%test_result: int] (List.sum (module Int) taken ~f:Fn.id) ~expect:points)
;;
