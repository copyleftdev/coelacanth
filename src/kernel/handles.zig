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

test "handle is deterministic" {
    var a: [64]u8 = undefined;
    var b: [64]u8 = undefined;
    const h1 = try make(&a, "out", "hello coelacanth");
    const h2 = try make(&b, "out", "hello coelacanth");
    try std.testing.expectEqualStrings(h1, h2);
    try std.testing.expect(std.mem.startsWith(u8, h1, "out:"));
}
