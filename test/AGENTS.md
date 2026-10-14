# AGENTS.md: test/

Inline expect tests and Quickcheck properties for the library, run with
`opam exec --switch 5.2.0+ox -- dune build --root .. @rewards-core/runtest` from the
repository root.

- `helpers.ml` holds the sample programme (EUR basis, three tiers, 100 points = 0.50
  EUR), currency helpers and the in-memory engine `Rewards`; add fixtures there.
- `test_properties.ml` drives random operation streams through the engine and checks the
  ledger rules after every step. When a rule changes, mutation-check it (disable the
  rule, see the property fail, restore).
- `test_stable.ml` pins bin_prot digests. A changed digest is a breaking change: add a
  `Stable.V2` instead of promoting the new value.
- After changing expect output, read the diff, then run `dune promote` from the workspace
  root with the same `DUNE_BUILD_DIR`.
