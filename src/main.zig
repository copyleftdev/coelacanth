const std = @import("std");
const api = @import("kernel/api.zig");
const mode = @import("kernel/mode.zig");
const describe = @import("kernel/describe.zig");
const schema = @import("kernel/schema.zig");
const handles = @import("kernel/handles.zig");

const pv = @import("verbs/pv.zig");
const watch = @import("verbs/watch.zig");
const ts = @import("verbs/ts.zig");
const parallel = @import("verbs/parallel.zig");
const tac = @import("verbs/tac.zig");
const tee = @import("verbs/tee.zig");
const sponge = @import("verbs/sponge.zig");
const column = @import("verbs/column.zig");
const comm = @import("verbs/comm.zig");
const explain = @import("verbs/explain.zig");

const VERSION = "0.1.0";

/// The toolbox. Every verb is self-describing; `coel describe` dumps the whole
/// surface. A living fossil: primitives declared extinct, still swimming.
const registry = [_]api.Verb{
    // streaming set
    .{ .spec = pv.spec, .run = pv.run },
    .{ .spec = watch.spec, .run = watch.run },
    .{ .spec = ts.spec, .run = ts.run },
    .{ .spec = parallel.spec, .run = parallel.run },
    // transform set
    .{ .spec = tac.spec, .run = tac.run },
    .{ .spec = tee.spec, .run = tee.run },
    .{ .spec = sponge.spec, .run = sponge.run },
    .{ .spec = column.spec, .run = column.run },
    .{ .spec = comm.spec, .run = comm.run },
    // evidence
    .{ .spec = explain.spec, .run = explain.run },
};

fn eql(a: []const u8, b: []const u8) bool {
    return std.mem.eql(u8, a, b);
}

fn findVerb(name: []const u8) ?api.Verb {
    for (registry) |v| {
        if (eql(v.spec.name, name)) return v;
    }
    return null;
}

fn stderrPrint(comptime fmt: []const u8, args: anytype) !void {
    try std.io.getStdErr().writer().print(fmt, args);
}

fn usage() !void {
    const w = std.io.getStdOut().writer();
    try w.print("coelacanth (coel) {s} — AI-first Unix primitives with a contract\n\n", .{VERSION});
    try w.writeAll("usage: coel <verb> [args]   (or symlink coel to a verb name)\n\n");
    try w.writeAll("verbs:\n");
    for (registry) |v| {
        const mark = if (v.spec.implemented) "  " else "· ";
        try w.print("  {s}{s: <10} {s}\n", .{ mark, v.spec.name, v.spec.summary });
    }
    try w.writeAll("\nmeta:\n");
    try w.writeAll("  describe [--all|<verb>]   machine-readable capability surface\n");
    try w.writeAll("  schema [--all|<verb>]     JSON Schema for a verb's frames\n");
    try w.writeAll("  version                   print version\n");
    try w.writeAll("  help                      this message\n");
    try w.writeAll("\nglobal flags:\n");
    try w.writeAll("  --contract                force typed NDJSON frames on stderr\n");
    try w.writeAll("  --human                   force pretty terminal output\n");
    try w.writeAll("  --store <dir>             persist handle evidence (or set $COEL_STORE)\n");
    try w.writeAll("\n(· = contract declared, not yet implemented)\n");
}

pub fn main() !u8 {
    var gpa_state = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa_state.deinit();
    const gpa = gpa_state.allocator();

    const argv = try std.process.argsAlloc(gpa);
    defer std.process.argsFree(gpa, argv);

    // Symlink dispatch: if invoked as a verb name (e.g. `pv`), use it directly.
    const prog = std.fs.path.basename(argv[0]);
    var name: ?[]const u8 = null;
    var rest_start: usize = 1;
    if (findVerb(prog) != null) {
        name = prog;
    } else if (argv.len >= 2) {
        name = argv[1];
        rest_start = 2;
    }

    const verb_name = name orelse {
        try usage();
        return 0;
    };

    // Meta subcommands.
    if (eql(verb_name, "help") or eql(verb_name, "--help") or eql(verb_name, "-h")) {
        try usage();
        return 0;
    }
    if (eql(verb_name, "version") or eql(verb_name, "--version")) {
        try std.io.getStdOut().writer().print("coelacanth (coel) {s}\n", .{VERSION});
        return 0;
    }
    if (eql(verb_name, "describe")) {
        const rest = argv[rest_start..];
        if (rest.len == 0 or eql(rest[0], "--all")) {
            try describe.describeAll(&registry);
            return 0;
        }
        if (findVerb(rest[0])) |v| {
            try describe.describeOne(v.spec);
            return 0;
        }
        try stderrPrint("coel describe: unknown verb '{s}'\n", .{rest[0]});
        return 2;
    }
    if (eql(verb_name, "schema")) {
        const rest = argv[rest_start..];
        if (rest.len == 0 or eql(rest[0], "--all")) {
            try schema.all(&registry);
            return 0;
        }
        if (findVerb(rest[0])) |v| {
            try schema.one(v.spec);
            return 0;
        }
        try stderrPrint("coel schema: unknown verb '{s}'\n", .{rest[0]});
        return 2;
    }

    // A real verb.
    const verb = findVerb(verb_name) orelse {
        try stderrPrint("coel: unknown verb '{s}' (try `coel help`)\n", .{verb_name});
        return 2;
    };

    // Strip global flags; hand the rest to the verb.
    var args = std.ArrayList([]const u8).init(gpa);
    defer args.deinit();
    var forced: ?mode.Mode = null;
    var store_dir: ?[]const u8 = null;
    var store_dir_owned: ?[]u8 = null;
    defer if (store_dir_owned) |s| gpa.free(s);

    var k: usize = rest_start;
    while (k < argv.len) : (k += 1) {
        const a = argv[k];
        if (eql(a, "--contract")) {
            forced = .agent;
        } else if (eql(a, "--human")) {
            forced = .human;
        } else if (eql(a, "--store")) {
            k += 1;
            if (k >= argv.len) {
                try stderrPrint("coel: `--store` needs a directory\n", .{});
                return 2;
            }
            store_dir = argv[k];
        } else {
            try args.append(a);
        }
    }
    // Fall back to $COEL_STORE when --store is not given.
    if (store_dir == null) {
        if (std.process.getEnvVarOwned(gpa, "COEL_STORE")) |v| {
            store_dir_owned = v;
            store_dir = v;
        } else |_| {}
    }
    if (store_dir) |d| std.fs.cwd().makePath(d) catch {};

    var store = handles.Store{ .dir = store_dir };
    var ctx = api.Context{
        .gpa = gpa,
        .args = args.items,
        .mode = mode.detect(forced),
        .store = &store,
    };
    return verb.run(&ctx);
}

test {
    std.testing.refAllDeclsRecursive(@This());
    _ = @import("kernel/handles.zig");
}
