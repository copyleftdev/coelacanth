const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "watch",
    .summary = "Re-run a command on an interval, reporting each iteration.",
    .inputs = "a command + args; -n <secs> interval (default 2), -c <n> max iterations (0=infinite)",
    .outputs = "human: repainted latest output; agent: no stdout payload — the typed change signal is the product",
    .schema = "coel.watch/0.1.0",
    .frames = &.{
        .{ .t = "tick", .fields = &.{
            .{ .name = "iter", .ty = .integer },
            .{ .name = "exit_code", .ty = .integer },
            .{ .name = "changed", .ty = .boolean },
            .{ .name = "dur_ms", .ty = .integer },
            .{ .name = "out", .ty = .string, .required = false },
            .{ .name = "error", .ty = .string, .required = false },
        } },
        .{ .t = "summary", .fields = &.{
            .{ .name = "iters", .ty = .integer },
            .{ .name = "changes", .ty = .integer },
            .{ .name = "last_exit", .ty = .integer },
        } },
    },
    .invariants = &.{
        "one tick frame per iteration, in order (iter increments from 1)",
        "tick.changed is true iff stdout differs from the previous iteration (false on the first tick)",
        "each iteration's stdout is addressable via its out handle (absent on spawn failure)",
        "a summary frame is emitted on completion or SIGINT",
    },
};

const max_output_bytes = 16 * 1024 * 1024;

/// Set by SIGINT so an infinite watch can break the loop and still emit its
/// summary. nanosleep returns early on signal delivery, so a long interval
/// wakes promptly.
var g_stop = std.atomic.Value(bool).init(false);

fn onSigint(_: c_int) callconv(.C) void {
    g_stop.store(true, .monotonic);
}

fn installSigint() void {
    var act = std.posix.Sigaction{
        .handler = .{ .handler = onSigint },
        .mask = std.posix.empty_sigset,
        .flags = 0,
    };
    std.posix.sigaction(std.posix.SIG.INT, &act, null);
}

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn fail(w: std.io.AnyWriter, comptime msg: []const u8) !u8 {
    try w.writeAll(msg);
    return 2;
}

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;

    var interval_s: f64 = 2.0;
    var count: u64 = 0; // 0 = infinite
    var template = std.ArrayList([]const u8).init(alloc);
    defer template.deinit();

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const a = ctx.args[i];
        if (template.items.len == 0 and (eql(a, "-n") or eql(a, "--interval"))) {
            i += 1;
            if (i >= ctx.args.len) return fail(ctx.stderr, "coel watch: `-n` needs seconds\n");
            interval_s = std.fmt.parseFloat(f64, ctx.args[i]) catch return fail(ctx.stderr, "coel watch: bad -n value\n");
        } else if (template.items.len == 0 and (eql(a, "-c") or eql(a, "--count"))) {
            i += 1;
            if (i >= ctx.args.len) return fail(ctx.stderr, "coel watch: `-c` needs a number\n");
            count = std.fmt.parseInt(u64, ctx.args[i], 10) catch return fail(ctx.stderr, "coel watch: bad -c value\n");
        } else {
            try template.append(a);
        }
    }

    if (template.items.len == 0) return fail(ctx.stderr, "coel watch: no command given\n");

    const interval_ns: u64 = if (interval_s > 0)
        @intFromFloat(interval_s * @as(f64, std.time.ns_per_s))
    else
        0;
    const argv = template.items;

    installSigint();
    var em = contract.Emitter.init(ctx.stderr, "coel.watch", "0.1.0");
    const out = ctx.stdout;

    var iter: u64 = 0;
    var changes: u64 = 0;
    var last_exit: i32 = -1;
    var have_prev = false;
    var prev_hash: [32]u8 = undefined;

    while (true) {
        if (g_stop.load(.monotonic)) break;
        if (count != 0 and iter >= count) break;
        iter += 1;

        var timer = try std.time.Timer.start();
        const res = std.process.Child.run(.{
            .allocator = alloc,
            .argv = argv,
            .max_output_bytes = max_output_bytes,
        }) catch |e| {
            const dur_ms = timer.read() / std.time.ns_per_ms;
            last_exit = -1;
            switch (ctx.mode) {
                .agent => try em.frame("tick", "\"iter\":{d},\"exit_code\":-1,\"changed\":false,\"dur_ms\":{d},\"error\":\"{s}\"", .{ iter, dur_ms, @errorName(e) }),
                .human => try out.print("\x1b[2J\x1b[H[iter {d}] error: {s}\n", .{ iter, @errorName(e) }),
            }
            if (count != 0 and iter >= count) break;
            if (g_stop.load(.monotonic)) break;
            if (interval_ns > 0) std.time.sleep(interval_ns);
            continue;
        };
        defer alloc.free(res.stdout);
        defer alloc.free(res.stderr);
        const dur_ms = timer.read() / std.time.ns_per_ms;

        var exit_code: i32 = -1;
        switch (res.term) {
            .Exited => |c| exit_code = c,
            else => {},
        }
        last_exit = exit_code;

        var h: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(res.stdout, &h, .{});
        const changed = have_prev and !std.mem.eql(u8, &h, &prev_hash);
        if (changed) changes += 1;
        prev_hash = h;
        have_prev = true;

        switch (ctx.mode) {
            .agent => {
                var hb: [80]u8 = undefined;
                const handle = try ctx.store.handle(&hb, "out", res.stdout);
                try em.frame(
                    "tick",
                    "\"iter\":{d},\"exit_code\":{d},\"changed\":{s},\"dur_ms\":{d},\"out\":\"{s}\"",
                    .{ iter, exit_code, if (changed) "true" else "false", dur_ms, handle },
                );
            },
            .human => {
                try out.writeAll("\x1b[2J\x1b[H");
                try out.print("every {d:.1}s  [iter {d}] exit={d} {s}{d}ms\n\n", .{
                    interval_s, iter, exit_code, if (changed) "changed " else "", dur_ms,
                });
                try out.writeAll(res.stdout);
            },
        }

        if (count != 0 and iter >= count) break;
        if (g_stop.load(.monotonic)) break;
        if (interval_ns > 0) std.time.sleep(interval_ns);
    }

    switch (ctx.mode) {
        .agent => try em.frame("summary", "\"iters\":{d},\"changes\":{d},\"last_exit\":{d}", .{ iter, changes, last_exit }),
        .human => try ctx.stderr.print("\nwatched {d} iterations, {d} changes, last_exit={d}\n", .{ iter, changes, last_exit }),
    }
    return 0;
}
