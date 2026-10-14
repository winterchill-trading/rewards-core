open! Core
open Rewards_core
open Helpers

let%expect_test "the in-memory store passes the conformance suite" =
  let module C = Store_conformance.Make (Monad.Ident) (Store) in
  print_s [%sexp (C.check (Store.create ()) : unit Or_error.t)];
  [%expect {| (Ok ()) |}]
;;

(* A store where another writer slips an entry in just before our append, as a second
   service instance would. *)
module Racing = struct
  include Store

  let before_append : (t -> unit) option ref = ref None

  let append t entry =
    Option.iter !before_append ~f:(fun f ->
      before_append := None;
      f t);
    Store.append t entry
  ;;
end

module Racing_rewards = Engine.Make (Monad.Ident) (Racing)

let%expect_test "a decision made on a stale ledger is made again" =
  let store = Racing.create () in
  let e = Racing_rewards.create (program ()) store in
  ignore
    (Racing_rewards.adjust e ~user ~id:(src "seed") ~points:1_200 ~reason:"" ~at:t0 : _);
  (* While a redemption of 1,000 points is being decided, another writer spends 500. *)
  Racing.before_append
  := Some
       (fun t ->
         let competing =
           Entry.create
             ~user
             ~seq:1
             ~cause:(Adjustment (src "other"))
             ~points:(-500)
             ~at:t0
             ()
           |> Or_error.ok_exn
         in
         ignore (Store.append t competing : Store_types.Append.t));
  let r =
    Racing_rewards.redeem
      e
      ~id:(Redemption_id.of_string "rd-1")
      ~user
      ~account:(Ledger.Account_id.of_string "customer:user-1/eur")
      ~currency:Money.Currency.eur
      ~points:1_000
      ~rate:None
      ~now:t0
  in
  (match r with
   | Ok r -> print_s [%sexp (r.status : Redemption.Status.t)]
   | Error refusal -> print_s [%sexp (refusal : Refusal.t)]);
  let account = Racing_rewards.account e user |> Or_error.ok_exn in
  printf
    "balance %d after %d entries\n"
    (Points_account.balance account)
    (Points_account.length account);
  [%expect
    {|
    (Refused (code INSUFFICIENT_POINTS))
    balance 700 after 2 entries
    |}]
;;
