# AGENTS.md: rewards-core

## Purpose

rewards-core is a loyalty points library for banks: an append-only points ledger per
customer, earn rules for settled card spend, tiers with benefits, cashback redemption
booked through `ledger`, an expiry policy and points statements. Everything is a pure
value or state machine; persistence is the `Store.S` module type with an in-memory
implementation and a conformance suite.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `rewards-core` library (one module per file, each with an `.mli`) |
| `test/` | Inline expect tests, Quickcheck properties, pinned stable digests |
| `examples/` | `quickstart.ml`, built and diffed against `quickstart.expected` by `dune test` |
| `doc/` | `index.mld`, the odoc landing page |
| `.github/` | `workflows/ci.yml` |
| `README.md`, `CHANGES.md` | User documentation and the changelog |

## Build, test, docs

Run from the repository root, inside the workspace (`..` is the workspace root; the
workspace keeps every org repository as a sibling checkout):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/all
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/doc
```

For parallel work give each agent its own build directory:
`DUNE_BUILD_DIR=../_build-rewards-core` (or `../_build-rewards-core-<task>`), so the shared
dune lock is not contended. Promote expect output with `dune promote` run from the
workspace root with the same `DUNE_BUILD_DIR`.

Standalone: add the organisation opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`),
`opam install --deps-only .`, then `dune build` and `dune test`.

## Conventions

- Format only this repository, after tests pass and `dune promote` is done:
  `dune build --root .. @rewards-core/fmt --auto-promote`. Never `dune fmt` across the
  workspace.
- `open! Core`, labelled arguments, `ppx_jane`, an `.mli` with odoc on every public value.
  CI fails on any odoc warning; reference sibling modules with `{!Module.value}` only
  when the module is a dependency, otherwise write `[Module.value]`.
- Records that are stored have a `Stable.V1` (bin_prot and sexp) whose reader validates
  like the smart constructor; digests are pinned in `test/test_stable.ml`. A changed
  digest means a new `V2`, never an edit of `V1`.
- Times in types that reach expect output use `Time_ns.Alternate_sexp` (UTC).
- Invariants get Quickcheck properties (`Quickcheck.test` inside `let%test_unit`);
  examples get expect tests.
- Comments for humans at any non-obvious choice (rounding direction, why zero-point
  refunds are booked, why the engine retries).
- User-visible changes get a line under `Unreleased` in `CHANGES.md`.

## Dependencies and dependents

Depends on `../money` and `../ledger` (and through them `../fixed-decimal`), plus `core`,
`ppx_jane` and `zarith`. CI pins them in order: fixed-decimal, money, ledger. No org
repository depends on rewards-core yet.

## CI

`.github/workflows/ci.yml` runs the `ox-setup` composite action from
`winterchill-trading/infra` (cached OxCaml switch, sibling pins), then `dune build`,
`dune test`, `dune build @examples/runtest` and `dune build @doc` with odoc warnings
failing the step; the `obj-magic` job calls the reusable workflow in `infra`. Check a run
with `gh run list --limit 1` and at most one `gh run watch <id> --exit-status`; never
poll in a loop. Pushes cancel the running build (`cancel-in-progress`), so on a cold
cache let one run finish before pushing again.

## Pitfalls

- A workspace build also prints errors from other repositories that are half written;
  filter the output for `File "rewards-core/` before treating it as a failure.
- A functor parameter named `Store` hides the library's `Store` module inside the
  functor (`Store.Append` becomes unbound); alias it first, as `Store_conformance` does.
  In tests the engine instance is called `Rewards` so `Engine.Outcome` stays reachable.
- Validated ids use `Binable.Of_binable_without_uuid [@alert "-legacy"]` so bin_prot
  reads re-check the id; after `include Identifiable.Make`, comparison operators are the
  id's, not `int`'s.
- `Time_ns.t` sexps print in the machine's zone, so expect output would differ between a
  laptop and CI; keep `Time_ns.Alternate_sexp` in printed types.
- Idempotency properties hold over accepted operations only: an operation refused once
  may legally apply later (a refund before its purchase), so replay only what booked.
- `dune promote` after a test that raised leaves an `[@@expect.uncaught_exn]` block in
  the source; delete it once the test is fixed.

## Where to read more

- `README.md` (rules, concurrency, refusal codes), `CHANGES.md`, `doc/index.mld`.
- `../specs/repos/rewards-core.md` for the repository's place in the workspace.
- `../oxcaml-claude-skills/AGENTS.md` (workspace guide) and the skills in
  `../oxcaml-claude-skills/skills/`: `banking-standards`, `janestreet-ocaml-style`.
- `../oxcaml-claude-skills/GOTCHAS.md`, section "Product libraries".

## Never do

- Install an opam package that changes the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared `5.2.0+ox` switch; dry-run any install first.
- Publish, tag or release.
- Add persistence, network or provider code to the library; services implement
  `Store.S`.
- Commit credentials or print secrets (this library needs none; `.env` is ignored).
- Poll CI in a loop.
