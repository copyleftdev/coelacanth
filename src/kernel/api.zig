const std = @import("std");
const mode = @import("mode.zig");
const handles = @import("handles.zig");

/// JSON Schema scalar types we emit for frame fields.
pub const Ty = enum {
    integer,
    number,
    string,
    boolean,

    pub fn json(self: Ty) []const u8 {
        return switch (self) {
            .integer => "integer",
            .number => "number",
            .string => "string",
            .boolean => "boolean",
        };
    }
};

/// One field of a frame, beyond the shared envelope (`t`/`seq`/`ts`).
/// `required = false` marks a conditional field (e.g. `error` on failure).
pub const Field = struct {
    name: []const u8,
    ty: Ty,
    required: bool = true,
};

/// A frame's typed shape: its `t` tag plus the fields it carries. This is the
/// single source of truth — both `describe` (names) and `schema` (JSON Schema)
/// are generated from it, so neither can drift from the other or from the code.
pub const FrameDef = struct {
    t: []const u8,
    fields: []const Field = &.{},
};

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
    /// Typed definitions of the frames this verb may emit (subset of the
    /// SPEC.md vocabulary). Source of truth for `describe` and `schema`.
    frames: []const FrameDef,
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
    /// Evidence store for handle dereferencing; disabled unless `--store` /
    /// `$COEL_STORE` set. Shared (pointer) so parallel workers persist safely.
    store: *handles.Store,
};

/// A registered verb: its contract plus its entry point. `run` returns the
/// process exit code.
pub const Verb = struct {
    spec: Spec,
    run: *const fn (ctx: *Context) anyerror!u8,
};
