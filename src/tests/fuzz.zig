const std = @import("std");
const h = @import("../testing/harness.zig");
const column = @import("../verbs/column.zig");
const ts = @import("../verbs/ts.zig");

// Native coverage-guided fuzzing (Zig 0.14, alpha). Kept OUT of the default
// `zig build test` — the fuzzer can spin up its server/loop — and behind its own
// step. Run:  zig build fuzz --fuzz   (loops, serves a live coverage UI)
//         or:  zig build fuzz          (runs each target once over the corpus)
//
// Oracle: whatever the input, every emitted frame parses as JSON, `seq` is
// monotonic from 1, and a `summary` terminates the stream.

fn fuzzColumn(_: void, input: []const u8) anyerror!void {
    const alloc = std.testing.allocator;
    const r = h.runCase(alloc, column.run, &.{}, .agent, input) catch return;
    defer h.free(alloc, r);
    try h.assertFramesWellFormed(alloc, r.err);
}

fn fuzzTs(_: void, input: []const u8) anyerror!void {
    const alloc = std.testing.allocator;
    const r = h.runCase(alloc, ts.run, &.{}, .agent, input) catch return;
    defer h.free(alloc, r);
    try h.assertFramesWellFormed(alloc, r.err);
}

test "fuzz: column frames stay well-formed under arbitrary input" {
    try std.testing.fuzz({}, fuzzColumn, .{});
}

test "fuzz: ts frames stay well-formed under arbitrary input" {
    try std.testing.fuzz({}, fuzzTs, .{});
}
