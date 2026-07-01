# coelacanth

> The fish everyone assumed went extinct with the dinosaurs — until a trawler
> pulled a living one up in 1938. A *living fossil*.

The forgotten Unix primitives — `pv`, `watch`, `ts`, `parallel`, `sponge`,
`comm`, `column`, `tac`, `tee` — were declared dead. They were quietly alive
the whole time. AI workflows just surfaced the exact problems they always
solved: long-running processes with no visibility, streams that fork, logs that
need timestamps, tasks that need parallelism.

The catch: these tools expose their contract as ad-hoc text and a man page. An
agent piping through them gets **prose, not structure**. Coelacanth
reimplements the family in Zig under **one self-describing, deterministic,
typed contract kernel** — so an agent can `describe` / `schema` its way through
all of them the same way, and every "invisible" progress bar becomes a
structured event stream.

Not a busybox clone. The first toolbox where the **toolbox itself is the
contract**. See [SPEC.md](./SPEC.md).

## Build

```sh
zig build            # -> zig-out/bin/coel   (Zig 0.14)
zig build test
```

## Try it

```sh
coel help
coel describe                          # whole capability surface, one JSON call
coel describe pv
coel schema pv                         # JSON Schema (draft 2020-12) for pv's frames
coel schema --all                      # every verb's frame schema, keyed by name

# the contract validates its own output — every frame conforms to `coel schema <verb>`:
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

# human mode (stderr is a terminal): a live throughput line
head -c 100M /dev/urandom | coel pv > /dev/null

# agent mode (forced): typed NDJSON frames on stderr, payload untouched on stdout
head -c 100M /dev/urandom | coel pv --contract > /dev/null
# {"t":"progress","seq":1,"ts":...,"bytes":...,"rate_bps":...}
# {"t":"summary","seq":N,"ts":...,"total_bytes":...,"elapsed_s":...,"avg_rate_bps":...}

# parallel: run jobs concurrently, bounded to N, typed frames per job
coel parallel -j4 gzip {} ::: *.log --contract     # items after :::
ls *.txt | coel parallel -j8 wc -l                 # items from stdin
# {"t":"job_start","seq":1,"ts":...,"job_id":0,"cmd":"gzip a.log"}
# {"t":"job_done","seq":2,"ts":...,"job_id":0,"exit_code":0,"dur_ms":12,"stdout":"out:...","stderr":"err:..."}
# {"t":"summary","seq":N,"ts":...,"total":N,"ok":N,"failed":0,"wall_s":...,"max_par":4}

# ts: human bakes the timestamp into text; agent keeps stdout verbatim
tail -f app.log | coel ts --human          # 2026-07-01 04:40:06 <line>
tail -f app.log | coel ts --human -s       # 0.000 / 0.252 / ...  (since start)
producer | coel ts --contract              # stdout = raw lines, timestamp in the frame:
# {"t":"line","seq":1,"ts":1782880763048,"out":"line:22896bcbc3d1"}

# watch: turn "re-run a command" into a typed change signal
coel watch -n 5 kubectl get pods --contract      # tick per run; changed iff output differs
coel watch -n 2 -c 10 date +%N --contract        # -c caps iterations (0 = infinite)
# {"t":"tick","seq":2,"ts":...,"iter":2,"exit_code":0,"changed":true,"dur_ms":3,"out":"out:d213c0e39ccd"}
# {"t":"summary","seq":N,"ts":...,"iters":N,"changes":M,"last_exit":0}   # also emitted on Ctrl-C
```

## Modes

Every verb picks a renderer automatically: **human** when stderr is a terminal,
**agent** (typed NDJSON on stderr) otherwise. Force it with `--contract` or
`--human`.

## Status

Nine verbs across two contract shapes, all on one kernel.

**Streaming set** — live `t`-typed frames; the dual-mode live/agent contract:

| verb | state |
|------|-------|
| `pv` | ✅ throughput `progress` frames |
| `parallel` | ✅ bounded concurrency, handle-addressed job I/O |
| `ts` | ✅ agent keeps stdout pristine; -s/-i human formats |
| `watch` | ✅ typed change signal, SIGINT-graceful summary |

**Transform set** — batch stdin→stdout payload + one `summary` frame in agent
mode (human mode is the plain filter, clean stderr):

| verb | state |
|------|-------|
| `tac` | ✅ reverse lines |
| `tee` | ✅ fan out to stdout + N files (`-a` append) |
| `sponge` | ✅ soak all stdin before opening output (safe in-place edits) |
| `column` | ✅ align into a table (`-s` in-sep, `-o` out-gap) |
| `comm` | ✅ three-column set diff of two sorted files (`-1/-2/-3`) |

Every frame validates against `coel schema <verb>` (draft 2020-12).

All primitives are **clean-room reimplemented** from spec — no vendored GPL
source, one static binary, one contract.
