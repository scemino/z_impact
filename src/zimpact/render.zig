const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
const types = @import("types.zig");
const drawQuad = @import("texture.zig").drawQuad;
const Texture = @import("texture.zig").Texture;
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sgl = sokol.gl;
const sglue = sokol.glue;
const options = @import("options.zig");

var logical_size: Vec2i = types.vec2i(64, 96);
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;
var inv_screen_scale: f32 = 1.0;
var screen_size: Vec2i = types.vec2i(0, 0);
var pip_normal: sgl.Pipeline = .{};
var pip_lighter: sgl.Pipeline = .{};
var pip: sgl.Pipeline = .{};
var pass_action: sg.PassAction = .{};
pub var NO_TEXTURE: Texture = undefined;
var blend_mode: BlendMode = .normal;

pub const BlendMode = enum { normal, lighter };

/// A renderer is responsible for drawing on the screen. Images, Fonts and
/// Animations ulitmately use the render_* functions to be drawn.
/// Different renderer backends can be implemented by supporting just a handful
/// of functions.
///
/// Called by the platform
pub fn init(size: Vec2i) void {
    logical_size = size;
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });
    // setup sokol-gl
    sgl.setup(.{ .logger = .{ .func = slog.func } });
    // default pass action
    pass_action.colors[0] = .{
        .load_action = sg.LoadAction.CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    var desc: sg.PipelineDesc = .{};
    desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = sg.BlendFactor.SRC_ALPHA,
        .dst_factor_rgb = sg.BlendFactor.ONE_MINUS_SRC_ALPHA,
    };
    pip_normal = sgl.makePipeline(desc);
    desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = sg.BlendFactor.SRC_ALPHA,
        .dst_factor_rgb = .ONE,
    };
    pip_lighter = sgl.makePipeline(desc);
    pip = pip_normal;

    const white_pixels = [1]Rgba{types.white()} ** 4;
    NO_TEXTURE = Texture.init(vec2i(2, 2), &white_pixels);
}

/// Called by the platform
pub fn cleanup() void {
    sgl.destroyPipeline(pip_normal);
    sgl.destroyPipeline(pip_lighter);
    sgl.shutdown();
    sg.shutdown();
}

pub fn framePrepare() void {
    const dw = sapp.width();
    const dh = sapp.height();

    sgl.viewport(0, 0, dw, dh, true);
    sgl.defaults();
    sgl.loadPipeline(pip);
    sgl.matrixModeProjection();
    sgl.ortho(0, @as(f32, @floatFromInt(logical_size.x)), @as(f32, @floatFromInt(logical_size.y)), 0.0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

pub fn frameEnd() void {
    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sgl.draw();
    sg.endPass();
    sg.commit();
}

/// Draws a rect with the given logical position, size, texture, uv-coords and
/// color, transformed by the current transform stack
pub fn draw(pos: Vec2, size: Vec2, texture_handle: Texture, uv_offset: Vec2, uv_size: Vec2, color: Rgba) void {
    if (pos.x > @as(f32, @floatFromInt(logical_size.x)) or pos.y > @as(f32, @floatFromInt(logical_size.y)) or
        pos.x + size.x < 0 or pos.y + size.y < 0)
    {
        return;
    }

    // pos = mulf(pos, screen_scale);
    // size = mulf(size, screen_scale);
    draw_calls += 1;

    const q = .{
        .vertices = .{
            .{ .pos = pos, .uv = uv_offset, .color = color },
            .{ .pos = .{ .x = pos.x + size.x, .y = pos.y }, .uv = .{ .x = uv_offset.x + uv_size.x, .y = uv_offset.y }, .color = color },
            .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .uv = .{ .x = uv_offset.x + uv_size.x, .y = uv_offset.y + uv_size.y }, .color = color },
            .{ .pos = .{ .x = pos.x, .y = pos.y + size.y }, .uv = .{ .x = uv_offset.x, .y = uv_offset.y + uv_size.y }, .color = color },
        },
    };

    // if (transform_stack_index > 0) {
    // 	mat3_t *m = &transform_stack[transform_stack_index];
    // 	for (uint32_t i = 0; i < 4; i++) {
    // 		q.vertices[i].pos = vec2_transform(q.vertices[i].pos, m);
    // 	}
    // }

    drawQuad(q, texture_handle);
}

/// Push the transform stack
pub fn push() void {
    sgl.pushMatrix();
}

/// Pop the transform stack
pub fn pop() void {
    sgl.popMatrix();
}

/// Translate; can only be called if stack was pushed at least once
pub fn translate(t: Vec2) void {
    sgl.translate(t.x, t.y, 0.0);
}

/// Scale; can only be called if stack was pushed at least once
pub fn scale(t: Vec2) void {
    sgl.scale(t.x, t.y, 1.0);
}

/// Rotate; can only be called if stack was pushed at least once
pub fn rotate(rotation: f32) void {
    sgl.rotate(rotation, 0.0, 0.0, 1.0);
}

/// Return the logical size
pub fn renderSize() Vec2i {
    return logical_size;
}

/// Returns a logical position, snapped to real screen pixels
pub fn snapPx(pos: Vec2) Vec2 {
    const sp = pos.mulf(screen_scale);
    return vec2(@round(sp.x), @round(sp.y)).mulf(inv_screen_scale);
}

/// Resize the logical size according to the available window size and the scale
/// and resize mode
pub fn resize(avaiable_size: Vec2i) void {
    // Determine Zoom
    if (options.options.RENDER_SCALE_MODE == options.RENDER_SCALE_NONE) {
        screen_scale = 1;
    } else {
        screen_scale = @min(@as(f32, @floatFromInt(avaiable_size.x)) / @as(f32, @floatFromInt(logical_size.x)), @as(f32, @floatFromInt(avaiable_size.y)) / @as(f32, @floatFromInt(logical_size.y)));

        if (options.options.RENDER_SCALE_MODE == options.RENDER_SCALE_DISCRETE) {
            screen_scale = @max(@floor(screen_scale), 0.5);
        }
    }

    // Determine size
    if ((options.options.RENDER_RESIZE_MODE & options.RENDER_RESIZE_WIDTH) != 0) {
        screen_size.x = @max(avaiable_size.x, logical_size.x);
    } else {
        screen_size.x = @as(i32, @intCast(logical_size.x)) * @as(i32, @intFromFloat(screen_scale));
    }

    if ((options.options.RENDER_RESIZE_MODE & options.RENDER_RESIZE_HEIGHT) != 0) {
        screen_size.y = @max(avaiable_size.y, logical_size.y);
    } else {
        screen_size.y = @as(i32, @intCast(logical_size.y)) * @as(i32, @intFromFloat(screen_scale));
    }

    logical_size.x = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.x)) / screen_scale));
    logical_size.y = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.y)) / screen_scale));
    inv_screen_scale = 1.0 / screen_scale;
}

pub fn setBlendMode(new_mode: BlendMode) void {
    if (new_mode == blend_mode)
        return;

    blend_mode = new_mode;
    pip = if (blend_mode == .normal) pip_normal else pip_lighter;
    sgl.loadPipeline(pip);
}
