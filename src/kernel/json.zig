const std = @import("std");

/// Escape a string for embedding inside a JSON string literal. Needed for any
/// user-supplied value (job commands, filenames) that reaches a frame; the
/// controlled strings in specs don't need it, but arbitrary input does.
pub fn escape(alloc: std.mem.Allocator, s: []const u8) ![]u8 {
    var out = std.ArrayList(u8).init(alloc);
    errdefer out.deinit();
    for (s) |c| switch (c) {
        '"' => try out.appendSlice("\\\""),
        '\\' => try out.appendSlice("\\\\"),
        '\n' => try out.appendSlice("\\n"),
        '\r' => try out.appendSlice("\\r"),
        '\t' => try out.appendSlice("\\t"),
        else => if (c < 0x20)
            try out.writer().print("\\u{x:0>4}", .{c})
        else
            try out.append(c),
    };
    return out.toOwnedSlice();
}

test "escape quotes and control chars" {
    const a = std.testing.allocator;
    const got = try escape(a, "he said \"hi\"\n\ttab");
    defer a.free(got);
    try std.testing.expectEqualStrings("he said \\\"hi\\\"\\n\\ttab", got);
}
