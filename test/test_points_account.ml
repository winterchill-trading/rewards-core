open! Core
open Rewards_core
open Helpers

let entry ?(user = user) ?(at = t0) ~seq ~cause points =
  Entry.create ~user ~seq ~cause ~points ~at () |> Or_error.ok_exn
;;

let show account entry =
  match Points_account.apply account entry with
  | Ok (Appended a) ->
    printf "appended, balance %d\n" (Points_account.balance a);
    a
  | Ok (Duplicate e) ->
    printf "duplicate of seq %d\n" e.seq;
    account
  | Error refusal ->
    print_s [%sexp (refusal : Refusal.t)];
    account
;;

let%expect_test "apply: sequence, one entry per cause, no overdraft" =
  let a = Points_account.empty user in
  let bonus = Cause.Action (act "first_exchange") in
  let a = show a (entry ~seq:0 ~cause:bonus 250) in
  (* Redelivered later with another time and sequence number: still a duplicate. *)
  let a = show a (entry ~seq:5 ~cause:bonus 250 ~at:(time "2026-04-01 00:00:00Z")) in
  let a = show a (entry ~seq:1 ~cause:bonus 300) in
  let a = show a (entry ~seq:3 ~cause:(Adjustment (src "x")) 10) in
  let a =
    show a (entry ~seq:1 ~cause:(Redemption (Redemption_id.of_string "r")) (-300))
  in
  let a =
    show a (entry ~seq:1 ~cause:(Redemption (Redemption_id.of_string "r")) (-250))
  in
  let a =
    show
      a
      (entry ~user:(User_id.of_string "other") ~seq:2 ~cause:(Adjustment (src "y")) 1)
  in
  print_s
    [%message
      ""
        ~balance:(Points_account.balance a : int)
        ~lifetime_earned:(Points_account.lifetime_earned a : int)
        ~length:(Points_account.length a : int)];
  [%expect
    {|
    appended, balance 250
    duplicate of seq 0
    (Cause_conflict (key action:first_exchange))
    (Invalid ("out of sequence" (expected 1) (got 3)))
    (Insufficient_points (balance 250) (requested 300))
    appended, balance 0
    (Invalid ("entry for another customer" (expected user-1) (got other)))
    ((balance 0) (lifetime_earned 250) (length 2))
    |}]
;;

let%expect_test "entries check their sign and their earning details" =
  let show r = print_s [%sexp (Or_error.ignore_m r : unit Or_error.t)] in
  show (Entry.create ~user ~seq:0 ~cause:(Action (act "a")) ~points:0 ~at:t0 ());
  show
    (Entry.create
       ~user
       ~seq:0
       ~cause:(Expiry (Date.of_string "2026-01-01"))
       ~points:5
       ~at:t0
       ());
  show
    (Entry.create
       ~user
       ~seq:0
       ~cause:(Card_refund { refund = src "r"; purchase = src "p" })
       ~points:0
       ~at:t0
       ());
  show (Entry.create ~user ~seq:(-1) ~cause:(Adjustment (src "a")) ~points:1 ~at:t0 ());
  [%expect
    {|
    (Error ("points have the wrong sign for the kind" (kind Bonus) (points 0)))
    (Error ("points have the wrong sign for the kind" (kind Expire) (points 5)))
    (Ok ())
    (Error ("negative sequence number" (seq -1)))
    |}]
;;

let%expect_test "ids are validated" =
  let show s =
    print_s [%sexp (User_id.of_string_or_error s |> Or_error.ignore_m : unit Or_error.t)]
  in
  show "customer-42";
  show "";
  show "has space";
  show (String.make 101 'a');
  [%expect
    {|
    (Ok ())
    (Error ((Rewards_core.User_id (id "")) "empty id"))
    (Error
     ((Rewards_core.User_id (id "has space"))
      ("invalid character in id" (c " ") "has space")))
    (Error
     ((Rewards_core.User_id
       (id
        aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa))
      ("too long" (max_length 100))))
    |}]
;;
