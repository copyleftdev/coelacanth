# Testing coelacanth

Rigor is layered: property tests assert the verbs' invariants, in-process `run()`
tests cover the CLI/mode logic, and mutation testing grades whether those
assertions actually catch bugs.

## Run it

```sh
zig build test                 # unit + property + run() suite (deterministic, seeded)
zig build fuzz                 # run fuzz targets once; add --fuzz to loop with the coverage UI
python3 tools/mutate.py        # mutation score over the logic files
```

## Layer 1 — pure cores

Each transform separates logic from I/O so it's testable in-memory:
`tac.reverseLines`, `comm.merge` (generic over its writer), `comm.splitLines`,
`column.format`, and the `handles.Store`. `run()` is a thin wrapper; its I/O is
injected via `Context` (`std.io.AnyReader`/`AnyWriter`) so `run()` itself is also
in-process testable — `src/testing/harness.zig` drives a verb over buffers.

## Layer 2 — property suite (`src/tests/properties.zig`)

300 seeded iterations each (`src/testing/gen.zig` generators):

- **tac** — `reverseLines ∘ reverseLines == id` on newline-terminated input (an involution).
- **comm** — `merge(a,a)` puts everything in *both*; `only1+both==|a|`, `only2+both==|b|`;
  argument-swap symmetry; and the rendered output's tab prefixes classify every
  line into the correct category with correct membership.
- **column** — field content is preserved, every column aligns to a stable
  offset, and no cell is trailing-padded.
- **store** — `explain(handle(x)) == x` round-trips through the content-addressed store.

## Layer 2.5 — run() / CLI tests (`src/tests/cli.zig`)

Drive each verb's `run()` over in-memory buffers and assert the CLI contract:
mode gating (agent emits a `summary` frame, human doesn't), argument parsing and
bad-arg rejection, `column` `-t`/`-s`/`-o`, and `comm`'s two-file requirement,
suppression flags (`-1/-2/-3`), and rendered three-column diff.

## Layer 3 — native fuzzing (`src/tests/fuzz.zig`)

`std.testing.fuzz` targets (`column`, `ts`) assert the frame stream stays
well-formed under arbitrary input: every line is JSON, `seq` is monotonic from 1,
and a `summary` terminates. Kept behind its own `zig build fuzz` step (the alpha
fuzzer spins up a server/loop), so `zig build test` stays deterministic. Run
`zig build fuzz --fuzz` for the coverage UI. The `coel schema` output is also a
ready-made oracle: feed random input to a verb and validate each frame against
`coel schema <verb>`.

## Layer 4 — mutation testing (`tools/mutate.py`)

Applies small source mutations (`==`↔`!=`, `<`↔`<=`, `and`↔`or`, `true`↔`false`,
`+`↔`-`, …) one at a time and runs `zig build test` as the oracle. A surviving
mutant is a gap in the tests.

**Score: 94.5%** (52/55 killed, every kill by a failing test). Progression as the
suite was built out:

| stage | score |
|-------|-------|
| initial property suite | 46.6% |
| + column/comm output assertions | 56.4% |
| + in-process run() tests | 80.0% |
| + comm suppression / column -o | 92.7% |
| + column agent-mode gate | **94.5%** |

The **3 remaining survivors are all provably-equivalent mutants** — `>`↔`>=`
inside *max* computations (`column.zig:59,67`, same result when equal) and
`.truncate = true` on an always-fresh temp file (`handles.zig:51`, no observable
effect). Equivalent mutants cannot be killed by definition, so **100% of the
killable mutants are killed.**
