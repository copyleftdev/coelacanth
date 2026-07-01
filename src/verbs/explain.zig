const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "explain",
    .summary = "Retrieve the evidence bytes behind a handle from the store.",
    .inputs = "a handle (e.g. out:9f2c1a0b4d6e) as the first argument",
    .outputs = "the stored bytes on stdout (payload)",
    .schema = "coel.explain/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "bytes", .ty = .integer },
            .{ .name = "found", .ty = .boolean },
        } },
    },
    .invariants = &.{
        "resolves the handle against the store (--store or $COEL_STORE)",
        "returned bytes are content-addressed: they hash back to the handle",
    },
};

pub fn run(ctx: *api.Context) !u8 {
    if (ctx.args.len < 1) {
        try ctx.stderr.writeAll("usage: coel explain <handle>\n");
        return 2;
    }
    if (ctx.store.dir == null) {
        try ctx.stderr.writeAll("coel explain: no store configured (set --store <dir> or $COEL_STORE)\n");
        return 2;
    }

    // Accept either "prefix:hex" or a bare hex string.
    const raw = ctx.args[0];
    const hex = if (std.mem.indexOfScalar(u8, raw, ':')) |i| raw[i + 1 ..] else raw;

    const bytes = try ctx.store.get(ctx.gpa, hex);
    if (bytes) |b| {
        defer ctx.gpa.free(b);
        try ctx.stdout.writeAll(b);
        if (ctx.mode == .agent) {
            var em = contract.Emitter.init(ctx.stderr, "coel.explain", "0.1.0");
            try em.frame("summary", "\"bytes\":{d},\"found\":true", .{b.len});
        }
        return 0;
    } else {
        if (ctx.mode == .agent) {
            var em = contract.Emitter.init(ctx.stderr, "coel.explain", "0.1.0");
            try em.frame("summary", "\"bytes\":0,\"found\":false", .{});
        } else {
            try ctx.stderr.print("coel explain: handle '{s}' not found in store\n", .{raw});
        }
        return 1;
    }
}
