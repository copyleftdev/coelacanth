# coelacanth

> In 1938 a trawler off South Africa hauled up a coelacanth — a fish the fossil
> record had filed under *extinct for 66 million years*. It had been down there
> the whole time. Alive. Just unlooked-at.

`pv`, `watch`, `ts`, `parallel`, `sponge`, `comm`, `column`, `tac`, `tee` — the
Unix tools everyone stopped teaching. They aren't dead either. And the problems
they've quietly solved for decades — no visibility into a long run, a stream that
must go two places, a log line that needs a timestamp, work that should run in
parallel — are *exactly* the problems AI agents just rediscovered the hard way.

So why can't an agent just use them?

Because a fifty-year-old tool talks to a **human at a terminal**. Pipe an agent
through `pv` and it gets a progress bar it can't read. Point it at `watch` and it
can't tell whether anything actually *changed*. The right primitives are sitting
right there — speaking a language (ad-hoc text, exit codes, a man page) a machine
can only guess at. The tools were never the problem. Their fifty-year-old
**interface** is.

coelacanth gives the whole family a new mouth: **one static Zig binary where every
tool speaks a single self-describing, deterministic, typed contract.** One engine,
two audiences — a human still gets the pretty bar; an agent gets a stream of typed
frames it can parse *and a JSON Schema to verify them against.*

Not a busybox clone. The first toolbox where **the toolbox is the contract.**

This started as two essays — [the forgotten commands][a1] and
[AI tools need contracts, not prompts][a2]. This repo is those essays, compiled.

[a1]: https://dev.to/copyleftdev/the-linux-commands-you-forgot-exist-and-why-ai-workflows-make-them-relevant-again-25bn
[a2]: https://dev.to/copyleftdev/ai-tools-need-contracts-not-prompts-5ca3

## See the difference

The same command, `pv`, to two different audiences — that split *is* the whole idea:

```sh
# human at a terminal: a live throughput bar on stderr, as always
head -c 100M /dev/urandom | coel pv > /dev/null

# an agent: typed NDJSON frames on stderr, the payload untouched on stdout
head -c 100M /dev/urandom | coel pv --contract > /dev/null
# {"t":"progress","seq":1,"ts":...,"bytes":...,"rate_bps":...}
# {"t":"summary","seq":N,"ts":...,"total_bytes":...,"elapsed_s":...,"avg_rate_bps":...}
```

And because the contract is machine-readable, the tool **validates its own output**:

```sh
coel schema parallel > pj.schema.json
coel parallel echo {} ::: a b --contract 2>frames.ndjson >/dev/null
python3 - pj.schema.json < frames.ndjson <<'PY'
import sys, json, jsonschema
schema = json.load(open(sys.argv[1]))
for line in sys.stdin:
    if line.strip():
        jsonschema.validate(json.loads(line), schema)  # raises if any frame is off-contract
print("all frames valid")
PY
```

## Build

```sh
zig build            # -> zig-out/bin/coel   (Zig 0.14)
zig build test       # unit + property + run() suite
```

## Discover it (the AI-first part)

An agent doesn't read a man page. It asks:

```sh
coel describe          # the whole capability surface, one JSON call
coel describe pv       # one verb's contract: inputs, outputs, frames, invariants
coel schema pv         # JSON Schema (draft 2020-12) for pv's frames
coel schema --all      # every verb's frame schema, keyed by name
```

`describe` and `schema` are both derived from each verb's typed declaration, so a
verb can't drift from its own contract — and the contract can't drift from the
code that emits it. See [SPEC.md](./SPEC.md).

## The verbs in action

```sh
# parallel: run jobs concurrently, bounded to N, a typed frame per job
coel parallel -j4 gzip {} ::: *.log --contract     # items after :::
ls *.txt | coel parallel -j8 wc -l                 # items from stdin
# {"t":"job_start","seq":1,"ts":...,"job_id":0,"cmd":"gzip a.log"}
# {"t":"job_done","seq":2,"ts":...,"job_id":0,"exit_code":0,"dur_ms":12,"stdout":"out:...","stderr":"err:..."}

# ts: human bakes the timestamp into text; an agent keeps stdout verbatim
tail -f app.log | coel ts --human          # 2026-07-01 04:40:06 <line>
producer      | coel ts --contract         # stdout = raw lines, timestamp in the frame

# watch: turn "re-run a command" into a typed change signal
coel watch -n 5 kubectl get pods --contract      # a tick per run; changed iff output differs
# {"t":"tick","seq":2,"iter":2,"exit_code":0,"changed":true,"dur_ms":3,"out":"out:d213c0e39ccd"}
# {"t":"summary","iters":N,"changes":M,"last_exit":0}   # emitted on completion OR Ctrl-C
```

## Modes

Every verb picks a renderer automatically: **human** when stderr is a terminal,
**agent** (typed NDJSON on stderr) otherwise. Force either with `--contract` or
`--human`. The rule underneath everything: **stdout is payload, stderr is the
contract** — so a pass-through tool like `pv` can stream real bytes *and* narrate
structured telemetry without corrupting either.

## The verbs

**Streaming** — live `t`-typed frames as work happens:

| verb | does |
|------|------|
| `pv` | pass stdin→stdout, report throughput |
| `parallel` | run jobs concurrently, bounded, with handle-addressed job I/O |
| `ts` | timestamp each line (in-text for humans; a structured field for agents) |
| `watch` | re-run a command; report *what changed*, SIGINT-graceful summary |

**Transform** — batch payload on stdout + one `summary` frame in agent mode:

| verb | does |
|------|------|
| `tac` | reverse lines |
| `tee` | fan out to stdout + N files (`-a` append) |
| `sponge` | soak all stdin before opening output (safe in-place edits) |
| `column` | align into a table (`-s` in-sep, `-o` out-gap) |
| `comm` | three-column set diff of two sorted files (`-1/-2/-3`) |

**Evidence** — the handles that streaming frames carry are dereferenceable:

| verb | does |
|------|------|
| `explain` | resolve a handle to its exact bytes from the store |

```sh
coel parallel --store .coel gzip -kf {} ::: *.log --contract 2>frames.ndjson
coel explain --store .coel out:9f2c1a0b4d6e     # -> the exact bytes that job wrote
```

Storage is opt-in (`--store <dir>` / `$COEL_STORE`); without it, handles stay
pure content-ids at zero disk cost. Identical evidence dedupes automatically.

## Built to be trusted

The point of an AI-first tool is that a machine can *rely* on it, so the tests
are the product too: pure-function property tests, in-process `run()` tests,
native fuzzing, and a mutation-testing harness that grades whether those tests
actually catch bugs. It sits at a **94.5% mutation score — every non-equivalent
mutant killed.** See [TESTING.md](./TESTING.md).

Every primitive is **clean-room reimplemented** from spec — no vendored GPL
source, one static binary, one contract.

## License

MIT — see [LICENSE](./LICENSE).
