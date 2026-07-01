const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "comm",
    .summary = "Compare two sorted files line by line (three-column set diff).",
    .inputs = "two sorted file paths; -1 -2 -3 suppress the matching column",
    .outputs = "col1=only in file1, col2=only in file2, col3=in both, tab-indented (payload)",
    .schema = "coel.comm/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "only1", .ty = .integer },
            .{ .name = "only2", .ty = .integer },
            .{ .name = "both", .ty = .integer },
        } },
    },
    .invariants = &.{
        "assumes both inputs are sorted; behavior mirrors POSIX comm",
        "column N is omitted from output when -N is given, but still counted in the summary",
    },
};

const max_input = 1 << 30;

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn splitLines(arena: std.mem.Allocator, data: []const u8) ![]const []const u8 {
    var lines = std.ArrayList([]const u8).init(arena);
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |seg| try lines.append(seg);
    if (data.len > 0 and data[data.len - 1] == '\n' and lines.items.len > 0) {
        _ = lines.pop();
    }
    return lines.toOwnedSlice();
}

pub const Counts = struct { only1: u64 = 0, only2: u64 = 0, both: u64 = 0 };

/// Pure core: walk two sorted line lists, emit the three-column diff through
/// `writer`, and return the category counts. Pass `std.io.null_writer` to count
/// without producing output. Counts reflect all lines regardless of suppression.
pub fn merge(a: []const []const u8, b: []const []const u8, s1: bool, s2: bool, s3: bool, writer: anytype) !Counts {
    // Tab indentation depends on which lower columns are shown (POSIX comm).
    const tab2: []const u8 = if (s1) "" else "\t";
    const tab3: []const u8 = if (s1 and s2) "" else if (!s1 and !s2) "\t\t" else "\t";

    var c = Counts{};
    var i: usize = 0;
    var j: usize = 0;
    while (i < a.len and j < b.len) {
        switch (std.mem.order(u8, a[i], b[j])) {
            .lt => {
                c.only1 += 1;
                if (!s1) try writer.print("{s}\n", .{a[i]});
                i += 1;
            },
            .gt => {
                c.only2 += 1;
                if (!s2) try writer.print("{s}{s}\n", .{ tab2, b[j] });
                j += 1;
            },
            .eq => {
                c.both += 1;
                if (!s3) try writer.print("{s}{s}\n", .{ tab3, a[i] });
                i += 1;
                j += 1;
            },
        }
    }
    while (i < a.len) : (i += 1) {
        c.only1 += 1;
        if (!s1) try writer.print("{s}\n", .{a[i]});
    }
    while (j < b.len) : (j += 1) {
        c.only2 += 1;
        if (!s2) try writer.print("{s}{s}\n", .{ tab2, b[j] });
    }
    return c;
}

pub fn run(ctx: *api.Context) !u8 {
    var arena_state = std.heap.ArenaAllocator.init(ctx.gpa);
    defer arena_state.deinit();
    const arena = arena_state.allocator();

    var s1 = false;
    var s2 = false;
    var s3 = false;
    var file_paths = std.ArrayList([]const u8).init(arena);
    for (ctx.args) |a| {
        if (eql(a, "-1")) {
            s1 = true;
        } else if (eql(a, "-2")) {
            s2 = true;
        } else if (eql(a, "-3")) {
            s3 = true;
        } else {
            try file_paths.append(a);
        }
    }
    if (file_paths.items.len != 2) {
        try std.io.getStdErr().writer().writeAll("coel comm: need exactly two files\n");
        return 2;
    }

    const da = try std.fs.cwd().readFileAlloc(arena, file_paths.items[0], max_input);
    const db = try std.fs.cwd().readFileAlloc(arena, file_paths.items[1], max_input);
    const a = try splitLines(arena, da);
    const b = try splitLines(arena, db);

    const out = std.io.getStdOut().writer();
    const c = try merge(a, b, s1, s2, s3, out);

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init("coel.comm", "0.1.0");
        try em.frame("summary", "\"only1\":{d},\"only2\":{d},\"both\":{d}", .{ c.only1, c.only2, c.both });
    }
    return 0;
}
