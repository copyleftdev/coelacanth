const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "pv",
    .summary = "Pass stdin to stdout while reporting throughput.",
    .inputs = "byte stream on stdin",
    .outputs = "identical byte stream on stdout (payload unchanged)",
    .schema = "coel.pv/0.1.0",
    .frames = &.{
        .{ .t = "progress", .fields = &.{
            .{ .name = "bytes", .ty = .integer },
            .{ .name = "rate_bps", .ty = .integer },
        } },
        .{ .t = "summary", .fields = &.{
            .{ .name = "total_bytes", .ty = .integer },
            .{ .name = "elapsed_s", .ty = .number },
            .{ .name = "avg_rate_bps", .ty = .integer },
        } },
    },
    .invariants = &.{
        "stdout bytes equal stdin bytes, in order, unmodified",
        "contract frames are written only to stderr",
        "exactly one summary frame is emitted, last",
        "seq increases by one per frame starting at 1",
    },
};

const buf_size = 64 * 1024;
const report_interval_ns: u64 = 500 * std.time.ns_per_ms;

fn rateBps(total: u64, elapsed_ns: u64) u64 {
    if (elapsed_ns == 0) return 0;
    const r = @as(u128, total) * std.time.ns_per_s / elapsed_ns;
    return std.math.cast(u64, r) orelse std.math.maxInt(u64);
}

fn reportHuman(w: std.io.AnyWriter, total: u64, elapsed_ns: u64) !void {
    const secs = @as(f64, @floatFromInt(elapsed_ns)) / std.time.ns_per_s;
    try w.print("\r  {d} bytes  {d} B/s  {d:.1}s   ", .{ total, rateBps(total, elapsed_ns), secs });
}

pub fn run(ctx: *api.Context) !u8 {
    _ = ctx.args;
    var em = contract.Emitter.init(ctx.stderr, "coel.pv", "0.1.0");

    var timer = try std.time.Timer.start();
    var buf: [buf_size]u8 = undefined;
    var total: u64 = 0;
    var last_report_ns: u64 = 0;

    while (true) {
        const n = try ctx.stdin.read(&buf);
        if (n == 0) break;
        try ctx.stdout.writeAll(buf[0..n]);
        total += n;

        const elapsed = timer.read();
        if (elapsed - last_report_ns >= report_interval_ns) {
            switch (ctx.mode) {
                .agent => try em.frame("progress", "\"bytes\":{d},\"rate_bps\":{d}", .{ total, rateBps(total, elapsed) }),
                .human => try reportHuman(ctx.stderr, total, elapsed),
            }
            last_report_ns = elapsed;
        }
    }

    const elapsed = timer.read();
    const secs = @as(f64, @floatFromInt(elapsed)) / std.time.ns_per_s;
    switch (ctx.mode) {
        .agent => try em.frame(
            "summary",
            "\"total_bytes\":{d},\"elapsed_s\":{d:.3},\"avg_rate_bps\":{d}",
            .{ total, secs, rateBps(total, elapsed) },
        ),
        .human => {
            try reportHuman(ctx.stderr, total, elapsed);
            try ctx.stderr.writeByte('\n');
        },
    }
    return 0;
}
