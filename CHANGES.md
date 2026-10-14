# Changes

All notable changes to this library. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow semantic
versioning once released.

## Unreleased

### Added

- Ids: `User_id`, `Source_id`, `Redemption_id`, `Action`, `Category`.
- Points ledger: `Kind`, `Cause` (unique key per customer), `Earning`, `Entry`
  (append-only, sign checked per kind), `Points_account` (balance never negative, one
  entry per cause, gap-free sequence numbers).
- Rules: `Earn_rules` (settled spend in a basis currency, category multipliers,
  proportional cumulative clawback capped at the balance, one-off action bonuses),
  `Benefit`, `Tier`, `Tiers` (rolling window, progress), `Cashback` (steps, minimum,
  maximum, round-down conversion), `Expiry` (never or after N days, earliest-expiring
  points spent first), `Program`.
- Redemptions: `Redemption` (accepted, completed, refused) and `Booking` (the cashback
  ledger entry under `rewards:redemption:<id>`).
- Reports: `Summary`, `Statement`.
- Persistence: `Store` module type, `Store_memory`, `Store_conformance`.
- `Engine`: settle, refund, bonus, adjust, expire, quote and redeem over any store and
  monad, with retries on concurrent writes.
- `Refusal` with stable codes.
- `Stable.V1` bin_prot and sexp forms with pinned digests; readers validate.
