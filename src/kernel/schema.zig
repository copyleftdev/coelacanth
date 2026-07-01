const std = @import("std");
const api = @import("api.zig");

const DRAFT = "https://json-schema.org/draft/2020-12/schema";

/// One frame type as a JSON Schema object. `t` is pinned to a const; the
/// envelope fields (`seq`, `ts`) are added to every frame; `additionalProperties`
/// is false so an agent can validate strictly.
fn frameSchema(w: anytype, f: api.FrameDef) !void {
    try w.print("{{\"type\":\"object\",\"properties\":{{\"t\":{{\"const\":\"{s}\"}},", .{f.t});
    try w.writeAll("\"seq\":{\"type\":\"integer\"},\"ts\":{\"type\":\"integer\"}");
    for (f.fields) |fld| {
        try w.print(",\"{s}\":{{\"type\":\"{s}\"}}", .{ fld.name, fld.ty.json() });
    }
    try w.writeAll("},\"required\":[\"t\",\"seq\",\"ts\"");
    for (f.fields) |fld| {
        if (fld.required) try w.print(",\"{s}\"", .{fld.name});
    }
    try w.writeAll("],\"additionalProperties\":false}");
}

/// A verb's whole frame stream: any emitted line is `oneOf` its frame types.
fn oneOf(w: anytype, s: api.Spec) !void {
    try w.print("\"title\":\"{s} frame\",\"oneOf\":[", .{s.schema});
    for (s.frames, 0..) |f, i| {
        if (i != 0) try w.writeByte(',');
        try frameSchema(w, f);
    }
    try w.writeByte(']');
}

/// `coel schema <verb>` — a standalone JSON Schema for that verb's frames.
pub fn one(s: api.Spec) !void {
    const w = std.io.getStdOut().writer();
    try w.print("{{\"$schema\":\"{s}\",", .{DRAFT});
    try oneOf(w, s);
    try w.writeAll("}\n");
}

/// `coel schema` / `coel schema --all` — every verb keyed by name.
pub fn all(verbs: []const api.Verb) !void {
    const w = std.io.getStdOut().writer();
    try w.print("{{\"$schema\":\"{s}\",\"schemas\":{{", .{DRAFT});
    for (verbs, 0..) |v, i| {
        if (i != 0) try w.writeByte(',');
        try w.print("\"{s}\":{{", .{v.spec.name});
        try oneOf(w, v.spec);
        try w.writeByte('}');
    }
    try w.writeAll("}}\n");
}
