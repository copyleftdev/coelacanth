const std = @import("std");
const api = @import("../kernel/api.zig");
const mmode = @import("../kernel/mode.zig");
const contract = @import("../kernel/contract.zig");
const handles = @import("../kernel/handles.zig");
const json = @import("../kernel/json.zig");

pub const spec = api.Spec{
    .name = "parallel",
    .summary = "Run jobs concurrently with bounded parallelism.",
    .inputs = "a command template (with {}) + items from stdin or after :::",
    .outputs = "each job's stdout, grouped per job, addressable via handle (payload)",
    .schema = "coel.parallel/0.1.0",
    .frames = &.{
        .{ .t = "job_start", .fields = &.{
            .{ .name = "job_id", .ty = .integer },
            .{ .name = "cmd", .ty = .string },
        } },
        .{ .t = "job_done", .fields = &.{
            .{ .name = "job_id", .ty = .integer },
            .{ .name = "exit_code", .ty = .integer },
            .{ .name = "dur_ms", .ty = .integer },
            .{ .name = "stdout", .ty = .string, .required = false },
            .{ .name = "stderr", .ty = .string, .required = false },
            .{ .name = "error", .ty = .string, .required = false },
        } },
        .{ .t = "summary", .fields = &.{
            .{ .name = "total", .ty = .integer },
            .{ .name = "ok", .ty = .integer },
            .{ .name = "failed", .ty = .integer },
            .{ .name = "wall_s", .ty = .number },
            .{ .name = "max_par", .ty = .integer },
        } },
    },
    .invariants = &.{
        "every job_start has a matching job_done with the same job_id",
        "at most max_par jobs run at once",
        "stdout and stderr of each job are addressable via handles",
        "each job's stdout is flushed as one contiguous block (never interleaved)",
        "exit code is 0 iff every job exited 0",
    },
};

const max_output_bytes = 16 * 1024 * 1024;

/// Shared state for the worker pool. `io` serializes every write to stdout and
/// every contract frame, so job output never interleaves and `seq` stays
/// monotonic across threads.
const Runner = struct {
    alloc: std.mem.Allocator,
    template: []const []const u8,
    items: []const []const u8,
    mode: mmode.Mode,
    em: *contract.Emitter,
    store: *handles.Store,
    out: std.io.AnyWriter,
    err: std.io.AnyWriter,
    io: std.Thread.Mutex = .{},
    next: std.atomic.Value(usize) = std.atomic.Value(usize).init(0),
    okc: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),
    failedc: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// Substitute the item into the template: replace every `{}`, or append the
    /// item as a final argument if the template has no placeholder.
    fn buildArgv(r: *Runner, item: []const u8) ![]const []const u8 {
        var list = std.ArrayList([]const u8).init(r.alloc);
        errdefer {
            for (list.items) |a| r.alloc.free(a);
            list.deinit();
        }
        var used = false;
        for (r.template) |t| {
            if (std.mem.indexOf(u8, t, "{}") != null) {
                used = true;
                try list.append(try std.mem.replaceOwned(u8, r.alloc, t, "{}", item));
            } else {
                try list.append(try r.alloc.dupe(u8, t));
            }
        }
        if (!used) try list.append(try r.alloc.dupe(u8, item));
        return list.toOwnedSlice();
    }

    fn freeArgv(r: *Runner, argv: []const []const u8) void {
        for (argv) |a| r.alloc.free(a);
        r.alloc.free(argv);
    }

    fn runOne(r: *Runner, id: usize) !void {
        const item = r.items[id];

        const argv = try r.buildArgv(item);
        defer r.freeArgv(argv);

        const cmd = try std.mem.join(r.alloc, " ", argv);
        defer r.alloc.free(cmd);
        const cmd_esc = try json.escape(r.alloc, cmd);
        defer r.alloc.free(cmd_esc);

        r.emitStart(id, cmd_esc, cmd);

        var timer = try std.time.Timer.start();
        const res = std.process.Child.run(.{
            .allocator = r.alloc,
            .argv = argv,
            .max_output_bytes = max_output_bytes,
        }) catch |e| {
            const dur_ms = timer.read() / std.time.ns_per_ms;
            r.emitDoneErr(id, dur_ms, @errorName(e));
            _ = r.failedc.fetchAdd(1, .monotonic);
            return;
        };
        defer r.alloc.free(res.stdout);
        defer r.alloc.free(res.stderr);
        const dur_ms = timer.read() / std.time.ns_per_ms;

        var exit_code: i32 = -1;
        var ok = false;
        switch (res.term) {
            .Exited => |c| {
                exit_code = c;
                ok = (c == 0);
            },
            else => {},
        }

        // Fallible work (handles) before counting, so a failure is tallied once
        // by the worker's catch rather than double-counted.
        var hbo: [80]u8 = undefined;
        var hbe: [80]u8 = undefined;
        const h_out = try r.store.handle(&hbo, "out", res.stdout);
        const h_err = try r.store.handle(&hbe, "err", res.stderr);

        if (ok) {
            _ = r.okc.fetchAdd(1, .monotonic);
        } else {
            _ = r.failedc.fetchAdd(1, .monotonic);
        }
        r.emitDone(id, exit_code, dur_ms, h_out, h_err, res.stdout);
    }

    fn emitStart(r: *Runner, id: usize, cmd_esc: []const u8, cmd_raw: []const u8) void {
        r.io.lock();
        defer r.io.unlock();
        switch (r.mode) {
            .agent => r.em.frame("job_start", "\"job_id\":{d},\"cmd\":\"{s}\"", .{ id, cmd_esc }) catch {},
            .human => r.err.print("[job {d}] ▶ {s}\n", .{ id, cmd_raw }) catch {},
        }
    }

    fn emitDone(r: *Runner, id: usize, exit_code: i32, dur_ms: u64, h_out: []const u8, h_err: []const u8, out_bytes: []const u8) void {
        r.io.lock();
        defer r.io.unlock();
        // Payload passthrough: one contiguous block per job (the mutex is what
        // makes "never interleaved" true).
        r.out.writeAll(out_bytes) catch {};
        switch (r.mode) {
            .agent => r.em.frame(
                "job_done",
                "\"job_id\":{d},\"exit_code\":{d},\"dur_ms\":{d},\"stdout\":\"{s}\",\"stderr\":\"{s}\"",
                .{ id, exit_code, dur_ms, h_out, h_err },
            ) catch {},
            .human => r.err.print("[job {d}] ✓ exit={d} {d}ms out={s}\n", .{ id, exit_code, dur_ms, h_out }) catch {},
        }
    }

    fn emitDoneErr(r: *Runner, id: usize, dur_ms: u64, ename: []const u8) void {
        r.io.lock();
        defer r.io.unlock();
        switch (r.mode) {
            .agent => r.em.frame("job_done", "\"job_id\":{d},\"exit_code\":-1,\"dur_ms\":{d},\"error\":\"{s}\"", .{ id, dur_ms, ename }) catch {},
            .human => r.err.print("[job {d}] ✗ error: {s}\n", .{ id, ename }) catch {},
        }
    }
};

