const std = @import("std");
const api = @import("../kernel/api.zig");
const stub = @import("stub.zig");

pub const spec = api.Spec{
    .name = "ts",
    .summary = "Annotate each input line with a timestamp.",
    .inputs = "line stream on stdin",
    .outputs = "each line prefixed with its timestamp (payload)",
    .schema = "coel.ts/0.1.0",
    .frames = &.{ "line", "summary" },
    .invariants = &.{
        "the timestamp is carried as a structured field, not baked into text",
        "one line frame per input line, in order",
    },
    .implemented = false,
};

pub fn run(ctx: *api.Context) !u8 {
    return stub.run(ctx, spec);
}
