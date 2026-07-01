const std = @import("std");
const mode = @import("mode.zig");

/// A verb's self-description. The kernel derives `describe`/`schema` output
/// directly from this struct, so a verb can never drift from its own contract:
/// the documentation IS the declaration.
pub const Spec = struct {
    /// Invocation name, e.g. "pv". Also the symlink-dispatch name.
    name: []const u8,
    /// One-line summary of what the verb does.
    summary: []const u8,
    /// What it reads (human-readable).
    inputs: []const u8,
    /// What it writes on stdout (the payload).
    outputs: []const u8,
    /// Contract schema id emitted on stderr in agent mode, e.g. "coel.pv/0.1.0".
    schema: []const u8,
    /// Frame `t` types this verb may emit (subset of SPEC.md vocabulary).
    frames: []const []const u8,
    /// Guarantees an agent may rely on. Keep quote-free (rendered into JSON).
    invariants: []const []const u8,
    /// True once the verb is real; stubs advertise themselves honestly.
    implemented: bool = true,
};

/// Everything a verb needs to run: allocator, its remaining args (globals
/// already stripped), and the resolved render mode.
pub const Context = struct {
    gpa: std.mem.Allocator,
    args: []const []const u8,
    mode: mode.Mode,
};

/// A registered verb: its contract plus its entry point. `run` returns the
/// process exit code.
pub const Verb = struct {
    spec: Spec,
    run: *const fn (ctx: *Context) anyerror!u8,
};
