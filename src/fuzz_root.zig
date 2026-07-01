// Test root for the `fuzz` build step. Lives at src/ (module root) so the fuzz
// file's `../testing` / `../verbs` imports resolve inside the module.
test {
    _ = @import("tests/fuzz.zig");
}
