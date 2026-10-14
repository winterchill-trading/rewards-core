open! Core
open Rewards_core
open Helpers

type op =
  | Settle of
      { id : int
      ; cents : int
      ; category : string
      ; foreign : bool
      ; day : int
      }
  | Refund of
      { id : int
      ; purchase : int
      ; cents : int
      ; day : int
      }
  | Action of
      { code : string
      ; day : int
      }
  | Adjust of
      { id : int
      ; points : int
      ; day : int
      }
  | Redeem of
      { id : int
      ; points : int
      ; foreign : bool
      ; day : int
      }
  | Expire of { day : int }
[@@deriving sexp_of]

let gen_op =
  let open Quickcheck.Generator.Let_syntax in
  let day = Int.gen_incl 0 400 in
  Quickcheck.Generator.weighted_union
    [ ( 4.
      , let%map id = Int.gen_incl 0 15
        and cents = Int.gen_incl 1 50_000
        and category = Quickcheck.Generator.of_list [ "travel"; "groceries"; "cash"; "other" ]
        and foreign = Bool.quickcheck_generator
        and day in
        Settle { id; cents; category; foreign; day } )
    ; ( 2.
      , let%map id = Int.gen_incl 0 15
        and purchase = Int.gen_incl 0 15
        and cents = Int.gen_incl 1 30_000
        and day in
        Refund { id; purchase; cents; day } )
    ; ( 1.
      , let%map code = Quickcheck.Generator.of_list [ "first_exchange"; "first_goal"; "nope" ]
        and day in
        Action { code; day } )
    ; ( 1.
      , let%map id = Int.gen_incl 0 5
        and points = Int.gen_incl (-3_000) 3_000
        and day in
        Adjust { id; points; day } )
    ; ( 2.
      , let%map id = Int.gen_incl 0 8
        and steps = Int.gen_incl 8 40
        and foreign = Bool.quickcheck_generator
        and day in
        Redeem { id; points = steps * 100; foreign; day } )
    ; ( 1.
      , let%map day in
        Expire { day } )
    ]
;;

let at day = Time_ns.add t0 (Time_ns.Span.of_day (Float.of_int day))
let account_eur = Ledger.Account_id.of_string "customer:user-1/eur"
let account_usd = Ledger.Account_id.of_string "customer:user-1/usd"

