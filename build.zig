const std = @import("std");
const sokol = @import("sokol");
const sdl = @import("sdl");

const Child = std.process.Child;

pub fn build(b: *std.Build) !void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});
    const opt_platform = b.option(PlatformAndRenderer, "platform", "Platform to use: sdl, sdl_soft or sokol");
    const platform_renderer = if (target.result.cpu.arch.isWasm()) .sokol else opt_platform orelse .sdl;

    // create the platform module from the chosen platform + renderer
    const mod_platform = getPlatformModule(b, .{
        .platform_renderer = platform_renderer,
        .target = target,
        .optimize = optimize,
    });

    // build lib
    const mod_zi = b.addModule("zimpact", .{
        .root_source_file = b.path("src/zimpact/zimpact.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "platform", .module = mod_platform },
        },
    });
    const lib = b.addStaticLibrary(.{
        .name = "zimpact",
        .root_module = mod_zi,
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

    // build image converter png => qoi
    const qoiconv_step = b.step("qoiconv", "Build qoiconv");
    const qoiconv_exe = addQoiConverter(b);
    qoiconv_step.dependOn(&qoiconv_exe.step);
    b.installArtifact(qoiconv_exe);

    // build image converter wav => qoa
    const qoaconv_step = b.step("qoaconv", "Build qoaconv");
    const qoaconv_exe = addQoaConverter(b);
    qoaconv_step.dependOn(&qoaconv_exe.step);
    b.installArtifact(qoaconv_exe);

    const asset_dir = "samples/zdrop/assets";
    const assets_step = b.step("zdrop_assets", "Build assets");
    try buildAssets(b, .{
        .assets_step = assets_step,
        .asset_dir = asset_dir,
        .qoiconv_exe = qoiconv_exe,
        .qoaconv_exe = qoaconv_exe,
    });
    assets_step.dependOn(qoiconv_step);
    assets_step.dependOn(qoaconv_step);

    // build Z Drop sample
    const sample: []const u8 = "zdrop";
    // main module with sokol and cimgui imports
    const mod_sample = b.createModule(.{
        .root_source_file = b.path(b.fmt("samples/{s}/main.zig", .{sample})),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "zimpact", .module = mod_zi },
        },
    });

    const dep_sokol = b.dependency("sokol", .{
        .target = target,
        .optimize = optimize,
    });

    if (target.result.cpu.arch.isWasm()) {
        try buildWasm(b, .{ .mod_main = mod_sample, .dep_sokol = dep_sokol, .assets_step = assets_step, .shell_file_path = b.path("web/shell.html") });
    } else {
        try buildNative(b, .{
            .name = sample,
            .mod_main = mod_sample,
            .assets_step = assets_step,
            .platform_renderer = platform_renderer,
        });
    }
}

pub const PlatformAndRenderer = enum {
    sdl,
    sdl_soft,
    sokol,
};

pub const PlatformCreateOptions = struct {
    platform_renderer: PlatformAndRenderer = .sdl,
    target: std.Build.ResolvedTarget = undefined,
    optimize: std.builtin.OptimizeMode = undefined,
};

fn getPlatformModule(b: *std.Build, options: PlatformCreateOptions) *std.Build.Module {
    const target = options.target;
    const optimize = options.optimize;

    // create common module
    const mod_common = b.createModule(.{
        .root_source_file = b.path("src/zimpact/common.zig"),
        .target = target,
        .optimize = optimize,
    });

    return switch (options.platform_renderer) {
        .sdl_soft => {
            const sdl_sdk = sdl.init(b, .{});
            // SDL soft platform module
            return b.createModule(.{
                .root_source_file = b.path("src/zimpact/platform_sdl_soft.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "common", .module = mod_common },
                    .{ .name = "sdl", .module = sdl_sdk.getNativeModule() },
                },
            });
        },
        .sdl => {
            const sdl_sdk = sdl.init(b, .{});
            // SDL platform module
            return b.createModule(.{
                .root_source_file = b.path("src/zimpact/platform_sdl.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "common", .module = mod_common },
                    .{ .name = "sdl", .module = sdl_sdk.getNativeModule() },
                },
            });
        },
        .sokol => {
            const dep_sokol = b.dependency("sokol", .{
                .target = target,
                .optimize = optimize,
            });
            // sokol platform module
            return b.createModule(.{
                .root_source_file = b.path("src/zimpact/platform_sokol.zig"),
                .target = target,
                .optimize = optimize,
                .imports = &.{
                    .{ .name = "common", .module = mod_common },
                    .{ .name = "sokol", .module = dep_sokol.module("sokol") },
                },
            });
        },
    };
}

const BuildNativeOptions = struct {
    name: []const u8,
    mod_main: *std.Build.Module,
    assets_step: *std.Build.Step,
    platform_renderer: PlatformAndRenderer,
};

fn buildNative(b: *std.Build, options: BuildNativeOptions) !void {
    // for native platforms, build into a regular executable
    const exe = b.addExecutable(.{
        .name = options.name,
        .root_module = options.mod_main,
    });

    if (options.platform_renderer == .sdl or options.platform_renderer == .sdl_soft) {
        const sdl_sdk = sdl.init(b, .{});
        sdl_sdk.link(exe, .dynamic, sdl.Library.SDL2);
    }

    const install_exe = b.addInstallArtifact(exe, .{});
    install_exe.step.dependOn(options.assets_step);
    b.getInstallStep().dependOn(&install_exe.step);

    const run_cmd = b.addRunArtifact(exe);
    const run_step = b.step(b.fmt("run", .{}), b.fmt("Run {s}.zig example", .{options.name}));
    run_cmd.step.dependOn(&install_exe.step);
    run_step.dependOn(&run_cmd.step);

    if (b.args) |args| {
        run_cmd.addArgs(args);
    }
}

