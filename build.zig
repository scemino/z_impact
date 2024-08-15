const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    const mod_zi = b.addModule("zimpact", .{
        .root_source_file = b.path("src/zimpact/zimpact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "sokol", .module = dep_sokol.module("sokol") },
        },
    });

    const exe = b.addExecutable(.{
        .name = "z_drop",
        .root_source_file = b.path("src/zdrop/main.zig"),
        .target = target,
        .optimize = optimize,
    });

    exe.root_module.addImport("zimpact", mod_zi);
    exe.root_module.addImport("sokol", dep_sokol.module("sokol"));

    b.installArtifact(exe);

    const run_cmd = b.addRunArtifact(exe);
    run_cmd.step.dependOn(b.getInstallStep());

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