fn worker(r: *Runner) void {
    while (true) {
        const id = r.next.fetchAdd(1, .monotonic);
        if (id >= r.items.len) break;
        r.runOne(id) catch {
            _ = r.failedc.fetchAdd(1, .monotonic);
        };
    }
}

fn fail(w: std.io.AnyWriter, comptime msg: []const u8) !u8 {
    try w.writeAll(msg);
    return 2;
}

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;

    var template = std.ArrayList([]const u8).init(alloc);
    defer template.deinit();
    var inline_items = std.ArrayList([]const u8).init(alloc);
    defer inline_items.deinit();
    var jobs_opt: ?usize = null;
    var seen_sep = false;

    var i: usize = 0;
    while (i < ctx.args.len) : (i += 1) {
        const a = ctx.args[i];
        if (!seen_sep and std.mem.eql(u8, a, ":::")) {
            seen_sep = true;
            continue;
        }
        if (seen_sep) {
            try inline_items.append(a);
            continue;
        }
        if (std.mem.eql(u8, a, "-j") or std.mem.eql(u8, a, "--jobs")) {
            i += 1;
            if (i >= ctx.args.len) return fail(ctx.stderr, "coel parallel: `-j` needs a number\n");
            jobs_opt = std.fmt.parseInt(usize, ctx.args[i], 10) catch return fail(ctx.stderr, "coel parallel: bad -j value\n");
            continue;
        }
        if (std.mem.startsWith(u8, a, "-j") and a.len > 2) {
            jobs_opt = std.fmt.parseInt(usize, a[2..], 10) catch return fail(ctx.stderr, "coel parallel: bad -j value\n");
            continue;
        }
        try template.append(a);
    }

    if (template.items.len == 0) return fail(ctx.stderr, "coel parallel: no command given\n");

    // Items: after ::: (inline), else one per line from stdin.
    var stdin_buf: []u8 = &.{};
    defer if (stdin_buf.len > 0) alloc.free(stdin_buf);
    var items = std.ArrayList([]const u8).init(alloc);
    defer items.deinit();
    if (seen_sep) {
        try items.appendSlice(inline_items.items);
    } else {
        stdin_buf = try ctx.stdin.readAllAlloc(alloc, 1 << 30);
        var it = std.mem.splitScalar(u8, stdin_buf, '\n');
        while (it.next()) |line| {
            const t = std.mem.trimRight(u8, line, "\r");
            if (t.len == 0) continue;
            try items.append(t);
        }
    }

    const cpu = std.Thread.getCpuCount() catch 4;
    var jobs = jobs_opt orelse cpu;
    if (jobs == 0) jobs = cpu;
    const max_par = @min(jobs, @max(items.items.len, 1));

    var em = contract.Emitter.init(ctx.stderr, "coel.parallel", "0.1.0");
    var runner = Runner{
        .alloc = alloc,
        .template = template.items,
        .items = items.items,
        .mode = ctx.mode,
        .em = &em,
        .store = ctx.store,
        .out = ctx.stdout,
        .err = ctx.stderr,
    };

    var timer = try std.time.Timer.start();
    if (items.items.len > 0) {
        const threads = try alloc.alloc(std.Thread, max_par);
        defer alloc.free(threads);
        for (threads) |*t| t.* = try std.Thread.spawn(.{}, worker, .{&runner});
        for (threads) |t| t.join();
    }
    const wall_s = @as(f64, @floatFromInt(timer.read())) / std.time.ns_per_s;

    const okc = runner.okc.load(.monotonic);
    const failedc = runner.failedc.load(.monotonic);
    switch (ctx.mode) {
        .agent => try em.frame(
            "summary",
            "\"total\":{d},\"ok\":{d},\"failed\":{d},\"wall_s\":{d:.3},\"max_par\":{d}",
            .{ items.items.len, okc, failedc, wall_s, max_par },
        ),
        .human => try ctx.stderr.print(
            "done: {d} ok, {d} failed, {d} total in {d:.3}s (max_par={d})\n",
            .{ okc, failedc, items.items.len, wall_s, max_par },
        ),
    }
    return if (failedc == 0) 0 else 1;
}
