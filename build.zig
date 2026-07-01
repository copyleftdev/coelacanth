const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exe = b.addExecutable(.{
        .name = "coel",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());
    if (b.args) |args| run_cmd.addArgs(args);
    const run_step = b.step("run", "Run coelacanth (coel)");
    run_step.dependOn(&run_cmd.step);

    const test_step = b.step("test", "Run unit + property tests (deterministic)");
    const unit_tests = b.addTest(.{
        .root_source_file = b.path("src/test_all.zig"),
        .target = target,
        .optimize = optimize,
    });
    test_step.dependOn(&b.addRunArtifact(unit_tests).step);

    // Fuzz targets live behind their own step so they never gate `zig build
    // test`. Run `zig build fuzz --fuzz` to loop with the coverage UI.
    const fuzz_step = b.step("fuzz", "Run fuzz targets (add --fuzz to loop)");
    const fuzz_tests = b.addTest(.{
        .root_source_file = b.path("src/fuzz_root.zig"),
        .target = target,
        .optimize = optimize,
    });
    fuzz_step.dependOn(&b.addRunArtifact(fuzz_tests).step);
}
