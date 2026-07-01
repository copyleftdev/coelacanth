const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

pub const spec = api.Spec{
    .name = "tee",
    .summary = "Copy stdin to stdout and to each named file.",
    .inputs = "byte stream on stdin; file paths as args; -a to append",
    .outputs = "stdin echoed on stdout (payload); a copy written to each file",
    .schema = "coel.tee/0.1.0",
    .frames = &.{
        .{ .t = "summary", .fields = &.{
            .{ .name = "bytes", .ty = .integer },
            .{ .name = "files", .ty = .integer },
        } },
    },
    .invariants = &.{
        "stdout receives every input byte, unmodified",
        "each named file receives an identical copy",
    },
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

pub fn run(ctx: *api.Context) !u8 {
    const alloc = ctx.gpa;

    var append = false;
    var paths = std.ArrayList([]const u8).init(alloc);
    defer paths.deinit();
    for (ctx.args) |a| {
        if (eql(a, "-a") or eql(a, "--append")) {
            append = true;
        } else {
            try paths.append(a);
        }
    }

    var files = std.ArrayList(std.fs.File).init(alloc);
    defer {
        for (files.items) |f| f.close();
        files.deinit();
    }
    for (paths.items) |p| {
        const f = if (append) blk: {
            const file = try std.fs.cwd().createFile(p, .{ .truncate = false });
            try file.seekFromEnd(0);
            break :blk file;
        } else try std.fs.cwd().createFile(p, .{ .truncate = true });
        try files.append(f);
    }

    var buf: [64 * 1024]u8 = undefined;
    var total: u64 = 0;
    while (true) {
        const n = try ctx.stdin.read(&buf);
        if (n == 0) break;
        try ctx.stdout.writeAll(buf[0..n]);
        for (files.items) |f| try f.writeAll(buf[0..n]);
        total += n;
    }

    if (ctx.mode == .agent) {
        var em = contract.Emitter.init(ctx.stderr, "coel.tee", "0.1.0");
        try em.frame("summary", "\"bytes\":{d},\"files\":{d}", .{ total, paths.items.len });
    }
    return 0;
}
