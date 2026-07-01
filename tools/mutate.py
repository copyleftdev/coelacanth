#!/usr/bin/env python3
"""Minimal mutation tester for coelacanth.

Applies small source mutations one at a time and runs `zig build test` as the
oracle: if the suite still passes, the mutant SURVIVED (a gap in the tests); if
it fails or stops compiling, the mutant was KILLED. Reports the mutation score
and every survivor so you know exactly what the tests don't pin down.

Usage:
  python3 tools/mutate.py [--max N] [--seed S] [file ...]
Defaults to the pure-logic files the property suite targets.
"""
import argparse
import random
import re
import subprocess
import sys
import time

DEFAULT_FILES = [
    "src/verbs/tac.zig",
    "src/verbs/comm.zig",
    "src/verbs/column.zig",
    "src/kernel/handles.zig",
    "src/kernel/json.zig",
]

# (regex, replacement) — high-signal logic mutations, low compile-noise.
OPERATORS = [
    (re.compile(r" == "), " != "),
    (re.compile(r" != "), " == "),
    (re.compile(r" <= "), " >= "),
    (re.compile(r" >= "), " <= "),
    (re.compile(r" < "), " <= "),
    (re.compile(r" > "), " >= "),
    (re.compile(r" \+ "), " - "),
    (re.compile(r" - "), " + "),
    (re.compile(r" \+= "), " -= "),
    (re.compile(r"\band\b"), "or"),
    (re.compile(r"\bor\b"), "and"),
    (re.compile(r"\btrue\b"), "false"),
    (re.compile(r"\bfalse\b"), "true"),
]


def code_spans(line):
    """Ranges of `line` that are real code (outside strings/char/// comment)."""
    spans, i, n, start = [], 0, len(line), 0
    in_str = in_chr = False
    while i < n:
        c = line[i]
        if in_str:
            if c == "\\":
                i += 2; continue
            if c == '"':
                in_str = False; i += 1; start = i; continue
            i += 1; continue
        if in_chr:
            if c == "\\":
                i += 2; continue
            if c == "'":
                in_chr = False; i += 1; start = i; continue
            i += 1; continue
        if c == '"':
            spans.append((start, i)); in_str = True; i += 1; continue
        if c == "'":
            spans.append((start, i)); in_chr = True; i += 1; continue
        if c == "/" and i + 1 < n and line[i + 1] == "/":
            spans.append((start, i)); return spans
        i += 1
    spans.append((start, n))
    return spans


def in_code(idx, spans):
    return any(a <= idx < b for a, b in spans)


def gen_mutants(path):
    """Yield (path, lineno, col, old_line, new_line, desc) for one file."""
    with open(path) as f:
        lines = f.readlines()
    out = []
    for li, line in enumerate(lines):
        spans = code_spans(line)
        for rx, rep in OPERATORS:
            for m in rx.finditer(line):
                if not in_code(m.start(), spans):
                    continue
                new_line = line[: m.start()] + rep + line[m.end():]
                if new_line == line:
                    continue
                desc = f"'{m.group().strip()}' -> '{rep.strip()}'"
                out.append((path, li, m.start(), line, new_line, desc))
    return out


def run_tests():
    r = subprocess.run(
        ["zig", "build", "test"],
        capture_output=True, text=True,
    )
    return r.returncode, r.stderr


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--max", type=int, default=80)
    ap.add_argument("--seed", type=int, default=1337)
    ap.add_argument("files", nargs="*", default=DEFAULT_FILES)
    args = ap.parse_args()

    print("baseline: zig build test ...", flush=True)
    code, _ = run_tests()
    if code != 0:
        print("ABORT: baseline tests do not pass; fix them first.")
        return 1

    mutants = []
    for path in args.files:
        mutants += gen_mutants(path)
    random.Random(args.seed).shuffle(mutants)
    total_found = len(mutants)
    if len(mutants) > args.max:
        mutants = mutants[: args.max]
    print(f"{total_found} mutants found; testing {len(mutants)} "
          f"(seed={args.seed}, max={args.max})\n", flush=True)

    killed = survived = compile_killed = 0
    survivors = []
    t0 = time.time()
    for n, (path, li, col, old_line, new_line, desc) in enumerate(mutants, 1):
        with open(path) as f:
            original = f.read()
        mutated = original.replace(old_line, new_line, 1)
        try:
            with open(path, "w") as f:
                f.write(mutated)
            code, err = run_tests()
        finally:
            with open(path, "w") as f:
                f.write(original)
        if code == 0:
            survived += 1
            survivors.append((path, li + 1, desc))
            mark = "SURVIVED"
        else:
            killed += 1
            # A test-failure run still prints the "N/M passed" summary; a compile
            # error fails before any test runs, so it never does.
            if "passed" in err:
                mark = "killed (test)"
            else:
                compile_killed += 1
                mark = "killed (compile)"
        print(f"[{n}/{len(mutants)}] {path}:{li+1} {desc}  -> {mark}", flush=True)

    dt = time.time() - t0
    tested = killed + survived
    score = (killed / tested * 100) if tested else 0.0
    print("\n" + "=" * 60)
    test_killed = killed - compile_killed
    print(f"mutation score: {score:.1f}%  ({killed} killed / {tested} tested)")
    print(f"  of killed: {test_killed} caught by a failing test, "
          f"{compile_killed} failed to compile")
    print(f"  survivors: {survived}   elapsed: {dt:.1f}s")
    if survivors:
        print("\nSURVIVORS (tests do not catch these):")
        for path, ln, desc in survivors:
            print(f"  {path}:{ln}  {desc}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
