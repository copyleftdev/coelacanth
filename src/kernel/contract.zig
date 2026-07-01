const std = @import("std");

/// Emits the shared NDJSON frame stream (see SPEC.md).
///
/// Rule: contract frames go to **stderr**, payload goes to stdout. This lets a
/// pass-through verb like `pv` stream real data on stdout while narrating its
/// progress as structured telemetry on stderr, without corrupting either.
///
/// Every frame carries `t` (type), a monotonic `seq`, and `ts` (ms since epoch,
/// the only nondeterministic field — isolated so an agent can normalize it).
pub const Emitter = struct {
    seq: u64 = 0,
    schema_name: []const u8,
    schema_version: []const u8,

    pub fn init(schema_name: []const u8, schema_version: []const u8) Emitter {
        return .{ .schema_name = schema_name, .schema_version = schema_version };
    }

    /// Write one frame. `fmt`/`args` supply the type-specific fields as a JSON
    /// fragment (no leading comma, no braces), e.g.
    ///   em.frame("progress", "\"bytes\":{d},\"rate_bps\":{d}", .{ n, r });
    /// Pass "" / .{} for a bare frame.
    pub fn frame(self: *Emitter, t: []const u8, comptime fmt: []const u8, args: anytype) !void {
        self.seq += 1;
        const ts = std.time.milliTimestamp();
        const w = std.io.getStdErr().writer();
        try w.print("{{\"t\":\"{s}\",\"seq\":{d},\"ts\":{d}", .{ t, self.seq, ts });
        if (comptime fmt.len > 0) try w.print("," ++ fmt, args);
        try w.print("}}\n", .{});
    }
};
