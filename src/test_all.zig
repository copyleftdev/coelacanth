// Aggregating test root: referencing a file with `_ = @import(...)` pulls its
// `test` blocks into the run, so `zig build test` executes every test in the
// project (unit tests next to code + the property suite).
test {
    _ = @import("main.zig");
    _ = @import("kernel/api.zig");
    _ = @import("kernel/mode.zig");
    _ = @import("kernel/contract.zig");
    _ = @import("kernel/handles.zig");
    _ = @import("kernel/json.zig");
    _ = @import("kernel/describe.zig");
    _ = @import("kernel/schema.zig");
    _ = @import("verbs/pv.zig");
    _ = @import("verbs/watch.zig");
    _ = @import("verbs/ts.zig");
    _ = @import("verbs/parallel.zig");
    _ = @import("verbs/tac.zig");
    _ = @import("verbs/tee.zig");
    _ = @import("verbs/sponge.zig");
    _ = @import("verbs/column.zig");
    _ = @import("verbs/comm.zig");
    _ = @import("verbs/explain.zig");
    _ = @import("tests/properties.zig");
    _ = @import("tests/cli.zig");
}
