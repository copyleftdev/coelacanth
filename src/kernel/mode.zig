const std = @import("std");

/// Two render modes for every verb. The engine is shared; only the renderer
/// differs. `human` draws pretty, ephemeral output for a terminal; `agent`
/// emits the typed NDJSON contract frames defined in SPEC.md.
pub const Mode = enum { human, agent };

/// Resolve the mode. If `forced` is non-null (`--contract` → agent,
/// `--human` → human), honor it. Otherwise auto-detect: contract telemetry
/// goes to stderr (stdout is reserved for payload), so the tell is whether
/// stderr is a terminal — a human is watching iff it is.
pub fn detect(forced: ?Mode) Mode {
    if (forced) |m| return m;
    const stderr_is_tty = std.posix.isatty(std.io.getStdErr().handle);
    return if (stderr_is_tty) .human else .agent;
}
