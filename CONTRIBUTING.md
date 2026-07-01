# Contributing to coelacanth

Thanks for looking under the hood. coelacanth is small and opinionated on
purpose — the contract *is* the product, so most of the guidance here is about
keeping that contract honest.

## Setup

- **Zig 0.14** (the only toolchain dependency).
- After cloning, enable the pre-push test gate — it's a versioned hook, but
  `core.hooksPath` has to be turned on once per clone:

  ```sh
  git config core.hooksPath tools/hooks
  ```

  From then on, every `git push` runs `zig build test` first and aborts on
  failure. Bypass in a pinch with `git push --no-verify`.

## Build & test

```sh
zig build                 # -> zig-out/bin/coel
zig build test            # unit + property + run() suite (deterministic)
zig build fuzz            # fuzz targets once; add --fuzz to loop with the coverage UI
python3 tools/mutate.py   # mutation score over the logic files
```

See [TESTING.md](./TESTING.md) for the full testing strategy.

## What we optimize for

- **The toolbox is the contract.** Every verb is self-describing (`coel describe`
  / `coel schema`) and every emitted frame must validate against
  `coel schema <verb>`. If you add or change a frame, update the verb's typed
  `FrameDef` — `describe` and `schema` are derived from it, so they can't drift.
- **stdout is payload, stderr is the contract.** Never mix them.
- **Structural determinism.** Same input → same frames; wall-clock lives only in
  the `ts` field. Keep it that way.
- **Clean-room reimplementation.** Primitives are written from spec — no vendored
  GPL (or other) source. One static binary, one contract.

## Adding a verb

1. `src/verbs/<name>.zig`: declare `pub const spec` (`api.Spec`) with typed
   `FrameDef`s, and a thin `pub fn run(ctx: *api.Context)` that does I/O through
   `ctx.stdin` / `ctx.stdout` / `ctx.stderr`. Put the real logic in pure
   functions so it's testable in-memory.
2. Register it in the `registry` in `src/main.zig`.
3. `describe` and `schema` pick it up automatically.
4. Add tests: property tests for the pure logic (`src/tests/properties.zig`) and
   a `run()` test for the CLI/mode behavior (`src/tests/cli.zig`). Run
   `tools/mutate.py` and make sure new logic isn't leaving survivors.

## Pull requests

- Keep it green — the pre-push gate enforces `zig build test`, and so should you.
- Match the surrounding style: comment density, naming, and idiom of the file
  you're editing.
- Small, focused commits with a clear "why" in the message.

## License

By contributing, you agree that your contributions are licensed under the
project's [MIT License](./LICENSE).
