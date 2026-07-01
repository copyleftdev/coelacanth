const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");
const stub = @import("stub.zig");

pub const spec = api.Spec{
    .name = "watch",
    .summary = "Re-run a command on an interval, reporting each iteration.",
    .inputs = "a command + args, an interval",
    .outputs = "the command's latest stdout (payload)",
    .schema = "coel.watch/0.1.0",
    .frames = &.{ "tick", "summary" },
    .invariants = &.{
        "one tick frame per iteration, in order",
        "tick.changed is true iff output differs from the previous iteration",
        "each iteration's output is addressable via its handle",
    },
    .implemented = false,
};

pub fn run(ctx: *api.Context) !u8 {
    return stub.run(ctx, spec);
}
