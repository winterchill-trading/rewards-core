(lang dune 3.17)

(name rewards-core)

(generate_opam_files true)

(license MIT)

(authors "WinterChill AI")

(maintainers "hello@winterchill.xyz")

(source
 (github winterchill-trading/rewards-core))

(homepage "https://github.com/winterchill-trading/rewards-core")

(bug_reports "https://github.com/winterchill-trading/rewards-core/issues")

(documentation "https://github.com/winterchill-trading/rewards-core#readme")

(package
 (name rewards-core)
 (synopsis "Loyalty points for banks: points ledger, earn rules, tiers, cashback redemption, expiry and statements")
 (description
  "rewards-core models a card loyalty programme as pure values and state machines: an append-only points ledger per customer where balances never go below zero and every cause (a settled purchase, a refund, a one-off action, a redemption, an expiry run) books at most once; earn rules that convert settled card spend into a base currency and apply per-category multipliers; proportional clawback on refunds; one-off action bonuses; tiers over a rolling window with benefits such as an FX spread cap or a cheaper fee schedule; cashback redemption with minimums, steps and maximums, booked as balanced ledger entries under idempotency keys; an expiry policy with first-in first-out consumption; and points statements. Persistence is a module type with an in-memory implementation and a conformance suite. Requires the OxCaml compiler (through its money and ledger dependencies).")
 (tags
  (rewards loyalty points cashback tiers ledger banking oxcaml))
 (depends
  oxcaml
  (ocaml
   (and
    (>= 5.2.0)
    (< 5.3~)))
  dune
  (core
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (ppx_jane
   (and
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (zarith
   (>= 1.12))
  money
  ledger
  (expect_test_helpers_core
   (and
    :with-test
    (>= v0.18~preview.130.106+341)
    (< v0.19~)))
  (odoc :with-doc)))
