const std = @import("std");
const sokol = @import("sokol");

const Child = std.process.Child;
var mod_zi: *std.Build.Module = undefined;

var assets_step: *std.Build.Step = undefined;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    mod_zi = b.addModule("zimpact", .{
        .root_source_file = b.path("src/zimpact/zimpact.zig"),
        .target = target,
        .optimize = optimize,
    });
    mod_zi.addImport("sokol", dep_sokol.module("sokol"));

    // build lib
    const lib = b.addStaticLibrary(.{
        .name = "zimpact",
        .root_source_file = b.path("src/zimpact/zimpact.zig"),
        .target = target,
        .optimize = optimize,
    });
    b.installArtifact(lib);

    // build docs
    const docs = b.addInstallDirectory(.{
        .source_dir = lib.getEmittedDocs(),
        .install_dir = .prefix,
        .install_subdir = "docs",
    });
    var docs_step = b.step("docs", "Build docs");
    docs_step.dependOn(&docs.step);
    b.getInstallStep().dependOn(docs_step);

    // build qoiconv executable
    const qoiconv_exe = b.addExecutable(.{
        .name = "qoiconv",
        .target = b.host,
        .optimize = .ReleaseFast,
    });
    qoiconv_exe.linkLibC();
    qoiconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoiconv.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });

    const qoiconv_step = b.step("qoiconv", "Build qoiconv");
    qoiconv_step.dependOn(&qoiconv_exe.step);

    // build qoaconv executable
    const qoaconv_exe = b.addExecutable(.{
        .name = "qoaconv",
        .target = b.host,
        .optimize = .ReleaseFast,
    });
    qoaconv_exe.linkLibC();
    qoaconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoaconv.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });

    const qoaconv_step = b.step("qoaconv", "Build qoaconv");
    qoaconv_step.dependOn(&qoaconv_exe.step);

    // convert the assets and install them
    assets_step = b.step("assets", "Build assets");
    assets_step.dependOn(qoiconv_step);
    assets_step.dependOn(qoaconv_step);

    const asset_dir = "samples/zdrop/assets";
    if (std.fs.cwd().openDir(asset_dir, .{ .iterate = true })) |dir| {
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();

        while (try walker.next()) |assets_file| {
            switch (assets_file.kind) {
                .directory => {},
                .file => {
                    const ext = std.fs.path.extension(assets_file.path);
                    const file = std.fs.path.stem(assets_file.basename);

                    const input = b.fmt("{s}/{s}", .{ asset_dir, assets_file.path });
                    const out_dir = std.fs.path.dirname(assets_file.path);
                    if (std.mem.eql(u8, ext, ".png")) {
                        // convert .png to .qoi
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}.qoi", .{ d, file }) else b.fmt("assets/{s}.qoi", .{file});
                        assets_step.dependOn(&convert(b, qoiconv_exe, input, output).step);
                    } else if (std.mem.eql(u8, ext, ".wav")) {
                        // convert .wav to .qoa
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}.qoa", .{ d, file }) else b.fmt("assets/{s}.qoa", .{file});
                        assets_step.dependOn(&convert(b, qoaconv_exe, input, output).step);
                    } else {
                        // just copy the asset
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}{s}", .{ d, file, ext }) else b.fmt("assets/{s}{s}", .{ file, ext });
                        assets_step.dependOn(&b.addInstallFileWithDir(b.path(input), .bin, output).step);
                    }
                },
                else => {},
            }
        }

        // build Z Drop sample
        const sample: []const u8 = "zdrop";

        if (!target.result.isWasm()) {
            const run_step = b.step(b.fmt("run", .{}), b.fmt("Run {s}.zig example", .{sample}));
            // for native platforms, build into a regular executable
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

            run_step.dependOn(assets_step);
            run_step.dependOn(&run_cmd.step);
        } else {
            try buildWeb(b, target, optimize, dep_sokol);
        }
    } else |_| {}
}

fn convert(b: *std.Build, tool: *std.Build.Step.Compile, input: []const u8, output: []const u8) *std.Build.Step.InstallFile {
    const tool_step = b.addRunArtifact(tool);
    tool_step.addFileArg(b.path(input));
    const out = tool_step.addOutputFileArg(std.fs.path.basename(output));
    // b.getInstallStep().dependOn(&b.addInstallBinFile(out, output).step);
    return b.addInstallBinFile(out, output);
}

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
fn buildWeb(b: *std.Build, target: std.Build.ResolvedTarget, optimize: std.builtin.OptimizeMode, dep_sokol: *std.Build.Dependency) !void {
    const sample = b.addStaticLibrary(.{
        .name = "zdrop",
        .target = target,
        .optimize = optimize,
        .root_source_file = b.path("samples/zdrop/main.zig"),
    });
    sample.root_module.addImport("zimpact", mod_zi);
    sample.root_module.addImport("sokol", dep_sokol.module("sokol"));

    // create a build step which invokes the Emscripten linker
    const emsdk = dep_sokol.builder.dependency("emsdk", .{});
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = sample,
        .target = target,
        .optimize = optimize,
        .emsdk = emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = true,
        .shell_file_path = "web/shell.html",
        .extra_args = &.{ "-sUSE_OFFSET_CONVERTER=1", "--preload-file", "zig-out/bin/assets@assets" },
    });
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "zdrop", .emsdk = emsdk });
    run.step.dependOn(assets_step);
    run.step.dependOn(&link_step.step);
    b.step("run", "Run zdrop").dependOn(&run.step);
}
