open! Core
open Rewards_core
open Helpers

let customer = Ledger.Account_id.of_string "customer:user-1/eur"
let customer_usd = Ledger.Account_id.of_string "customer:user-1/usd"
let day n = Time_ns.add t0 (Time_ns.Span.of_day (Float.of_int n))

let%expect_test "earn, refund, bonus and adjust are idempotent by cause" =
  let e = engine () in
  let settle ?(spend = eur "45.80") ?(category = "travel") id =
    Rewards.settle_purchase
      e
      ~user
      ~purchase:(src id)
      ~spend
      ~category:(cat category)
      ~rate:None
      ~at:t0
    |> print_outcome
  in
  settle "tx-1";
  settle "tx-1";
  settle "tx-1" ~spend:(eur "45.81");
  settle "tx-2" ~category:"cash";
  Rewards.settle_purchase
    e
    ~user
    ~purchase:(src "tx-3")
    ~spend:(usd "22.00")
    ~category:(cat "groceries")
    ~rate:None
    ~at:t0
  |> print_outcome;
  Rewards.settle_purchase
    e
    ~user
    ~purchase:(src "tx-3")
    ~spend:(usd "22.00")
    ~category:(cat "groceries")
    ~rate:(Some eur_usd)
    ~at:t0
  |> print_outcome;
  let refund id amount =
    Rewards.refund_purchase
      e
      ~user
      ~refund:(src id)
      ~purchase:(src "tx-1")
      ~amount:(eur amount)
      ~at:(day 1)
    |> print_outcome
  in
  refund "rf-1" "22.90";
  refund "rf-1" "22.90";
  refund "rf-2" "0.10";
  Rewards.refund_purchase
    e
    ~user
    ~refund:(src "rf-3")
    ~purchase:(src "tx-2")
    ~amount:(eur "1.00")
    ~at:(day 1)
  |> print_outcome;
  let action a = Rewards.complete_action e ~user ~action:(act a) ~at:(day 2) |> print_outcome in
  action "first_exchange";
  action "first_exchange";
  action "first_flight";
  let adjust id points =
    Rewards.adjust e ~user ~id:(src id) ~points ~reason:"goodwill" ~at:(day 3)
    |> print_outcome
  in
  adjust "adj-1" 40;
  adjust "adj-1" 41;
  adjust "adj-2" (-10_000);
  printf "balance %d\n" (balance e user);
  [%expect
    {|
    booked +135 (card_purchase:tx-1)
    already booked +135 (card_purchase:tx-1)
    (refused (refusal (Cause_conflict (key card_purchase:tx-1))))
    nothing to book
    (refused (refusal (Rate_unavailable (from USD) (to_ EUR))))
    booked +40 (card_purchase:tx-3)
    booked -67 (card_refund:rf-1)
    already booked -67 (card_refund:rf-1)
    booked +0 (card_refund:rf-2)
    nothing to book
    booked +250 (action:first_exchange)
    already booked +250 (action:first_exchange)
    (refused (refusal (Unknown_action first_flight)))
    booked +40 (adjustment:adj-1)
    (refused (refusal (Cause_conflict (key adjustment:adj-1))))
    (refused (refusal (Insufficient_points (balance 398) (requested 10000))))
    balance 398
    |}]
;;

let ledger () =
  let accounts =
    Ledger.Account.create ~purpose:Customer_funds customer Liability
    :: Ledger.Account.create ~purpose:Customer_funds customer_usd Liability
    :: Booking.Chart.accounts
         Booking.Chart.default
         ~currencies:[ Money.Currency.eur; Money.Currency.usd ]
  in
  List.fold accounts ~init:Ledger.Balances.empty ~f:(fun b a ->
    Ledger.Balances.apply b { seq = Ledger.Balances.next_seq b; event = Account_opened a }
    |> Or_error.ok_exn)
;;

let show_redemption r =
  match r with
  | Error refusal -> print_s [%message "refused" (refusal : Refusal.t)]
  | Ok (r : Redemption.t) ->
    print_s
      [%message
        ""
          ~id:(r.id : Redemption_id.t)
          ~status:(r.status : Redemption.Status.t)
          ~points:(r.quote.points : int)
          ~amount:(Money.Amount.to_string r.quote.amount)]
;;

