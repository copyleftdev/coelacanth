const std = @import("std");

/// Two render modes for every verb. The engine is shared; only the renderer
/// differs. `human` draws pretty, ephemeral output for a terminal; `agent`
/// emits the typed NDJSON contract frames defined in SPEC.md.
pub const Mode = enum { human, agent };

/// Auto-detect the mode.
///
/// Contract telemetry always goes to stderr (stdout is reserved for payload),
/// so the tell is: is stderr a terminal? If a human is watching, render for
/// them; otherwise a machine is consuming the stream, so emit the contract.
/// `--contract` forces agent mode regardless.
pub fn detect(force_contract: bool) Mode {
    if (force_contract) return .agent;
    const stderr_is_tty = std.posix.isatty(std.io.getStdErr().handle);
    return if (stderr_is_tty) .human else .agent;
}
