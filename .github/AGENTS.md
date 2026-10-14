# AGENTS.md: .github/

`workflows/ci.yml` builds, tests, runs the example and builds the docs on every push,
using the `ox-setup` action from `winterchill-trading/infra` and the shared `obj-magic`
workflow.

- The `pins:` list must name every organisation package this repository depends on, in
  dependency order (fixed-decimal, money, ledger). When `dune-project` gains an
  organisation dependency, add its pin here in the same commit.
- Check runs with `gh run list --limit 1` and at most one `gh run watch`; never poll.