let%expect_test "cashback redemption: points spent once, cash booked once" =
  let e = engine () in
  ignore (Rewards.adjust e ~user ~id:(src "seed") ~points:2_345 ~reason:"seed" ~at:t0 : _);
  let redeem ?(account = customer) ?(currency = Money.Currency.eur) ?rate ?(points = 2_300) id =
    Rewards.redeem
      e
      ~id:(Redemption_id.of_string id)
      ~user
      ~account
      ~currency
      ~points
      ~rate
      ~now:(day 1)
  in
  let r = redeem "rd-1" in
  show_redemption r;
  show_redemption (redeem "rd-1");
  show_redemption (redeem "rd-1" ~points:1_000);
  show_redemption (redeem "rd-2" ~points:1_000);
  printf "balance %d\n" (balance e user);
  (* The cash side: the same redemption booked twice is one ledger entry. *)
  let r = Result.ok r |> Option.value_exn in
  let entry =
    Booking.cashback Booking.Chart.default r ~recorded_at:(day 1) |> Or_error.ok_exn
  in
  let b = Booking.apply (ledger ()) [ entry ] |> Or_error.ok_exn in
  print_s
    [%message
      ""
        ~key:(entry.idempotency_key : Ledger.Idempotency_key.t)
        ~customer:
          (Money.Amount.to_string
             (Ledger.Balances.available b customer Money.Currency.eur))
        ~expense:
          (Money.Amount.to_string
             (Ledger.Balances.balance
                b
                (Booking.Chart.default.rewards_expense Money.Currency.eur)
                Money.Currency.eur))];
  print_s
    [%sexp
      (Booking.apply b [ entry ] |> Or_error.ignore_m |> Result.is_error : bool)];
  [%expect
    {|
    ((id rd-1) (status Completed) (points 2300) (amount "11.50 EUR"))
    ((id rd-1) (status Completed) (points 2300) (amount "11.50 EUR"))
    (refused (refusal (Redemption_conflict (id rd-1))))
    (refused (refusal (Insufficient_points (balance 45) (requested 1000))))
    balance 45
    ((key rewards:redemption:rd-1) (customer "11.50 EUR") (expense "11.50 EUR"))
    true
    |}]
;;

let%expect_test "a redemption interrupted after it was recorded finishes as priced" =
  let store = Store.create () in
  let e = Rewards.create (program ()) store in
  ignore (Rewards.adjust e ~user ~id:(src "seed") ~points:5_000 ~reason:"seed" ~at:t0 : _);
  (* A crash right after the insert: the record is Accepted, no points spent yet. *)
  let quote =
    Cashback.quote cashback ~points:2_000 ~balance:5_000 ~currency:Money.Currency.usd
      ~rate:(Some eur_usd)
    |> Result.ok
    |> Option.value_exn
  in
  let accepted =
    Redemption.create
      ~id:(Redemption_id.of_string "rd-9")
      ~user
      ~account:customer_usd
      ~quote
      ~created_at:t0
  in
  ignore (Store.insert_redemption store accepted : Store_types.Insert.t);
  (* The retry carries a different rate; the stored price wins. *)
  let other_rate = rate ~base:Money.Currency.eur ~quote:Money.Currency.usd "2.00" in
  show_redemption
    (Rewards.redeem
       e
       ~id:accepted.id
       ~user
       ~account:customer_usd
       ~currency:Money.Currency.usd
       ~points:2_000
       ~rate:(Some other_rate)
       ~now:(day 5));
  printf "balance %d\n" (balance e user);
  [%expect
    {|
    ((id rd-9) (status Completed) (points 2000) (amount "11.00 USD"))
    balance 3000
    |}]
;;

let%expect_test "a redemption whose points vanished in the meantime is refused" =
  let store = Store.create () in
  let e = Rewards.create (program ()) store in
  ignore (Rewards.adjust e ~user ~id:(src "seed") ~points:1_000 ~reason:"seed" ~at:t0 : _);
  let quote =
    Cashback.quote cashback ~points:1_000 ~balance:1_000 ~currency:Money.Currency.eur
      ~rate:None
    |> Result.ok
    |> Option.value_exn
  in
  let accepted =
    Redemption.create
      ~id:(Redemption_id.of_string "rd-8")
      ~user
      ~account:customer
      ~quote
      ~created_at:t0
  in
  ignore (Store.insert_redemption store accepted : Store_types.Insert.t);
  ignore (Rewards.adjust e ~user ~id:(src "fix") ~points:(-500) ~reason:"fix" ~at:t0 : _);
  let again () =
    Rewards.redeem
      e
      ~id:accepted.id
      ~user
      ~account:customer
      ~currency:Money.Currency.eur
      ~points:1_000
      ~rate:None
      ~now:(day 1)
    |> show_redemption
  in
  again ();
  again ();
  print_s
    [%sexp
      (Booking.cashback Booking.Chart.default
         (Store.redemptions store |> List.hd_exn)
         ~recorded_at:t0
       |> Or_error.ignore_m
       : unit Or_error.t)];
  [%expect
    {|
    ((id rd-8) (status (Refused (code INSUFFICIENT_POINTS))) (points 1000)
     (amount "5.00 EUR"))
    ((id rd-8) (status (Refused (code INSUFFICIENT_POINTS))) (points 1000)
     (amount "5.00 EUR"))
    (Error
     ("only a completed redemption is paid" (id rd-8)
      (status (Refused (code INSUFFICIENT_POINTS)))))
    |}]
