const std = @import("std");
const h = @import("../testing/harness.zig");
const tac = @import("../verbs/tac.zig");
const column = @import("../verbs/column.zig");
const comm = @import("../verbs/comm.zig");

// run()-level tests over injected in-memory I/O: mode gating and argument
// parsing (the mutation survivors the pure-function tests couldn't reach).

test "run: tac reverses; agent emits a summary frame, human does not" {
    const alloc = std.testing.allocator;

    const ag = try h.runCase(alloc, tac.run, &.{}, .agent, "a\nb\nc\n");
    defer h.free(alloc, ag);
    try std.testing.expectEqual(@as(u8, 0), ag.code);
    try std.testing.expectEqualStrings("c\nb\na\n", ag.out);
    try std.testing.expect(std.mem.indexOf(u8, ag.err, "\"t\":\"summary\"") != null);

    const hu = try h.runCase(alloc, tac.run, &.{}, .human, "a\nb\nc\n");
    defer h.free(alloc, hu);
    try std.testing.expectEqualStrings("c\nb\na\n", hu.out);
    try std.testing.expectEqual(@as(usize, 0), hu.err.len); // no frame in human mode
}

test "run: column aligns, honors -t/-s, and rejects bad args" {
    const alloc = std.testing.allocator;

    const ok = try h.runCase(alloc, column.run, &.{}, .human, "aa b\nc dddd\n");
    defer h.free(alloc, ok);
    try std.testing.expectEqual(@as(u8, 0), ok.code);
    try std.testing.expectEqualStrings("aa  b\nc   dddd\n", ok.out);

    // -t is accepted (kills the `or`->`and` mutant in the flag test).
    const t = try h.runCase(alloc, column.run, &.{"-t"}, .human, "a b\n");
    defer h.free(alloc, t);
    try std.testing.expectEqual(@as(u8, 0), t.code);
    try std.testing.expectEqualStrings("a  b\n", t.out);

    // -s <sep> is accepted and used.
    const s = try h.runCase(alloc, column.run, &.{ "-s", "," }, .human, "a,bb\nccc,d\n");
    defer h.free(alloc, s);
    try std.testing.expectEqual(@as(u8, 0), s.code);
    try std.testing.expectEqualStrings("a    bb\nccc  d\n", s.out);

    const bad = try h.runCase(alloc, column.run, &.{"--bogus"}, .human, "");
    defer h.free(alloc, bad);
    try std.testing.expectEqual(@as(u8, 2), bad.code);
    try std.testing.expect(bad.err.len > 0);
}

test "run: comm needs two files, and renders the three-column diff" {
    const alloc = std.testing.allocator;

    const one = try h.runCase(alloc, comm.run, &.{"only-one"}, .human, "");
    defer h.free(alloc, one);
    try std.testing.expectEqual(@as(u8, 2), one.code);
    try std.testing.expect(one.err.len > 0);

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    try tmp.dir.writeFile(.{ .sub_path = "A", .data = "apple\nbanana\n" });
    try tmp.dir.writeFile(.{ .sub_path = "B", .data = "banana\ncherry\n" });
    const pa = try tmp.dir.realpathAlloc(alloc, "A");
    defer alloc.free(pa);
    const pb = try tmp.dir.realpathAlloc(alloc, "B");
    defer alloc.free(pb);

    const r = try h.runCase(alloc, comm.run, &.{ pa, pb }, .agent, "");
    defer h.free(alloc, r);
    try std.testing.expectEqual(@as(u8, 0), r.code);
    // apple only in A; banana in both (two tabs); cherry only in B (one tab)
    try std.testing.expectEqualStrings("apple\n\t\tbanana\n\tcherry\n", r.out);
    try std.testing.expect(std.mem.indexOf(u8, r.err, "\"both\":1") != null);
}
