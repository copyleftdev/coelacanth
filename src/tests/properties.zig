const std = @import("std");
const gen = @import("../testing/gen.zig");
const tac = @import("../verbs/tac.zig");
const comm = @import("../verbs/comm.zig");
const column = @import("../verbs/column.zig");
const handles = @import("../kernel/handles.zig");

const iters = 300;

// ---------------------------------------------------------------------------
// tac: reversing lines twice is the identity (on newline-terminated input).
// ---------------------------------------------------------------------------
test "prop: tac ∘ tac == id on newline-terminated input" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0xC0E1_AACF);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const input = try gen.randomText(a, rand, 8, 10, true);
        const once = try tac.reverseLines(a, input);
        const twice = try tac.reverseLines(a, once.bytes);
        std.testing.expectEqualSlices(u8, input, twice.bytes) catch |e| {
            std.debug.print("\ntac involution failed on: '{s}'\n", .{input});
            return e;
        };
        _ = arena.reset(.retain_capacity);
    }
}

// ---------------------------------------------------------------------------
// comm: metamorphic relations against sorted-distinct set semantics.
// ---------------------------------------------------------------------------
test "prop: comm(a,a) puts everything in 'both'" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0xC0FF_EE01);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const set = try gen.sortedDistinct(a, rand, 12, 6);
        const c = try comm.merge(set, set, false, false, false, std.io.null_writer);
        try std.testing.expectEqual(@as(u64, 0), c.only1);
        try std.testing.expectEqual(@as(u64, 0), c.only2);
        try std.testing.expectEqual(@as(u64, set.len), c.both);
        _ = arena.reset(.retain_capacity);
    }
}

test "prop: comm partition — only1+both==|a|, only2+both==|b|; symmetry" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0xBEEF_0007);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const sa = try gen.sortedDistinct(a, rand, 12, 5);
        const sb = try gen.sortedDistinct(a, rand, 12, 5);
        const c = try comm.merge(sa, sb, false, false, false, std.io.null_writer);
        // Distinct+sorted inputs: the three categories partition each side.
        try std.testing.expectEqual(@as(u64, sa.len), c.only1 + c.both);
        try std.testing.expectEqual(@as(u64, sb.len), c.only2 + c.both);
        // Swapping the arguments swaps only1<->only2 and keeps both.
        const swapped = try comm.merge(sb, sa, false, false, false, std.io.null_writer);
        try std.testing.expectEqual(c.only1, swapped.only2);
        try std.testing.expectEqual(c.only2, swapped.only1);
        try std.testing.expectEqual(c.both, swapped.both);
        _ = arena.reset(.retain_capacity);
    }
}

// ---------------------------------------------------------------------------
// column: content is preserved and columns are aligned.
// ---------------------------------------------------------------------------
const Tok = struct { off: usize, text: []const u8 };

fn tokenize(a: std.mem.Allocator, line: []const u8) ![]Tok {
    var list = std.ArrayList(Tok).init(a);
    var i: usize = 0;
    while (i < line.len) {
        while (i < line.len and line[i] == ' ') i += 1;
        if (i >= line.len) break;
        const start = i;
        while (i < line.len and line[i] != ' ') i += 1;
        try list.append(.{ .off = start, .text = line[start..i] });
    }
    return list.toOwnedSlice();
}

test "prop: column preserves fields and aligns every column" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0xC01A_11A9);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const input = try gen.randomTable(a, rand, 6, 5, 8);
        const f = try column.format(a, input, null, "  ");

        var in_lines = std.mem.splitScalar(u8, input, '\n');
        var out_lines = std.mem.splitScalar(u8, f.bytes, '\n');

        // first-seen offset for each column; must match on every later row
        var col_off = std.AutoHashMap(usize, usize).init(a);
        var row: usize = 0;
        while (in_lines.next()) |in_line| {
            if (in_line.len == 0) continue;
            const out_line = out_lines.next() orelse {
                std.debug.print("\ncolumn produced too few lines\n", .{});
                return error.TooFewLines;
            };
            // No trailing padding: the last cell is never padded.
            if (out_line.len > 0) {
                std.testing.expect(out_line[out_line.len - 1] != ' ') catch |e| {
                    std.debug.print("\ntrailing space in:\n{s}\n", .{f.bytes});
                    return e;
                };
            }
            const in_toks = try tokenize(a, in_line);
            const out_toks = try tokenize(a, out_line);
            try std.testing.expectEqual(in_toks.len, out_toks.len);
            for (in_toks, out_toks, 0..) |it, ot, c| {
                try std.testing.expectEqualStrings(it.text, ot.text); // content preserved
                const gop = try col_off.getOrPut(c);
                if (gop.found_existing) {
                    std.testing.expectEqual(gop.value_ptr.*, ot.off) catch |e| {
                        std.debug.print("\ncolumn {d} misaligned in:\n{s}\n", .{ c, f.bytes });
                        return e;
                    };
                } else {
                    gop.value_ptr.* = ot.off;
                }
            }
            row += 1;
        }
        _ = arena.reset(.retain_capacity);
    }
}