;;

let%expect_test "expiry runs book once per date" =
  let e = engine ~expiry:(After_days 30) () in
  ignore (Rewards.adjust e ~user ~id:(src "a") ~points:100 ~reason:"" ~at:t0 : _);
  ignore (Rewards.adjust e ~user ~id:(src "b") ~points:60 ~reason:"" ~at:(day 10) : _);
  ignore (Rewards.adjust e ~user ~id:(src "c") ~points:(-30) ~reason:"" ~at:(day 11) : _);
  let run d =
    List.iter
      (Rewards.expire_all e ~as_of:(Date.of_string d) ~at:(day 40))
      ~f:(fun (u, r) ->
        printf "%s %s: " d (User_id.to_string u);
        print_outcome r)
  in
  run "2026-03-30";
  run "2026-03-31";
  run "2026-03-31";
  run "2026-04-10";
  printf "balance %d\n" (balance e user);
  [%expect
    {|
    2026-03-30 user-1: nothing to book
    2026-03-31 user-1: booked -70 (expiry:2026-03-31)
    2026-03-31 user-1: already booked -70 (expiry:2026-03-31)
    2026-04-10 user-1: booked -60 (expiry:2026-04-10)
    balance 0
    |}]
;;

let%expect_test "summary and statement" =
  let e = engine ~expiry:(After_days 365) () in
  let settle id spend at =
    ignore
      (Rewards.settle_purchase
         e
         ~user
         ~purchase:(src id)
         ~spend:(eur spend)
         ~category:(cat "travel")
         ~rate:None
         ~at
       : _)
  in
  settle "tx-1" "300.00" t0;
  settle "tx-2" "250.00" (day 20);
  ignore (Rewards.complete_action e ~user ~action:(act "first_goal") ~at:(day 21) : _);
  ignore
    (Rewards.redeem
       e
       ~id:(Redemption_id.of_string "rd-1")
       ~user
       ~account:customer
       ~currency:Money.Currency.eur
       ~points:1_000
       ~rate:None
       ~now:(day 22)
     : _);
  print_s [%sexp (Rewards.summary e ~user ~now:(day 22) |> Or_error.ok_exn : Summary.t)];
  let st =
    Rewards.statement e ~user ~from:(day 1) ~until:(day 30) |> Or_error.ok_exn
  in
  print_s
    [%message
      ""
        ~opening:(st.opening : int)
        ~lines:
          (List.map st.lines ~f:(fun l -> Entry.key l.entry, l.entry.points, l.balance_after)
           : (string * int * int) list)
        ~totals:(st.totals : (Kind.t * int) list)
        ~closing:(st.closing : int)];
  print_s [%sexp (Statement.check st : unit Or_error.t)];
  [%expect
    {|
    ((balance 950) (lifetime_earned 1950)
     (tier
      ((tier
        ((code silver) (name Silver) (threshold 1500)
         (benefits ((Fx_spread_cap (bps 35))))))
       (next
        (((code gold) (name Gold) (threshold 5000)
          (benefits
           ((Fx_spread_cap (bps 20))
            (Fee_schedule (product exchange)
             (fee ((currency EUR) (fixed "0.00 EUR") (bps 10) (min ()) (max ()))))
            (Perk "priority support"))))))
       (window_points 1950) (points_to_next (3050)) (progress_percent 12)))
     (redeemable 0) (expiring ((2027-03-21 650) (2027-03-22 300))))
    ((opening 900)
     (lines
      ((card_purchase:tx-2 750 1650) (action:first_goal 300 1950)
       (redemption:rd-1 -1000 950)))
     (totals
      ((Earn 750) (Bonus 300) (Reversal 0) (Redeem -1000) (Adjustment 0)
       (Expire 0)))
     (closing 950))
    (Ok ())
    |}]
;;
