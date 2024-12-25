const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // --------------------- dependencies --------------------

    const doji = b.dependency("doji", .{
        .target = target,
        .optimize = optimize,
    });

    // ---------------------- executable ---------------------

    const exe = b.addExecutable(.{
        .name = "doji",
        .root_source_file = b.path("src/main.zig"),
        .target = target,
        .optimize = optimize,
    });
    exe.root_module.addImport("doji", doji.module("doji"));

    const run_exe = b.addRunArtifact(exe);
    run_exe.step.dependOn(&exe.step);

    // ------------------------ steps ------------------------

    const run_step = b.step("run", "Run the executable");
    run_step.dependOn(&run_exe.step);
}