fn convert(b: *std.Build, tool: *std.Build.Step.Compile, input: []const u8, output: []const u8) *std.Build.Step.InstallFile {
    const tool_step = b.addRunArtifact(tool);
    tool_step.addFileArg(b.path(input));
    const out = tool_step.addOutputFileArg(std.fs.path.basename(output));
    return b.addInstallBinFile(out, output);
}

const BuildWasmOptions = struct {
    mod_main: *std.Build.Module,
    dep_sokol: *std.Build.Dependency,
    assets_step: *std.Build.Step,
    shell_file_path: std.Build.LazyPath,
};

// for web builds, the Zig code needs to be built into a library and linked with the Emscripten linker
pub fn buildWasm(b: *std.Build, opts: BuildWasmOptions) !void {
    // build the main file into a library, this is because the WASM 'exe'
    // needs to be linked in a separate build step with the Emscripten linker
    const demo = b.addLibrary(.{
        .name = "demo",
        .root_module = opts.mod_main,
    });

    // get the Emscripten SDK dependency from the sokol dependency
    const dep_emsdk = opts.dep_sokol.builder.dependency("emsdk", .{});

    // create a build step which invokes the Emscripten linker
    const link_step = try sokol.emLinkStep(b, .{
        .lib_main = demo,
        .target = opts.mod_main.resolved_target.?,
        .optimize = opts.mod_main.optimize.?,
        .emsdk = dep_emsdk,
        .use_webgl2 = true,
        .use_emmalloc = true,
        .use_filesystem = true,
        .shell_file_path = opts.shell_file_path,
        .extra_args = &.{ "-sUSE_OFFSET_CONVERTER=1", "--preload-file", "zig-out/bin/assets@assets" },
    });
    // attach to default target
    b.getInstallStep().dependOn(&link_step.step);
    // ...and a special run step to start the web build output via 'emrun'
    const run = sokol.emRunStep(b, .{ .name = "demo", .emsdk = dep_emsdk });
    run.step.dependOn(opts.assets_step);
    run.step.dependOn(&link_step.step);
    b.step("run", "Run demo").dependOn(&run.step);
}

fn addQoiConverter(b: *std.Build) *std.Build.Step.Compile {
    // build qoiconv executable
    const qoiconv_exe = b.addExecutable(.{
        .name = "qoiconv",
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    qoiconv_exe.linkLibC();
    qoiconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoiconv.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });

    return qoiconv_exe;
}

fn addQoaConverter(b: *std.Build) *std.Build.Step.Compile {
    // build qoaconv executable
    const qoaconv_exe = b.addExecutable(.{
        .name = "qoaconv",
        .target = b.graph.host,
        .optimize = .ReleaseFast,
    });
    qoaconv_exe.linkLibC();
    qoaconv_exe.addCSourceFile(.{
        .file = b.path("tools/qoaconv.c"),
        .flags = &[_][]const u8{"-std=c99"},
    });

    return qoaconv_exe;
}

const BuildAssetsOptions = struct {
    assets_step: *std.Build.Step,
    asset_dir: []const u8,
    qoiconv_exe: *std.Build.Step.Compile,
    qoaconv_exe: *std.Build.Step.Compile,
};

pub fn buildAssets(b: *std.Build, options: BuildAssetsOptions) !void {
    // convert the assets and install them
    if (std.fs.cwd().openDir(options.asset_dir, .{ .iterate = true })) |dir| {
        var walker = try dir.walk(b.allocator);
        defer walker.deinit();

        while (try walker.next()) |assets_file| {
            switch (assets_file.kind) {
                .directory => {},
                .file => {
                    const ext = std.fs.path.extension(assets_file.path);
                    const file = std.fs.path.stem(assets_file.basename);

                    const input = b.fmt("{s}/{s}", .{ options.asset_dir, assets_file.path });
                    const out_dir = std.fs.path.dirname(assets_file.path);
                    if (std.mem.eql(u8, ext, ".png")) {
                        // convert .png to .qoi
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}.qoi", .{ d, file }) else b.fmt("assets/{s}.qoi", .{file});
                        options.assets_step.dependOn(&convert(b, options.qoiconv_exe, input, output).step);
                    } else if (std.mem.eql(u8, ext, ".wav")) {
                        // convert .wav to .qoa
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}.qoa", .{ d, file }) else b.fmt("assets/{s}.qoa", .{file});
                        options.assets_step.dependOn(&convert(b, options.qoaconv_exe, input, output).step);
                    } else {
                        // just copy the asset
                        const output = if (out_dir) |d| b.fmt("assets/{s}/{s}{s}", .{ d, file, ext }) else b.fmt("assets/{s}{s}", .{ file, ext });
                        options.assets_step.dependOn(&b.addInstallFileWithDir(b.path(input), .bin, output).step);
                    }
                },
                else => {},
            }
        }
    } else |_| {}
}
