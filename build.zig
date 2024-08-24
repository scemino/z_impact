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
    });
    mod_zi.addImport("sokol", dep_sokol.module("sokol"));

    const lib = b.addStaticLibrary(.{
        .name = "zimpact",
        .root_source_file = b.path("src/zimpact/zimpact.zig"),
        .target = target,
        .optimize = optimize,
    });

    b.installArtifact(lib);

    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    b.getInstallStep().dependOn(&docs.step);

    for ([_][]const u8{"zdrop"}) |sample| {
        const run_step = b.step(b.fmt("run-{s}", .{sample}), b.fmt("Run {s}.zig example", .{sample}));
        const exe = b.addExecutable(.{
            .name = sample,
            .root_source_file = b.path(b.fmt("samples/{s}/main.zig", .{sample})),
            .target = target,
            .optimize = optimize,
        });

        exe.root_module.addImport("zimpact", mod_zi);
        exe.root_module.addImport("sokol", dep_sokol.module("sokol"));

        const run_cmd = b.addRunArtifact(exe);
        run_cmd.step.dependOn(&b.addInstallArtifact(exe, .{}).step);

        if (b.args) |args| {
            run_cmd.addArgs(args);
        }

        run_step.dependOn(&run_cmd.step);
    }
}
