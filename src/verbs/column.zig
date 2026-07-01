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

pub const Formatted = struct { bytes: []u8, rows: usize, cols: usize };

/// Pure core: align `input` into a padded table. `sep = null` tokenizes on
/// whitespace runs; otherwise splits on any byte in `sep`. Each column is padded
/// to its widest cell; the last cell of a row is never trailing-padded. The
/// parsing arena is internal; `bytes` uses the caller's allocator so it outlives
/// the arena. Caller owns `bytes`.
pub fn format(alloc: std.mem.Allocator, input: []const u8, sep: ?[]const u8, outsep: []const u8) !Formatted {
    var arena_state = std.heap.ArenaAllocator.init(alloc);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var rows = std.ArrayList([]const []const u8).init(arena);
    var ncols: usize = 0;
    var lines = std.mem.splitScalar(u8, input, '\n');
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

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    for (rows.items) |r| {
        for (r, 0..) |f, c| {
            try out.appendSlice(f);
            if (c != r.len - 1) {
                var pad = width[c] - f.len;
                while (pad > 0) : (pad -= 1) try out.append(' ');
                try out.appendSlice(outsep);
            }
        }
        try out.append('\n');
    }
    return .{ .bytes = try out.toOwnedSlice(), .rows = rows.items.len, .cols = ncols };
}

pub fn run(ctx: *api.Context) !u8 {
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

    const data = try std.io.getStdIn().readToEndAlloc(ctx.gpa, max_input);
    defer ctx.gpa.free(data);

    const f = try format(ctx.gpa, data, sep, outsep);
    defer ctx.gpa.free(f.bytes);
    try std.io.getStdOut().writeAll(f.bytes);

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init("coel.column", "0.1.0");
        try em.frame("summary", "\"rows\":{d},\"cols\":{d}", .{ f.rows, f.cols });
    }
    return 0;
}
