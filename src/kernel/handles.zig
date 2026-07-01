const std = @import("std");

/// A stable, content-addressed pointer into evidence. Summaries stay compact;
/// an agent fetches only what it needs by address (`explain <handle>`).
///
/// Format: "<prefix>:<12 hex chars of BLAKE3(data)>", e.g. "out:9f2c1a0b4d6e".
/// Deterministic: same bytes -> same handle, so results are cacheable.
pub fn make(buf: []u8, prefix: []const u8, data: []const u8) ![]const u8 {
    var digest: [32]u8 = undefined;
    std.crypto.hash.Blake3.hash(data, &digest, .{});
    return std.fmt.bufPrint(buf, "{s}:{s}", .{
        prefix,
        std.fmt.fmtSliceHexLower(digest[0..6]),
    });
}

/// Optional backing store for handle evidence. When `dir` is null the store is
/// disabled and `handle()` behaves exactly like `make()` (a pure content-id,
/// no disk cost). When enabled (via `--store` / `$COEL_STORE`), evidence is
/// persisted content-addressed so `explain` can dereference it later.
pub const Store = struct {
    dir: ?[]const u8 = null,
    tmp_counter: std.atomic.Value(u64) = std.atomic.Value(u64).init(0),

    /// The 12-hex handle prefix comes from the first 6 digest bytes; the store
    /// file is keyed by the *full* 64-hex digest to avoid collisions. Persisting
    /// is best-effort: a store failure never breaks the verb.
    pub fn handle(self: *Store, buf: []u8, prefix: []const u8, data: []const u8) ![]const u8 {
        var digest: [32]u8 = undefined;
        std.crypto.hash.Blake3.hash(data, &digest, .{});
        if (self.dir) |d| self.persist(d, &digest, data) catch {};
        return std.fmt.bufPrint(buf, "{s}:{s}", .{ prefix, std.fmt.fmtSliceHexLower(digest[0..6]) });
    }

    fn persist(self: *Store, dir: []const u8, digest: *const [32]u8, data: []const u8) !void {
        var namebuf: [64]u8 = undefined;
        const name = try std.fmt.bufPrint(&namebuf, "{s}", .{std.fmt.fmtSliceHexLower(digest[0..])});

        var d = try std.fs.cwd().openDir(dir, .{});
        defer d.close();

        // Content-addressed: if it's already there, the bytes are identical.
        if (d.access(name, .{})) |_| return else |_| {}

        // Write to a thread-unique temp file, then atomically rename into place,
        // so a concurrent reader never sees a torn file.
        var tmpbuf: [96]u8 = undefined;
        const n = self.tmp_counter.fetchAdd(1, .monotonic);
        const tmp = try std.fmt.bufPrint(&tmpbuf, "{s}.{d}.tmp", .{ name, n });
        {
            const f = try d.createFile(tmp, .{ .truncate = true });
            defer f.close();
            try f.writeAll(data);
        }
        try d.rename(tmp, name);
    }

    /// Resolve a handle's hex (the part after ':', or a full digest) to bytes.
    /// Prefix match on the store filenames; returns null if disabled or absent.
    /// Caller owns the returned slice.
    pub fn get(self: *Store, alloc: std.mem.Allocator, hex: []const u8) !?[]u8 {
        const dir = self.dir orelse return null;
        var d = std.fs.cwd().openDir(dir, .{ .iterate = true }) catch return null;
        defer d.close();
        var it = d.iterate();
        while (try it.next()) |entry| {
            if (entry.kind != .file) continue;
            if (std.mem.endsWith(u8, entry.name, ".tmp")) continue;
            if (std.mem.startsWith(u8, entry.name, hex)) {
                return try d.readFileAlloc(alloc, entry.name, 1 << 30);
            }
        }
        return null;
    }
};

test "handle is deterministic" {
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;
    const h1 = try make(&a, "out", "hello coelacanth");
    const h2 = try make(&b, "out", "hello coelacanth");
    try std.testing.expectEqualStrings(h1, h2);
    try std.testing.expect(std.mem.startsWith(u8, h1, "out:"));
}

test "disabled store behaves like make" {
    var store = Store{ .dir = null };
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;
    const h1 = try store.handle(&a, "line", "abc");
    const h2 = try make(&b, "line", "abc");
    try std.testing.expectEqualStrings(h2, h1);
}
