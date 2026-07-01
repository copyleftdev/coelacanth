const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "ts",
    .summary = "Annotate each input line with a timestamp.",
    .inputs = "line stream on stdin; -s (since start) / -i (incremental) set human format",
    .outputs = "human: '<stamp> <line>'; agent: raw line on stdout, timestamp in the line frame",
    .schema = "coel.ts/0.1.0",
    .frames = &.{
        .{ .t = "line", .fields = &.{
            .{ .name = "out", .ty = .string },
        } },
        .{ .t = "summary", .fields = &.{
            .{ .name = "lines", .ty = .integer },
            .{ .name = "span_s", .ty = .number },
        } },
    },
    .invariants = &.{
        "in agent mode the payload line is emitted unchanged; the timestamp lives in the frame, never baked into stdout text",
        "one line frame per input line, in order",
        "the envelope ts of a line frame is that line's timestamp",
    },
};

const Stamp = enum { absolute, since_start, incremental };

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

/// Format epoch milliseconds as "YYYY-MM-DD HH:MM:SS" in UTC.
fn fmtAbsolute(w: anytype, ms: i64) !void {
    const secs: u64 = @intCast(@divFloor(ms, 1000));
    const es = std.time.epoch.EpochSeconds{ .secs = secs };
    const yd = es.getEpochDay().calculateYearDay();
    const md = yd.calculateMonthDay();
    const ds = es.getDaySeconds();
    try w.print("{d:0>4}-{d:0>2}-{d:0>2} {d:0>2}:{d:0>2}:{d:0>2}", .{
        yd.year,
        @intFromEnum(md.month),
        @as(u32, md.day_index) + 1,
        ds.getHoursIntoDay(),
        ds.getMinutesIntoHour(),
        ds.getSecondsIntoMinute(),
    });
}

fn writeStamp(w: anytype, stamp: Stamp, ms: i64, start_ms: i64, prev_ms: i64) !void {
    switch (stamp) {
        .absolute => try fmtAbsolute(w, ms),
        .since_start => try w.print("{d:.3}", .{@as(f64, @floatFromInt(ms - start_ms)) / 1000.0}),
        .incremental => try w.print("{d:.3}", .{@as(f64, @floatFromInt(ms - prev_ms)) / 1000.0}),
    }
}

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;

    var stamp: Stamp = .absolute;
    for (ctx.args) |a| {
        if (eql(a, "-s") or eql(a, "--since-start")) {
            stamp = .since_start;
        } else if (eql(a, "-i") or eql(a, "--incremental")) {
            stamp = .incremental;
        } else {
            try ctx.stderr.print("coel ts: unknown option '{s}'\n", .{a});
            return 2;
        }
    }

    var em = contract.Emitter.init(ctx.stderr, "coel.ts", "0.1.0");
    const out = ctx.stdout;
    var br = std.io.bufferedReader(ctx.stdin);
    const rdr = br.reader();

    var line = std.ArrayList(u8).init(alloc);
    defer line.deinit();

    var count: u64 = 0;
    var start_ms: i64 = 0;
    var prev_ms: i64 = 0;
    var last_ms: i64 = 0;

    while (true) {
        line.clearRetainingCapacity();
        var eof = false;
        rdr.streamUntilDelimiter(line.writer(), '\n', null) catch |e| switch (e) {
            error.EndOfStream => {
                if (line.items.len == 0) break; // clean EOF on a line boundary
                eof = true; // trailing line without a newline
            },
            else => return e,
        };

        const content = std.mem.trimRight(u8, line.items, "\r");
        const ms = std.time.milliTimestamp();
        if (count == 0) {
            start_ms = ms;
            prev_ms = ms;
        }
        count += 1;
        last_ms = ms;

        switch (ctx.mode) {
            .human => {
                try writeStamp(out, stamp, ms, start_ms, prev_ms);
                try out.writeByte(' ');
                try out.writeAll(content);
                try out.writeByte('\n');
            },
            .agent => {
                // payload: the line, verbatim
                try out.writeAll(content);
                try out.writeByte('\n');
                // contract: timestamp (envelope ts) + content handle
                var hb: [80]u8 = undefined;
                const h = try ctx.store.handle(&hb, "line", content);
                try em.frame("line", "\"out\":\"{s}\"", .{h});
            },
        }
        prev_ms = ms;
        if (eof) break;
    }

    if (ctx.mode == .agent) {
        const span = if (count > 0)
            @as(f64, @floatFromInt(last_ms - start_ms)) / 1000.0
        else
            0.0;
        try em.frame("summary", "\"lines\":{d},\"span_s\":{d:.3}", .{ count, span });
    }
    return 0;
}
