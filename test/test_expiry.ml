open! Core
open Rewards_core
open Helpers

let entry ~seq ~cause ~points ~at =
  Entry.create ~user ~seq ~cause ~points ~at () |> Or_error.ok_exn
;;

let%expect_test "lots expire first in, first out" =
  let policy = Expiry.Policy.After_days 30 in
  let entries =
    [ entry ~seq:0 ~cause:(Adjustment (src "a")) ~points:100 ~at:(time "2026-01-10 23:59:00Z")
    ; entry ~seq:1 ~cause:(Adjustment (src "b")) ~points:50 ~at:(time "2026-01-20 08:00:00Z")
    ; entry
        ~seq:2
        ~cause:(Redemption (Redemption_id.of_string "r"))
        ~points:(-120)
        ~at:(time "2026-01-25 08:00:00Z")
    ; entry ~seq:3 ~cause:(Action (act "x")) ~points:10 ~at:(time "2026-02-01 08:00:00Z")
    ]
  in
  print_s [%sexp (Expiry.schedule policy entries : (Date.t * int) list)];
  List.iter [ "2026-02-09"; "2026-02-19"; "2026-03-03" ] ~f:(fun d ->
    printf "%s %d\n" d (Expiry.due policy entries ~as_of:(Date.of_string d)));
  print_s [%sexp (Expiry.schedule Never entries : (Date.t * int) list)];
  [%expect
    {|
    ((2026-02-19 30) (2026-03-03 10))
    2026-02-09 0
    2026-02-19 30
    2026-03-03 40
    ()
    |}]
;;

let%expect_test "policy validation" =
  print_s [%sexp (Expiry.Policy.validate (After_days 0) : unit Or_error.t)];
  [%expect {| (Error ("expiry needs at least one day" (n 0))) |}]
;;
