# AGENTS.md: lib/

The `rewards-core` library. Every module has an `.mli`; the `.mli` is the contract, so
change it first and keep its odoc complete. `rewards_core.ml(i)` re-exports the modules.

- Ledger rules live in `points_account.ml` (`apply`): sequence numbers, one entry per
  `Cause.key`, balance never negative. Every write path goes through it.
- Pure rules: `earn_rules.ml`, `tiers.ml`, `cashback.ml`, `expiry.ml`, `convert.ml`.
  Rounding is explicit: earning floors to whole basis units, cashback rounds down in the
  payout currency, clawback floors after multiplying (the default `Clawback_rule`
  floors the cumulative share). A `Clawback_rule` is not stored with the programme, so
  the engine's caller must keep it the same for a programme's life.
- `engine.ml` is the only module with a write loop: idempotency by cause first, then
  the decision, then `Store.append`, re-deciding on `Stale`.
- `store.ml` documents what an implementation must make atomic; `store_conformance.ml`
  checks it. Keep both in step with any change to the contract.
- Stored records (`Entry`, `Redemption`, `Program`, ...) keep `Stable.V1` readers that
  validate. Never edit a `V1`; add `V2`.

Build and test from the repository root with
`opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/runtest`.
