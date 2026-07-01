const std = @import("std");
const api = @import("../kernel/api.zig");
const contract = @import("../kernel/contract.zig");

/// Honest placeholder for a not-yet-implemented verb. It still answers within
/// the contract: agents get a `summary` frame flagging `unimplemented`; humans
/// get a plain note. Nothing pretends to work.
pub fn run(ctx: *api.Context, spec: api.Spec) !u8 {
    switch (ctx.mode) {
        .agent => {
            var em = contract.Emitter.init(spec.schema, "0.1.0");
            try em.frame("summary", "\"status\":\"unimplemented\",\"verb\":\"{s}\"", .{spec.name});
        },
        .human => {
            try std.io.getStdErr().writer().print(
                "coel {s}: not yet implemented (contract declared; run `coel describe {s}`)\n",
                .{ spec.name, spec.name },
            );
        },
    }
    return 0;
}
