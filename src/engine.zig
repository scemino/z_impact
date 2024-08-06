const std = @import("std");
const assert = std.debug.assert;
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const sgl = sokol.gl;
const slog = sokol.log;
const sglue = sokol.glue;
const Vec2 = @import("types.zig").Vec2;
const shaders = @import("shaders.zig");
const types = @import("types.zig");
const Rgba = @import("types.zig").Rgba;
const drawQuad = @import("texture.zig").drawQuad;

/// The real time in seconds since program start
var time_real: f64 = 0.0;

/// The game time in seconds since scene start
var time: f64 = 0.0;

// A global multiplier for how fast game time should advance. Default: 1.0
var time_scale: f64 = 1.0;

// The time difference in seconds from the last frame to the current.
// Typically 0.01666 (assuming 60hz)
var tick: f64 = 0;

// The frame number in this current scene. Increases by 1 for every frame.
var frame: u64 = 0;

/// The map to use for entity vs. world collisions. Reset for each scene.
/// Use engine_set_collision_map() to set it.
// map_t *collision_map,

// The maps to draw. Reset for each scene. Use engine_add_background_map()
// to add.
// map_t *background_maps[ENGINE_MAX_BACKGROUND_MAPS];
// uint32_t background_maps_len;

// A global multiplier that affects the gravity of all entities. This only
// makes sense for side view games. For a top-down game you'd want to have
// it at 0.0. Default: 1.0
var gravity: f32 = 1.0;

// The top left corner of the viewport. Internally just an offset when
// drawing background_maps and entities.
var viewport: Vec2 = .{};

// var pip: sgl.Pipeline = .{};
var pass_action: sg.PassAction = .{};

// Various infos about the last frame
// struct {
// 	int entities;
// 	int checks;
// 	int draw_calls;
// 	float update;
// 	float draw;
// 	float total;
// } perf;

// pub fn init(platform: anytype) void {
pub fn init() void {
    // time_real = platform.now();
    // render_init(platform.screen_size());
    renderInit();
    // sound_init(platform.samplerate());
    // platform_set_audio_mix_cb(sound_mix_stereo);
    // input_init();
    // entities_init();
    // main_init();

    // init_bump_mark = bump_mark();
    // init_images_mark = images_mark();
    // init_sounds_mark = sound_mark();
    // init_textures_mark = textures_mark();
}

pub fn update() void {
    draw();
}

pub fn cleanup() void {
    renderCleanup();
}

fn renderCleanup() void {
    sgl.shutdown();
    sg.shutdown();
}

fn renderInit() void {
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    // setup sokol-gl
    sgl.setup(.{ .logger = .{ .func = slog.func } });

    // default pass action
    pass_action.colors[0] = .{
        .load_action = sg.LoadAction.CLEAR,
        .clear_value = .{ .r = 0.8, .g = 0.8, .b = 0.8, .a = 1.0 },
    };
}

pub fn framePrepare() void {
    const dw = sapp.width();
    const dh = sapp.height();

    sgl.viewport(0, 0, dw, dh, true);
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0, 240.0, 0.0, 160.0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

fn draw() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sgl.draw();
    sg.endPass();
    sg.commit();
}
