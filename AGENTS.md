# AGENTS.md: rewards-core

## Purpose

rewards-core is a loyalty programme library for banks: an append-only points ledger, earn
rules for settled card spend, tiers with benefits, cashback redemption booked through
`ledger`, an expiry policy and points statements. Everything is a pure value or state
machine; persistence is a `Store.S` module type with an in-memory implementation.

## Layout

| Path | Holds |
| --- | --- |
| `lib/` | The `rewards-core` library |
| `doc/` | `index.mld`, the odoc landing page |
| `.github/` | `ci.yml` |
| `README.md`, `CHANGES.md` | User documentation and the changelog |

## Build, test, docs

Run from the repository root, inside the workspace (`..` is the workspace root; the
workspace keeps every org repository as a sibling checkout):

```sh
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/all
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/runtest
opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/doc
```

For parallel work give each agent its own build directory, for example
`DUNE_BUILD_DIR=../_build-rewards-core`, so the shared dune lock is not contended.

Standalone: add the organisation opam repository
(`opam repo add winterchill https://github.com/winterchill-trading/opam-repository.git`),
`opam install --deps-only .`, then `dune build` and `dune test`.

## Never do

- Install an opam package that changes the compiler, `core`, `base`, `async` or
  `ppx_jane` on the shared `5.2.0+ox` switch.
- Publish, tag or release.
- Commit credentials or print secrets. This library needs none.
- Poll CI in a loop.
