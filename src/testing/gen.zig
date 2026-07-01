const std = @import("std");

// Deterministic random test-input generators for the property suite. All take
// an allocator (use an arena in tests so no per-value frees are needed) and a
// std.Random so runs are reproducible from a fixed seed.

fn word(alloc: std.mem.Allocator, rand: std.Random, maxlen: usize) ![]u8 {
    const len = 1 + rand.uintLessThan(usize, maxlen);
    const buf = try alloc.alloc(u8, len);
    for (buf) |*c| c.* = 'a' + rand.uintLessThan(u8, 26);
    return buf;
}

/// Random newline-separated text: 0..max_lines lines, each 0..max_len lowercase
/// letters. `terminate` appends a trailing newline (needed for tac's involution).
pub fn randomText(alloc: std.mem.Allocator, rand: std.Random, max_lines: usize, max_len: usize, terminate: bool) ![]u8 {
    const nlines = rand.uintLessThan(usize, max_lines + 1);
    var out = std.ArrayList(u8).init(alloc);
    var i: usize = 0;
    while (i < nlines) : (i += 1) {
        if (i > 0) try out.append('\n');
        const wlen = rand.uintLessThan(usize, max_len + 1);
        var j: usize = 0;
        while (j < wlen) : (j += 1) try out.append('a' + rand.uintLessThan(u8, 26));
    }
    if (terminate and nlines > 0) try out.append('\n');
    return out.toOwnedSlice();
}

/// Random arbitrary bytes, length 0..max.
pub fn randomBytes(alloc: std.mem.Allocator, rand: std.Random, max: usize) ![]u8 {
    const len = rand.uintLessThan(usize, max + 1);
    const buf = try alloc.alloc(u8, len);
    rand.bytes(buf);
    return buf;
}

fn lessStr(_: void, a: []const u8, b: []const u8) bool {
    return std.mem.lessThan(u8, a, b);
}

/// A sorted, de-duplicated list of random words — the precondition `comm` wants.
pub fn sortedDistinct(alloc: std.mem.Allocator, rand: std.Random, maxn: usize, maxlen: usize) ![]const []const u8 {
    const n = rand.uintLessThan(usize, maxn + 1);
    var list = std.ArrayList([]const u8).init(alloc);
    var i: usize = 0;
    while (i < n) : (i += 1) try list.append(try word(alloc, rand, maxlen));
    std.mem.sort([]const u8, list.items, {}, lessStr);
    var out = std.ArrayList([]const u8).init(alloc);
    for (list.items, 0..) |s, idx| {
        if (idx > 0 and std.mem.eql(u8, s, list.items[idx - 1])) continue;
        try out.append(s);
    }
    return out.toOwnedSlice();
}

/// Newline-terminated table: 1..maxrows rows, each 1..maxcols single-space-
/// separated words. No leading/trailing spaces, so words == whitespace tokens.
pub fn randomTable(alloc: std.mem.Allocator, rand: std.Random, maxrows: usize, maxcols: usize, maxlen: usize) ![]u8 {
    const rows = 1 + rand.uintLessThan(usize, maxrows);
    var out = std.ArrayList(u8).init(alloc);
    var r: usize = 0;
    while (r < rows) : (r += 1) {
        const cols = 1 + rand.uintLessThan(usize, maxcols);
        var c: usize = 0;
        while (c < cols) : (c += 1) {
            if (c > 0) try out.append(' ');
            try out.appendSlice(try word(alloc, rand, maxlen));
        }
        try out.append('\n');
    }
    return out.toOwnedSlice();
}
