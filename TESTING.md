# Testing coelacanth

Rigor is layered: property tests assert the verbs' invariants, and mutation
testing grades whether those assertions actually catch bugs.

## Run it

```sh
zig build test                 # unit + property suite (reproducible, seeded)
zig build test --fuzz          # native coverage-guided fuzzing (Zig 0.14, alpha)
python3 tools/mutate.py        # mutation score over the pure-logic files
```

## Layer 1 — pure cores

Each transform separates logic from I/O so it's testable in-memory:
`tac.reverseLines`, `comm.merge` (generic over its writer), `comm.splitLines`,
`column.format`, and the `handles.Store`. `run()` is a thin wrapper that wires
stdin/stdout into these.

## Layer 2 — property suite (`src/tests/properties.zig`)

300 seeded iterations each (`src/testing/gen.zig` generators):

- **tac** — `reverseLines ∘ reverseLines == id` on newline-terminated input (an involution).
- **comm** — `merge(a,a)` puts everything in *both*; `only1+both==|a|`, `only2+both==|b|`;
  argument-swap symmetry; and the rendered output's tab prefixes classify every
  line into the correct category with correct membership.
- **column** — field content is preserved, every column aligns to a stable
  offset, and no cell is trailing-padded.
- **store** — `explain(handle(x)) == x` round-trips through the content-addressed store.

## Layer 3 — native fuzzing

`std.testing.fuzz` targets (arg parsers, `column` splitting, `json.escape`) run
under `zig build test --fuzz` with a live coverage UI. The schema is a ready-made
oracle: feed random input to a verb and assert every emitted frame validates
against `coel schema <verb>`.

## Layer 4 — mutation testing (`tools/mutate.py`)

Applies small source mutations (`==`↔`!=`, `<`↔`<=`, `and`↔`or`, `true`↔`false`,
`+`↔`-`, …) one at a time and runs `zig build test` as the oracle. A surviving
mutant is a gap in the tests.

**Current score: 56.4%** (31/55 killed, all by a failing test), up from 46.6%
before the `column`/`comm` output assertions were added. The 24 survivors are:

- **Equivalent mutants** (unkillable by definition) — `>`↔`>=` inside *max*
  computations (`column.zig:59,67`) and `.truncate = true` on an always-fresh
  temp file (`handles.zig:51`).
- **CLI / mode-gating code** covered by the shell integration tests but not by
  in-process Zig unit tests — argument parsing in every `run()`, and the
  `ctx.mode == .agent` summary gates.

**Next lever:** inject the reader/writer into `run()` (instead of hardcoded
stdin/stdout) so the CLI and mode logic become in-process-testable, then those
survivors become killable and the score climbs toward the equivalent-mutant
ceiling.
