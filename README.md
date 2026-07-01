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

# human mode (stderr is a terminal): a live throughput line
head -c 100M /dev/urandom | coel pv > /dev/null

# agent mode (forced): typed NDJSON frames on stderr, payload untouched on stdout
head -c 100M /dev/urandom | coel pv --contract > /dev/null
# {"t":"progress","seq":1,"ts":...,"bytes":...,"rate_bps":...}
# {"t":"summary","seq":N,"ts":...,"total_bytes":...,"elapsed_s":...,"avg_rate_bps":...}
```

## Status

MVP proves the hardest part first — the dual-mode live/agent contract — on the
streaming set:

| verb | state |
|------|-------|
| `pv` | ✅ implemented |
| `watch` | contract declared, stub |
| `ts` | contract declared, stub |
| `parallel` | contract declared, stub |

Transform verbs (`comm`, `column`, `tac`, `sponge`, `tee`) come after, on the
same kernel.

All primitives are **clean-room reimplemented** from spec — no vendored GPL
source, one static binary, one contract.
