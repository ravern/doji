const std = @import("std");

pub fn build(b: *std.Build) void {
    const root_path = b.path("src/root.zig");

    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------- user options --------------------

    const gc_increment_size = b.option(usize, "gc_increment_size", "number of objects to mark per increment") orelse 1024;

    const options = b.addOptions();
    options.addOption(usize, "gc_increment_size", gc_increment_size);

    // ----------------------- module ------------------------

    const module = b.addModule("doji", .{
        .root_source_file = root_path,
        .target = target,
        .optimize = optimize,
    });
    module.addImport("build_options", options.createModule());

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
