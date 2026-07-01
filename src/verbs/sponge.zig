const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "sponge",
    .summary = "Soak up all stdin, then write it out — safe for in-place edits.",
    .inputs = "byte stream on stdin; optional output file path",
    .outputs = "all input written to the file (or stdout) only after stdin closes",
    .schema = "coel.sponge/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "bytes", .ty = .integer },
            .{ .name = "to_file", .ty = .boolean },
        } },
    },
    .invariants = &.{
        "stdin is fully consumed before the output is opened or truncated",
        "so `cmd file | coel sponge file` never truncates file mid-read",
    },
};

const max_input = 1 << 30;

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;

    // Read everything first — this is the whole point of sponge.
    const data = try ctx.stdin.readAllAlloc(alloc, max_input);
    defer alloc.free(data);

    const to_file = ctx.args.len >= 1;
    if (to_file) {
        // Only now, after stdin is fully drained, do we open/truncate the target.
        const f = try std.fs.cwd().createFile(ctx.args[0], .{ .truncate = true });
        defer f.close();
        try f.writeAll(data);
    } else {
        try ctx.stdout.writeAll(data);
    }

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init(ctx.stderr, "coel.sponge", "0.1.0");
        try em.frame("summary", "\"bytes\":{d},\"to_file\":{s}", .{ data.len, if (to_file) "true" else "false" });
    }
    return 0;
}