fn contains(set: []const []const u8, x: []const u8) bool {
    for (set) |s| if (std.mem.eql(u8, s, x)) return true;
    return false;
}

// comm output (not just counts): each line's tab prefix must classify it into
// the right category, and its text must actually belong there.
test "prop: comm output — tab prefixes classify every line correctly" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0x7AB5_0C05);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const sa = try gen.sortedDistinct(a, rand, 12, 5);
        const sb = try gen.sortedDistinct(a, rand, 12, 5);
        var buf = std.ArrayList(u8).init(a);
        const c = try comm.merge(sa, sb, false, false, false, buf.writer());

        var n1: u64 = 0;
        var n2: u64 = 0;
        var nb: u64 = 0;
        var it = std.mem.splitScalar(u8, buf.items, '\n');
        while (it.next()) |line| {
            if (line.len == 0) continue;
            if (std.mem.startsWith(u8, line, "\t\t")) {
                nb += 1;
                const t = line[2..];
                try std.testing.expect(contains(sa, t) and contains(sb, t));
            } else if (std.mem.startsWith(u8, line, "\t")) {
                n2 += 1;
                const t = line[1..];
                try std.testing.expect(contains(sb, t) and !contains(sa, t));
            } else {
                n1 += 1;
                try std.testing.expect(contains(sa, line) and !contains(sb, line));
            }
        }
        try std.testing.expectEqual(c.only1, n1);
        try std.testing.expectEqual(c.only2, n2);
        try std.testing.expectEqual(c.both, nb);
        _ = arena.reset(.retain_capacity);
    }
}

test "prop: comm.splitLines round-trips join-with-newline (incl. empty)" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    var prng = std.Random.DefaultPrng.init(0x5911_7011);
    const rand = prng.random();

    var i: usize = 0;
    while (i < iters) : (i += 1) {
        const a = arena.allocator();
        const lines = try gen.sortedDistinct(a, rand, 12, 6); // nonempty words
        var buf = std.ArrayList(u8).init(a);
        for (lines, 0..) |line, idx| {
            if (idx > 0) try buf.append('\n');
            try buf.appendSlice(line);
        }
        if (lines.len > 0) try buf.append('\n');

        const got = try comm.splitLines(a, buf.items);
        try std.testing.expectEqual(lines.len, got.len);
        for (lines, got) |want, have| try std.testing.expectEqualStrings(want, have);
        _ = arena.reset(.retain_capacity);
    }
}

// ---------------------------------------------------------------------------
// store: explain(handle(x)) round-trips through the content-addressed store.
// ---------------------------------------------------------------------------
test "prop: explain(handle(x)) == x round-trips through the store" {
    var arena = std.heap.ArenaAllocator.init(std.testing.allocator);
    defer arena.deinit();
    const a = arena.allocator();

    var tmp = std.testing.tmpDir(.{});
    defer tmp.cleanup();
    const dir_path = try tmp.dir.realpathAlloc(a, ".");

    var store = handles.Store{ .dir = dir_path };
    var prng = std.Random.DefaultPrng.init(0x5709_0113);
    const rand = prng.random();

    var i: usize = 0;
    while (i < 200) : (i += 1) {
        const x = try gen.randomBytes(a, rand, 48);
        var buf: [80]u8 = undefined;
        const h = try store.handle(&buf, "out", x);
        const hex = h["out:".len..];
        const got = (try store.get(a, hex)) orelse {
            std.debug.print("\nhandle {s} not found in store\n", .{h});
            return error.NotFound;
        };
        try std.testing.expectEqualSlices(u8, x, got);
    }
}
