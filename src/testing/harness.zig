const std = @import("std");
const api = @import("../kernel/api.zig");
const mode = @import("../kernel/mode.zig");
const handles = @import("../kernel/handles.zig");

pub const Result = struct { code: u8, out: []u8, err: []u8 };

/// Drive a verb's `run` in-process over in-memory buffers — the whole point of
/// injecting I/O into Context. Caller frees via `free`.
pub fn runCase(
    alloc: std.mem.Allocator,
    comptime runFn: fn (*api.Context) anyerror!u8,
    args: []const []const u8,
    m: mode.Mode,
    input: []const u8,
) !Result {
    var in_stream = std.io.fixedBufferStream(input);
    var out = std.ArrayList(u8).init(alloc);
    defer out.deinit();
    var err = std.ArrayList(u8).init(alloc);
    defer err.deinit();
    var store = handles.Store{ .dir = null };

    // These must outlive the call: the AnyReader/AnyWriter point into them.
    var in_r = in_stream.reader();
    var out_w = out.writer();
    var err_w = err.writer();

    var ctx = api.Context{
        .gpa = alloc,
        .args = args,
        .mode = m,
        .store = &store,
        .stdin = in_r.any(),
        .stdout = out_w.any(),
        .stderr = err_w.any(),
    };
    const code = try runFn(&ctx);
    return .{ .code = code, .out = try out.toOwnedSlice(), .err = try err.toOwnedSlice() };
}

pub fn free(alloc: std.mem.Allocator, r: Result) void {
    alloc.free(r.out);
    alloc.free(r.err);
}

/// Structural oracle for the agent frame stream: every line is a JSON object
/// with a monotonic `seq` from 1, and a `summary` always terminates.
pub fn assertFramesWellFormed(alloc: std.mem.Allocator, frames: []const u8) !void {
    var it = std.mem.splitScalar(u8, frames, '\n');
    var expect_seq: i64 = 1;
    var count: usize = 0;
    var summary_seen = false;
    while (it.next()) |line| {
        if (line.len == 0) continue;
        var parsed = std.json.parseFromSlice(std.json.Value, alloc, line, .{}) catch return error.FrameNotJson;
        defer parsed.deinit();
        const obj = parsed.value.object;
        try std.testing.expectEqual(expect_seq, obj.get("seq").?.integer);
        expect_seq += 1;
        _ = obj.get("ts").?;
        try std.testing.expect(!summary_seen); // nothing follows a summary
        if (std.mem.eql(u8, obj.get("t").?.string, "summary")) summary_seen = true;
        count += 1;
    }
    if (count > 0) try std.testing.expect(summary_seen);
}
