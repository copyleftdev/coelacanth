const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "column",
    .summary = "Align delimited input into a table of padded columns.",
    .inputs = "lines on stdin; -s <sep> input delimiters (default whitespace), -o <sep> output gap (default 2 spaces)",
    .outputs = "the rows with each column left-aligned to its widest cell (payload)",
    .schema = "coel.column/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "rows", .ty = .integer },
            .{ .name = "cols", .ty = .integer },
        } },
    },
    .invariants = &.{
        "column c is padded to the width of the widest cell in column c",
        "the last cell of a row is never trailing-padded",
    },
};

const max_input = 1 << 30;

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn fail(comptime msg: []const u8) !u8 {
    try std.io.getStdErr().writer().writeAll(msg);
    return 2;
}

pub fn run(ctx: *api.Context) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var sep: ?[]const u8 = null; // null => whitespace tokenization
    var outsep: []const u8 = "  ";
    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const a = ctx.args[i];
        if (eql(a, "-t") or eql(a, "--table")) {
            // table mode is the default; accepted for familiarity
        } else if (eql(a, "-s") or eql(a, "--separator")) {
            i += 1;
            if (i >= ctx.args.len) return fail("coel column: `-s` needs a separator\n");
            sep = ctx.args[i];
        } else if (eql(a, "-o") or eql(a, "--output-separator")) {
            i += 1;
            if (i >= ctx.args.len) return fail("coel column: `-o` needs a separator\n");
            outsep = ctx.args[i];
        } else {
            return fail("coel column: unexpected argument\n");
        }
    }

    const data = try std.io.getStdIn().readToEndAlloc(arena, max_input);

    var rows = std.ArrayList([]const []const u8).init(arena);
    var ncols: usize = 0;
    var lines = std.mem.splitScalar(u8, data, '\n');
    while (lines.next()) |line| {
        if (line.len == 0) continue; // skip blank lines
        var fields = std.ArrayList([]const u8).init(arena);
        if (sep) |s| {
            var it = std.mem.splitAny(u8, line, s);
            while (it.next()) |f| try fields.append(f);
        } else {
            var it = std.mem.tokenizeAny(u8, line, " \t");
            while (it.next()) |f| try fields.append(f);
        }
        if (fields.items.len > ncols) ncols = fields.items.len;
        try rows.append(try fields.toOwnedSlice());
    }

    const width = try arena.alloc(usize, ncols);
    @memset(width, 0);
    for (rows.items) |r| {
        for (r, 0..) |f, c| {
            if (f.len > width[c]) width[c] = f.len;
        }
    }

    const out = std.io.getStdOut().writer();
    for (rows.items) |r| {
        for (r, 0..) |f, c| {
            try out.writeAll(f);
            if (c != r.len - 1) {
                var pad = width[c] - f.len;
                while (pad > 0) : (pad -= 1) try out.writeByte(' ');
                try out.writeAll(outsep);
            }
        }
        try out.writeByte('\n');
    }

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init("coel.column", "0.1.0");
        try em.frame("summary", "\"rows\":{d},\"cols\":{d}", .{ rows.items.len, ncols });
    }
    return 0;
}
