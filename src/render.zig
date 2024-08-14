const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
const types = @import("types.zig");
const drawQuad = @import("texture.zig").drawQuad;
const Texture = @import("texture.zig").Texture;
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const Vec2i = types.Vec2i;
const sokol = @import("sokol");
const sapp = sokol.app;
const sgl = sokol.gl;

const RENDER_ATLAS_SIZE = 64;
const RENDER_ATLAS_GRID = 8;
const RENDER_ATLAS_SIZE_PX = (RENDER_ATLAS_SIZE * RENDER_ATLAS_GRID);

const RENDER_SCALE_NONE = 0;
const RENDER_SCALE_DISCRETE = 1;
const RENDER_SCALE_EXACT = 2;

const RENDER_RESIZE_NONE = 0;
const RENDER_RESIZE_WIDTH = 1;
const RENDER_RESIZE_HEIGHT = 2;
const RENDER_RESIZE_ANY = 3;

const RENDER_RESIZE_MODE = RENDER_RESIZE_NONE;

pub const RENDER_WIDTH = 64;
pub const RENDER_HEIGHT = 96;
pub const RENDER_SCALE_MODE = RENDER_SCALE_DISCRETE;

var logical_size: Vec2i = types.vec2i(RENDER_WIDTH, RENDER_HEIGHT);
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;
var inv_screen_scale: f32 = 1.0;
var screen_size: Vec2i = types.vec2i(0, 0);

pub fn framePrepare() void {
    const dw = sapp.width();
    const dh = sapp.height();

    sgl.viewport(0, 0, dw, dh, true);
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0, RENDER_WIDTH, RENDER_HEIGHT, 0.0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
}

pub fn frameEnd() void {
    // TODO:
}

pub fn draw(pos: Vec2, size: Vec2, texture_handle: Texture, uv_offset: Vec2, uv_size: Vec2, color: Rgba) void {
    // if (pos.x > logical_size.x or pos.y > logical_size.y or
    //     pos.x + size.x < 0 or pos.y + size.y < 0)
    // {
    //     return;
    // }

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

pub fn push() void {
    sgl.pushMatrix();
}

pub fn pop() void {
    sgl.popMatrix();
}

pub fn translate(t: Vec2) void {
    sgl.translate(t.x, t.y, 0.0);
}

pub fn scale(t: Vec2) void {
    sgl.scale(t.x, t.y, 1.0);
}

pub fn rotate(rotation: f32) void {
    sgl.rotate(rotation, 0.0, 0.0, 1.0);
}

pub fn renderSize() Vec2i {
    return logical_size;
}

pub fn snapPx(pos: Vec2) Vec2 {
    const sp = pos.mulf(screen_scale);
    return vec2(@round(sp.x), @round(sp.y)).mulf(inv_screen_scale);
}

pub fn resize(avaiable_size: Vec2i) void {
    // Determine Zoom
    if (RENDER_SCALE_MODE == RENDER_SCALE_NONE) {
        screen_scale = 1;
    } else {
        screen_scale = @min(@as(f32, @floatFromInt(avaiable_size.x)) / @as(f32, @floatFromInt(RENDER_WIDTH)), @as(f32, @floatFromInt(avaiable_size.y)) / @as(f32, @floatFromInt(RENDER_HEIGHT)));

        if (RENDER_SCALE_MODE == RENDER_SCALE_DISCRETE) {
            screen_scale = @max(@floor(screen_scale), 0.5);
        }
    }

    // Determine size
    if ((RENDER_RESIZE_MODE & RENDER_RESIZE_WIDTH) != 0) {
        screen_size.x = @max(avaiable_size.x, RENDER_WIDTH);
    } else {
        screen_size.x = @as(i32, @intCast(RENDER_WIDTH)) * @as(i32, @intFromFloat(screen_scale));
    }

    if ((RENDER_RESIZE_MODE & RENDER_RESIZE_HEIGHT) != 0) {
        screen_size.y = @max(avaiable_size.y, RENDER_HEIGHT);
    } else {
        screen_size.y = @as(i32, @intCast(RENDER_HEIGHT)) * @as(i32, @intFromFloat(screen_scale));
    }

    logical_size.x = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.x)) / screen_scale));
    logical_size.y = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.y)) / screen_scale));
    inv_screen_scale = 1.0 / screen_scale;
    // setScreen(screen_size);
}
