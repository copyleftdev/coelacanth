const std = @import("std");
const api = @import("../kernel/api.zig");
const stub = @import("stub.zig");

pub const spec = api.Spec{
    .name = "parallel",
    .summary = "Run jobs concurrently with bounded parallelism.",
    .inputs = "a job template + an input list (or stdin)",
    .outputs = "each job's stdout, addressable via handle (payload)",
    .schema = "coel.parallel/0.1.0",
    .frames = &.{ "job_start", "job_done", "summary" },
    .invariants = &.{
        "every job_start has a matching job_done with the same job_id",
        "at most max_par jobs run at once",
        "stdout and stderr of each job are addressable via handles",
    },
    .implemented = false,
};

pub fn run(ctx: *api.Context) !u8 {
    return stub.run(ctx, spec);
}