(* Returns whether the op booked a new points entry. *)
let run e op =
  let booked = function
    | Ok (Engine.Outcome.Booked _) -> true
    | Ok (Already_booked _ | Nothing_to_book) | Error _ -> false
  in
  match op with
  | Settle { id; cents; category; foreign; day } ->
    let spend =
      Money.Amount.of_minor_units_int
        (if foreign then Money.Currency.usd else Money.Currency.eur)
        cents
    in
    Rewards.settle_purchase
      e
      ~user
      ~purchase:(src (sprintf "p%d" id))
      ~spend
      ~category:(cat category)
      ~rate:(if foreign then Some eur_usd else None)
      ~at:(at day)
    |> booked
  | Refund { id; purchase; cents; day } ->
    (* A refund is in the purchase's currency; try both and let the engine refuse one. *)
    List.exists [ Money.Currency.eur; Money.Currency.usd ] ~f:(fun currency ->
      Rewards.refund_purchase
        e
        ~user
        ~refund:(src (sprintf "r%d" id))
        ~purchase:(src (sprintf "p%d" purchase))
        ~amount:(Money.Amount.of_minor_units_int currency cents)
        ~at:(at day)
      |> booked)
  | Action { code; day } ->
    Rewards.complete_action e ~user ~action:(act code) ~at:(at day) |> booked
  | Adjust { id; points; day } ->
    if points = 0
    then false
    else
      Rewards.adjust e ~user ~id:(src (sprintf "a%d" id)) ~points ~reason:"" ~at:(at day)
      |> booked
  | Redeem { id; points; foreign; day } ->
    let before = balance e user in
    (match
       Rewards.redeem
         e
         ~id:(Redemption_id.of_string (sprintf "rd%d" id))
         ~user
         ~account:(if foreign then account_usd else account_eur)
         ~currency:(if foreign then Money.Currency.usd else Money.Currency.eur)
         ~points
         ~rate:(if foreign then Some eur_usd else None)
         ~now:(at day)
     with
     | Ok { status = Completed; _ } -> balance e user < before
     | Ok _ | Error _ -> false)
  | Expire { day } ->
    Rewards.expire e ~user ~as_of:(Time_ns.to_date (at day) ~zone:Time_float.Zone.utc) ~at:(at day)
    |> booked
;;

let check_invariants e =
  let account = Rewards.account e user |> Or_error.ok_exn in
  let entries = Points_account.entries account in
  assert (Points_account.balance account >= 0);
  assert (Points_account.balance account = List.sum (module Int) entries ~f:(fun e -> e.points));
  (* Every purchase gives back at most what it earned. *)
  List.iter entries ~f:(fun (p : Entry.t) ->
    match p.cause with
    | Card_purchase purchase ->
      let clawed =
        Points_account.refunds_of account ~purchase
        |> List.sum (module Int) ~f:(fun r -> -r.points)
      in
      assert (clawed <= p.points)
    | _ -> ());
  let st =
    Statement.create ~user ~from:(at 0) ~until:(at 1_000) entries |> Or_error.ok_exn
  in
  Statement.check st |> Or_error.ok_exn
;;

let%test_unit "random operation streams keep every ledger rule" =
  Quickcheck.test
    ~trials:300
    ~sexp_of:[%sexp_of: op list]
    (List.gen_with_length 40 gen_op)
    ~f:(fun ops ->
      let e = engine ~expiry:(After_days 120) () in
      let booked =
        List.filter ops ~f:(fun op ->
          let b = run e op in
          check_invariants e;
          b)
      in
      (* Every operation that booked an entry is a no-op the second time. *)
      let length () = Points_account.length (Rewards.account e user |> Or_error.ok_exn) in
      let n = length () in
      List.iter booked ~f:(fun op -> assert (not (run e op)));
      [%test_result: int] (length ()) ~expect:n)
;;

let%test_unit "after an expiry run nothing more is due on that date" =
  Quickcheck.test
    ~trials:300
    ~sexp_of:[%sexp_of: op list * int]
    (Quickcheck.Generator.both (List.gen_with_length 30 gen_op) (Int.gen_incl 0 600))
    ~f:(fun (ops, day) ->
      let e = engine ~expiry:(After_days 60) () in
      List.iter ops ~f:(fun op -> ignore (run e op : bool));
      let as_of = Time_ns.to_date (at day) ~zone:Time_float.Zone.utc in
      ignore (Rewards.expire e ~user ~as_of ~at:(at day) : _);
      let entries = Points_account.entries (Rewards.account e user |> Or_error.ok_exn) in
      [%test_result: int] (Expiry.due (After_days 60) entries ~as_of) ~expect:0)
;;

let%test_unit "cashback never pays more than the points are worth" =
  Quickcheck.test
    ~trials:1_000
    ~sexp_of:[%sexp_of: int * int * string]
    (Quickcheck.Generator.tuple3
       (Int.gen_incl 0 20_000)
       (Int.gen_incl 0 30_000)
       (Quickcheck.Generator.of_list [ "1.10"; "0.85"; "157.3"; "0.0001" ]))
    ~f:(fun (points, balance, price) ->
      let r = rate ~base:Money.Currency.eur ~quote:Money.Currency.jpy price in
      match
        Cashback.quote cashback ~points ~balance ~currency:Money.Currency.jpy ~rate:(Some r)
      with
      | Error _ -> ()
      | Ok q ->
        assert (q.points % 100 = 0 && q.points <= balance && q.points >= 1_000);
        let exact = Q.mul (Money.Amount.to_q q.value) (Money.Rate.price r) in
        let paid = Money.Amount.to_q q.amount in
        assert (Q.leq paid exact);
        (* Rounded down by less than one yen. *)
        assert (Q.lt (Q.sub exact paid) Q.one))
;;

let%test_unit "a higher window total never gives a lower tier" =
  Quickcheck.test
    ~sexp_of:[%sexp_of: int * int]
    (Quickcheck.Generator.both (Int.gen_incl 0 10_000) (Int.gen_incl 0 10_000))
    ~f:(fun (a, b) ->
      let lo = Int.min a b
      and hi = Int.max a b in
      assert (
        (Tiers.tier_for tiers ~points:lo).threshold
        <= (Tiers.tier_for tiers ~points:hi).threshold))
;;
