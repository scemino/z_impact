const std = @import("std");
const Child = std.process.Child;

pub fn build(b: *std.Build) !void {
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

    // build Z Drop sample
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

    // build qoiconv executable
    const qoiconv_exe = b.addExecutable(.{
        .name = "qoiconv",
        .target = target,
    });
    qoiconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoiconv.c"),
        .flags = &[_][]const u8{},
    });
    b.installArtifact(qoiconv_exe);

    const qoiconv_step = b.step("qoiconv", "Build qoiconv");
    qoiconv_step.dependOn(&qoiconv_exe.step);

    // build qoaconv executable
    const qoaconv_exe = b.addExecutable(.{
        .name = "qoaconv",
        .target = target,
    });
    qoaconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoaconv.c"),
        .flags = &[_][]const u8{},
    });
    b.installArtifact(qoaconv_exe);

    const qoaconv_step = b.step("qoaconv", "Build qoaconv");
    qoaconv_step.dependOn(&qoaconv_exe.step);

    const asset_dir = "samples/zdrop/assets";
    const dir = try std.fs.cwd().openDir(asset_dir, .{ .iterate = true });
    var walker = try dir.walk(b.allocator);
    defer walker.deinit();

    while (try walker.next()) |assets_file| {
        const ext = std.fs.path.extension(assets_file.path);
        const file = try std.fs.path.join(std.heap.page_allocator, &[_][]const u8{ "assets", std.fs.path.stem(assets_file.path) });
        defer std.heap.page_allocator.free(file);

        var input = std.ArrayList(u8).init(std.heap.page_allocator);
        defer input.deinit();
        try input.appendSlice(asset_dir);
        try input.append('/');
        try input.appendSlice(assets_file.path);

        var output = std.ArrayList(u8).init(std.heap.page_allocator);
        defer output.deinit();
        try output.appendSlice(file);

        if (std.mem.eql(u8, ext, ".png")) {
            // convert .png to .qoi
            try output.appendSlice(".qoi");
            convert(b, qoiconv_exe, input.items, output.items);
        } else if (std.mem.eql(u8, ext, ".wav")) {
            // convert .wav to .qoa
            try output.appendSlice(".qoa");
            convert(b, qoaconv_exe, input.items, output.items);
        } else {
            // just copy the asset
            try output.appendSlice(ext);
            b.getInstallStep().dependOn(&b.addInstallFileWithDir(b.path(input.items), .bin, output.items).step);
        }
    }
}

fn convert(b: *std.Build, tool: *std.Build.Step.Compile, input: []const u8, output: []const u8) void {
    const tool_step = b.addRunArtifact(tool);
    tool_step.addFileArg(b.path(input));
    const out = tool_step.addOutputFileArg(output);
    b.getInstallStep().dependOn(&b.addInstallFileWithDir(out, .bin, output).step);
}
