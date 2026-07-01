const std = @import("std");
const api = @import("api.zig");

const TOOL = "coelacanth";
const BINARY = "coel";
const VERSION = "0.1.0";

fn jsonStrArray(w: anytype, items: []const []const u8) !void {
    try w.writeByte('[');
    for (items, 0..) |it, i| {
        if (i != 0) try w.writeByte(',');
        try w.print("\"{s}\"", .{it});
    }
    try w.writeByte(']');
}

fn verbObject(w: anytype, s: api.Spec) !void {
    try w.print(
        "{{\"name\":\"{s}\",\"summary\":\"{s}\",\"inputs\":\"{s}\",\"outputs\":\"{s}\",\"schema\":\"{s}\",\"implemented\":{s},\"frames\":",
        .{ s.name, s.summary, s.inputs, s.outputs, s.schema, if (s.implemented) "true" else "false" },
    );
    try jsonStrArray(w, s.frames);
    try w.writeAll(",\"invariants\":");
    try jsonStrArray(w, s.invariants);
    try w.writeByte('}');
}

/// `coel describe [--all]` — the whole capability surface in one deterministic
/// call. This single dump is the AI-first payoff: no scattered man pages.
pub fn describeAll(verbs: []const api.Verb) !void {
    const w = std.io.getStdOut().writer();
    try w.print(
        "{{\"schema\":{{\"name\":\"coel.describe\",\"version\":\"{s}\"}},\"tool\":\"{s}\",\"binary\":\"{s}\",\"verbs\":[",
        .{ VERSION, TOOL, BINARY },
    );
    for (verbs, 0..) |v, i| {
        if (i != 0) try w.writeByte(',');
        try verbObject(w, v.spec);
    }
    try w.writeAll("]}\n");
}

/// `coel describe <verb>` — one verb's contract.
pub fn describeOne(s: api.Spec) !void {
    const w = std.io.getStdOut().writer();
    try w.print(
        "{{\"schema\":{{\"name\":\"coel.describe\",\"version\":\"{s}\"}},\"verb\":",
        .{VERSION},
    );
    try verbObject(w, s);
    try w.writeAll("}\n");
}
