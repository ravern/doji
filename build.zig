const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // ------------------- Zig module ------------------------

    const module = b.addModule("doji", .{
        .root_source_file = b.path("src/doji.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{},
    });

    // ----------------- REPL executable ---------------------

    const repl_exe = b.addExecutable(.{
        .name = "doji",
        .root_source_file = b.path("src/repl.zig"),
        .target = target,
        .optimize = optimize,
    });
    repl_exe.root_module.addImport("doji", module);

    const repl_install = b.addInstallArtifact(repl_exe, .{});
    repl_install.step.dependOn(&repl_exe.step);

    const repl_run = b.addRunArtifact(repl_exe);
    repl_run.step.dependOn(&repl_install.step);

    const repl_step = b.step("repl", "Start a REPL session");
    repl_step.dependOn(&repl_run.step);

    // ----------------------- tests -------------------------

    const tests_exe = b.addTest(.{
        .root_source_file = b.path("src/doji.zig"),
        .target = target,
        .optimize = optimize,
    });

    const tests_run = b.addRunArtifact(tests_exe);
    tests_run.step.dependOn(&tests_exe.step);

    const tests_step = b.step("test", "Run unit tests");
    tests_step.dependOn(&tests_run.step);
}
