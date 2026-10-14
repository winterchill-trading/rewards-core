# AGENTS.md: examples/

`quickstart.ml` is the README's example as a complete program. `dune test` runs it and
diffs its output against `quickstart.expected`; CI also runs
`dune build @examples/runtest`.

- When the example's output changes on purpose, regenerate `quickstart.expected` from
  the program's output and update the README's copy of it.
- Keep the example free of anything that varies between runs (wall-clock time, random
  ids), so the diff stays stable.
