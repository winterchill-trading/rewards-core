open! Core
open Rewards_core
open Helpers

(* A changed digest means stored bytes no longer decode: add a Stable.V2 next to V1
   instead of editing V1, and keep V1 readable. *)
let%expect_test "stable bin_prot digests" =
  List.iter
    [ "User_id", [%bin_digest: User_id.Stable.V1.t]
    ; "Source_id", [%bin_digest: Source_id.Stable.V1.t]
    ; "Redemption_id", [%bin_digest: Redemption_id.Stable.V1.t]
    ; "Action", [%bin_digest: Action.Stable.V1.t]
    ; "Category", [%bin_digest: Category.Stable.V1.t]
    ; "Kind", [%bin_digest: Kind.Stable.V1.t]
    ; "Cause", [%bin_digest: Cause.Stable.V1.t]
    ; "Earning", [%bin_digest: Earning.Stable.V1.t]
    ; "Entry", [%bin_digest: Entry.Stable.V1.t]
    ; "Earn_rules", [%bin_digest: Earn_rules.Stable.V1.t]
    ; "Benefit", [%bin_digest: Benefit.Stable.V1.t]
    ; "Tier", [%bin_digest: Tier.Stable.V1.t]
    ; "Tiers", [%bin_digest: Tiers.Stable.V1.t]
    ; "Cashback.Rules", [%bin_digest: Cashback.Rules.Stable.V1.t]
    ; "Cashback.Quote", [%bin_digest: Cashback.Quote.Stable.V1.t]
    ; "Expiry.Policy", [%bin_digest: Expiry.Policy.Stable.V1.t]
    ; "Program", [%bin_digest: Program.Stable.V1.t]
    ; "Redemption", [%bin_digest: Redemption.Stable.V1.t]
    ]
    ~f:(fun (name, digest) -> printf "%-15s %s\n" name digest);
  [%expect
    {|
    User_id         d9a8da25d5656b016fb4dbdc2e4197fb
    Source_id       d9a8da25d5656b016fb4dbdc2e4197fb
    Redemption_id   d9a8da25d5656b016fb4dbdc2e4197fb
    Action          d9a8da25d5656b016fb4dbdc2e4197fb
    Category        d9a8da25d5656b016fb4dbdc2e4197fb
    Kind            84791e1eb1ebc47bba65312dd311779b
    Cause           57a91ac71bb381597223756e17256194
    Earning         dcc46d5514138973d6db577dcdfbcfec
    Entry           741d32ca029965b8fcaee19be7851a75
    Earn_rules      6206ab89a065f98be85418abe92889a1
    Benefit         7d9b7e5d36605ab388a89f87d003a890
    Tier            deb964cb9ba6166ca1cbf57b5e733bbf
    Tiers           96b8d8e6b0fa39e4abaa4db65d2e227b
    Cashback.Rules  aee07e39c53c3199798e0134a7e08916
    Cashback.Quote  5c48884c098c82c2083e0e0dc19e2b7c
    Expiry.Policy   f0376718f080e670e07a66b29b717146
    Program         69400a7542a0e361b731fc2a6ce27c5e
    Redemption      961e0491a0035d133b62e53c91ce918b
    |}]
;;

module type Stable = sig
  type t [@@deriving bin_io, sexp, equal]
end

let round_trip (type a) (module M : Stable with type t = a) (v : a) =
  let back = Binable.of_string (module M) (Binable.to_string (module M) v) in
  assert (M.equal back v);
  assert (M.equal (M.t_of_sexp (M.sexp_of_t v)) v)
;;

let%expect_test "values round trip through bin_prot and sexp" =
  round_trip (module Program.Stable.V1) (program ~expiry:(After_days 365) ());
  let e = engine () in
  ignore
    (Rewards.settle_purchase
       e
       ~user
       ~purchase:(src "tx-1")
       ~spend:(usd "22.00")
       ~category:(cat "travel")
       ~rate:(Some eur_usd)
       ~at:t0
     : _);
  let entry =
    Rewards.account e user |> Or_error.ok_exn |> Points_account.entries |> List.hd_exn
  in
  round_trip (module Entry.Stable.V1) entry;
  print_s [%sexp (entry : Entry.Stable.V1.t)];
  [%expect
    {|
    ((user user-1) (seq 0) (cause (Card_purchase tx-1)) (points 60)
     (at "2026-03-01 10:00:00Z")
     (earning
      (((spend "22.00 USD") (basis_amount "20.00 EUR")
        (rate
         (((base USD) (quote EUR) (price 10/11) (at "2026-03-01 10:00:00Z")
           (source test))))
        (category travel) (multiplier 3))))
     (note ""))
    |}]
;;

let%expect_test "readers validate" =
  let read s =
    Or_error.try_with (fun () -> Entry.Stable.V1.t_of_sexp (Sexp.of_string s))
  in
  print_s
    [%sexp
      (read
         "((user u) (seq 0) (cause (Card_purchase p)) (points -5) (at \"2026-03-01 \
          10:00:00Z\") (earning ()) (note \"\"))"
       |> Or_error.ignore_m
       : unit Or_error.t)];
  print_s
    [%sexp
      (Or_error.try_with (fun () ->
         Program.Stable.V1.t_of_sexp
           (Sexp.of_string
              "((earn ((basis EUR) (points_per_unit 1) (default_multiplier 1) \
               (multipliers ()) (bonuses ()))) (tiers ((window 90d) (tiers (((code a) \
               (name A) (threshold 0) (benefits ())))))) (cashback ((step 100) \
               (value_per_step \"0.50 USD\") (minimum 1000) (maximum 2000))) (expiry \
               Never))"))
       |> Or_error.ignore_m
       : unit Or_error.t)];
  [%expect
    {|
    (Error ("points have the wrong sign for the kind" (kind Earn) (points -5)))
    (Error
     ("cashback and earning use different basis currencies" (earn EUR)
      (cashback USD)))
    |}]
;;
