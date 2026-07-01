const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "tac",
    .summary = "Reverse the order of input lines.",
    .inputs = "line stream on stdin",
    .outputs = "the same lines in reverse order (payload)",
    .schema = "coel.tac/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "lines", .ty = .integer },
        } },
    },
    .invariants = &.{
        "output is a permutation of input lines in exactly reverse order",
        "agent mode adds only a summary frame on stderr; stdout is identical to human mode",
    },
};

const max_input = 1 << 30;

pub const Reversed = struct { bytes: []u8, lines: usize };

/// Pure core: reverse the input's lines. Output is newline-terminated. Empty
/// input yields empty output (so `reverseLines(reverseLines(x)) == x` for any
/// newline-terminated x). Caller owns `bytes`.
pub fn reverseLines(alloc: std.mem.Allocator, input: []const u8) !Reversed {
    if (input.len == 0) return .{ .bytes = try alloc.alloc(u8, 0), .lines = 0 };

    var lines = std.ArrayList([]const u8).init(alloc);
    defer lines.deinit();
    var it = std.mem.splitScalar(u8, input, '\n');
    while (it.next()) |seg| try lines.append(seg);
    // A trailing '\n' yields a final empty segment that isn't a line.
    if (input[input.len - 1] == '\n') _ = lines.pop();

    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    var i = lines.items.len;
    while (i > 0) {
        i -= 1;
        try out.appendSlice(lines.items[i]);
        try out.append('\n');
    }
    return .{ .bytes = try out.toOwnedSlice(), .lines = lines.items.len };
}

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;
    const data = try ctx.stdin.readAllAlloc(alloc, max_input);
    defer alloc.free(data);

    const r = try reverseLines(alloc, data);
    defer alloc.free(r.bytes);
    try ctx.stdout.writeAll(r.bytes);

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init(ctx.stderr, "coel.tac", "0.1.0");
        try em.frame("summary", "\"lines\":{d}", .{r.lines});
    }
    return 0;
}
