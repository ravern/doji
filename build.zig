const std = @import("std");

pub fn build(b: *std.Build) void {
    const root_path = b.path("src/doji.zig");
    const main_path = b.path("src/main.zig");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------- executable -----------------------

    const lib = b.addStaticLibrary(.{
        .name = "doji",
        .root_source_file = root_path,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    const exe = b.addExecutable(.{
        .name = "doji",
        .root_source_file = main_path,
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(exe);

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe.step);

    const run_step = b.step("run", "Run the executable");
    run_step.dependOn(&run_exe.step);

    // ----------------------- tests -------------------------

    const tests = b.addTest(.{
        .root_source_file = root_path,
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
