const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
const types = @import("types.zig");
const drawQuad = @import("texture.zig").drawQuad;
const Texture = @import("texture.zig").Texture;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const sokol = @import("sokol");
const sapp = sokol.app;
const sgl = sokol.gl;

const RENDER_ATLAS_SIZE = 64;
const RENDER_ATLAS_GRID = 32;
const RENDER_ATLAS_SIZE_PX = (RENDER_ATLAS_SIZE * RENDER_ATLAS_GRID);

var logical_size: Vec2i = types.vec2i(1280, 720);
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;

pub fn framePrepare() void {
    const dw = sapp.width();
    const dh = sapp.height();

    sgl.viewport(0, 0, dw, dh, true);
    sgl.defaults();
    sgl.matrixModeProjection();
    sgl.ortho(0, 240.0, 160.0, 0.0, -1, 1);
    sgl.matrixModeModelview();
    sgl.loadIdentity();
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

pub fn renderSize() Vec2i {
    return logical_size;
}
