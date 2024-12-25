const std = @import("std");

pub fn build(b: *std.Build) void {
    const root_path = b.path("src/root.zig");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ----------------------- module ------------------------

    _ = b.addModule("doji", .{
        .root_source_file = root_path,
        .target = target,
        .optimize = optimize,
    });

    // ----------------------- tests -------------------------

    const tests = b.addTest(.{
        .root_source_file = root_path,
        .target = target,
        .optimize = optimize,
    });
    const run_tests = b.addRunArtifact(tests);

    // ----------------------- steps -------------------------

    const test_step = b.step("test", "Run unit tests");
    test_step.dependOn(&run_tests.step);
}
