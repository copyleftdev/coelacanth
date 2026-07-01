# Coelacanth Contract — v0.1.0

The reusable asset. Not the binary — the **contract** the binary speaks.

## Channels

- **stdout** — payload only (the actual data a verb produces).
- **stderr** — the contract: typed NDJSON frames, one JSON object per line.

Keeping them separate is what lets a pass-through verb like `pv` stream real
bytes on stdout while narrating structured telemetry on stderr, corrupting
neither.

## Modes

Every verb has one engine and two renderers:

- **human** — pretty, ephemeral output for a terminal. Chosen when stderr is a TTY, or forced with `--human`.
- **agent** — the NDJSON frame stream below. Chosen when stderr is not a TTY, or forced with `--contract`.

## Frame envelope

Every frame carries:

| field | type | meaning |
|-------|------|---------|
| `t`   | string | frame type (see vocabulary) |
| `seq` | int    | monotonic, starts at 1, +1 per frame |
| `ts`  | int    | ms since epoch — **the only nondeterministic field**, isolated so an agent can normalize/strip it |

A run emits zero or more live frames terminated by **exactly one** `summary`.

**Streaming verbs** (`pv`, `watch`, `ts`, `parallel`) emit live frames as work
happens. **Transform verbs** (`tac`, `tee`, `sponge`, `column`, `comm`) are
batch: they produce their payload on stdout and emit a single `summary` frame in
agent mode (in human mode they behave as a plain Unix filter with clean stderr).

## Determinism

Live tools can't be byte-identical run to run. The contract instead guarantees
**structural determinism**: fixed schema, fixed frame vocabulary, monotonic
`seq`, and all wall-clock time confined to `ts`. Strip `ts` and two runs over
the same input are comparable.

## Frame vocabulary (v0.1.0)

| `t` | emitted by | fields (beyond envelope) |
|-----|-----------|--------------------------|
| `progress` | pv | `bytes`, `rate_bps` |
| `tick`     | watch | `iter`, `exit_code`, `changed` (false on first tick), `dur_ms`, `out` (handle; `error` string instead on spawn failure) |
| `line`     | ts | `out` (handle) |
| `job_start`| parallel | `job_id`, `cmd` |
| `job_done` | parallel | `job_id`, `exit_code`, `dur_ms`, `stdout` (handle), `stderr` (handle); on spawn failure: `exit_code` = -1 and `error` (string) instead of handles |
| `summary`  | all | verb-specific totals |

## Handles

`<prefix>:<12 hex of BLAKE3(bytes)>`, e.g. `out:9f2c1a0b4d6e`. A stable,
content-addressed pointer into evidence. Summaries stay compact; an agent
fetches detail by address rather than swallowing everything up front.

### Store & `explain`

Handles are dereferenceable when an evidence store is configured (`--store <dir>`
or `$COEL_STORE`). Enabled, the content-bearing verbs (`parallel`, `watch`, `ts`)
persist their evidence content-addressed: the store file is keyed by the *full*
64-hex BLAKE3 digest, of which the handle is the 12-hex prefix. Identical bytes
dedupe to one object; writes are temp-then-atomic-rename, so a concurrent reader
never sees a torn file.

`coel explain <handle>` resolves the handle (prefix-matched against the store)
and writes the bytes to stdout — the returned bytes hash back to the handle.
Disabled (the default), handles stay pure content-ids with zero disk cost.

## Self-description

- `coel describe [--all]` — every verb's contract in one deterministic call.
- `coel describe <verb>` — one verb's contract.
- `coel schema <verb>` — a JSON Schema (draft 2020-12) whose `oneOf` covers
  every frame type the verb emits: `t` pinned to a const, envelope fields typed,
  `additionalProperties: false`. Any emitted frame validates against it.
- `coel schema [--all]` — every verb's frame schema, keyed by name.

All of these are derived from each verb's `Spec` (its typed `FrameDef` list is
the single source of truth), so a verb cannot drift from its own contract, and
`describe`/`schema` cannot drift from each other.

## Versioning

`schema.version` binds the contract to an implementation. Breaking changes to
frame shapes require a version bump.
