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

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;
    const data = try std.io.getStdIn().readToEndAlloc(alloc, max_input);
    defer alloc.free(data);

    var lines = std.ArrayList([]const u8).init(alloc);
    defer lines.deinit();
    var it = std.mem.splitScalar(u8, data, '\n');
    while (it.next()) |seg| try lines.append(seg);
    // A trailing '\n' yields a final empty segment that isn't a line.
    if (data.len > 0 and data[data.len - 1] == '\n' and lines.items.len > 0) {
        _ = lines.pop();
    }

    const out = std.io.getStdOut().writer();
    var i = lines.items.len;
    while (i > 0) {
        i -= 1;
        try out.writeAll(lines.items[i]);
        try out.writeByte('\n');
    }

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init("coel.tac", "0.1.0");
        try em.frame("summary", "\"lines\":{d}", .{lines.items.len});
    }
    return 0;
}
