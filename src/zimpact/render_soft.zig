const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
const sdl = @import("sdl");
pub const cmn = @import("common");
const utils = cmn.utils;
const platform = @import("platform_sdl_soft.zig");
const alloc = cmn.alloc;
const types = cmn.types;
const texture = cmn.texture;
const Texture = texture.Texture;
const Quad = texture.Quad;
const Vertex = texture.Vertex;
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const fromVec2i = types.fromVec2i;
const fromVec2 = types.fromVec2;
const Mat3 = types.Mat3;
const options = cmn.opt;
const shd = cmn.shd;

var screenbuffer: ?*sdl.SDL_Texture = null;
var screenbuffer_size: Vec2i = vec2i(0, 0);

const InternalTexture = struct {
    size: Vec2i,
    pixels: []Rgba,
};

var textures: [options.options.RENDER_TEXTURES_MAX]InternalTexture = undefined;

var screen_pitch: i32 = 0;
var screen_ppr: i32 = 0;
var screen_buffer: []Rgba = undefined;

var logical_size: Vec2i = undefined;
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;
var inv_screen_scale: f32 = 1.0;
var screen_size: Vec2i = undefined;

pub var NO_TEXTURE: Texture = undefined;
var blend_mode: BlendMode = .normal;
var backbuffer_size: Vec2i = undefined;
var window_size: Vec2i = undefined;

var transform_stack: [options.options.RENDER_TRANSFORM_STACK_SIZE]Mat3 = undefined;
var transform_stack_index: usize = 0;

var quad_buffer: [options.options.RENDER_BUFFER_CAPACITY * 4]Vertex = undefined;
var index_buffer: [options.options.RENDER_BUFFER_CAPACITY * 6]u16 = undefined;
var quad_buffer_len: usize = 0;
var tex_buffer_len: usize = 0;

pub const BlendMode = enum { normal, lighter };

/// A renderer is responsible for drawing on the screen. Images, Fonts and
/// Animations ulitmately use the render_* functions to be drawn.
/// Different renderer backends can be implemented by supporting just a handful
/// of functions.
///
/// Called by the platform
pub fn init() void {
    // nothing
}

/// Called by the engine
pub fn cleanup() void {
    // nothing
}

/// Called by the engine
pub fn framePrepare() void {
    screen_ppr = @divTrunc(screen_pitch, @sizeOf(Rgba));
    @memset(screen_buffer[0..@intCast(screen_size.x * screen_size.y)], types.transparent());
}

/// Called by the engine
pub fn frameEnd() void {}

/// Draws a rect with the given logical position, size, texture, uv-coords and
/// color, transformed by the current transform stack
pub fn draw(p: Vec2, s: Vec2, texture_handle: Texture, uv_offset: Vec2, uv_size: Vec2, color: Rgba) void {
    var pos = p;
    var size = s;
    if (pos.x > @as(f32, @floatFromInt(logical_size.x)) or pos.y > @as(f32, @floatFromInt(logical_size.y)) or
        pos.x + size.x < 0 or pos.y + size.y < 0)
    {
        return;
    }

    pos = pos.mulf(screen_scale);
    size = size.mulf(screen_scale);
    draw_calls += 1;

    const uv0: Vec2 = uv_offset;
    const uv1: Vec2 = vec2(uv_offset.x + uv_size.x, uv_offset.y);
    const uv2: Vec2 = vec2(uv_offset.x + uv_size.x, uv_offset.y + uv_size.y);
    const uv3: Vec2 = vec2(uv_offset.x, uv_offset.y + uv_size.y);

    var vertices = [4]Vertex{
        .{ .pos = pos, .uv = uv0, .color = color },
        .{ .pos = .{ .x = pos.x + size.x, .y = pos.y }, .uv = uv1, .color = color },
        .{ .pos = .{ .x = pos.x + size.x, .y = pos.y + size.y }, .uv = uv2, .color = color },
        .{ .pos = .{ .x = pos.x, .y = pos.y + size.y }, .uv = uv3, .color = color },
    };

    if (transform_stack_index > 0) {
        const m = transform_stack[transform_stack_index];
        for (0..4) |i| {
            vertices[i].pos = vertices[i].pos.transform(m);
        }
    }

    drawQuad(.{ .vertices = vertices }, texture_handle);
}

pub fn drawQuad(quad: Quad, texture_handle: Texture) void {
    assert(texture_handle.index < texture.textures_len);

    // FIXME: this only handles axis aligned quads; rotation/shearing is not
    // supported.

    const v = quad.vertices;
    const color = v[0].color;

    var dx: i32 = @intFromFloat(v[0].pos.x);
    var dy: i32 = @intFromFloat(v[0].pos.y);
    var dw: i32 = @as(i32, @intFromFloat(v[2].pos.x)) - dx;
    var dh: i32 = @as(i32, @intFromFloat(v[2].pos.y)) - dy;
    const dxf: f32 = @as(f32, @floatFromInt(dx));
    const dyf: f32 = @as(f32, @floatFromInt(dy));

    const src_size = textures[texture_handle.index].size;
    const src_px = textures[texture_handle.index].pixels;

    var uv_tl = fromVec2(v[0].uv);
    uv_tl.x = utils.clamp(uv_tl.x, 0, src_size.x);
    uv_tl.y = utils.clamp(uv_tl.y, 0, src_size.y);

    var uv_br = fromVec2(v[2].uv);
    uv_br.x = utils.clamp(uv_br.x, 0, src_size.x);
    uv_br.y = utils.clamp(uv_br.y, 0, src_size.y);

    var sx: f32 = @floatFromInt(uv_tl.x);
    var sy: f32 = @floatFromInt(uv_tl.y);
    const sw: f32 = @as(f32, @floatFromInt(uv_br.x)) - sx;
    const sh: f32 = @as(f32, @floatFromInt(uv_br.y)) - sy;

    const sx_inc: f32 = sw / @as(f32, @floatFromInt(dw));
    const sy_inc: f32 = sh / @as(f32, @floatFromInt(dh));

    // Clip to screen
    if (dx < 0) {
        sx += sx_inc * -dxf;
        dw += dx;
        dx = 0;
    }
    if (dx + dw >= screen_size.x) {
        dw = screen_size.x - dx;
    }
    if (dy < 0) {
        sy += sy_inc * -dyf;
        dh += dy;
        dy = 0;
    }
    if (dy + dh >= screen_size.y) {
        dh = screen_size.y - dy;
    }

    // FIXME: There's probably an underflow in the source data when
    // sx_inc or sy_inc is negative?!
    var di: usize = @intCast(dy * screen_ppr + dx);
    for (0..@intCast(dh)) |y| {
        // fudge source index by 0.001 pixels to avoid rounding errors :/
        var si: f32 = @floor(sy + @as(f32, @floatFromInt(y)) * sy_inc) * @as(f32, @floatFromInt(src_size.x)) + sx + 0.001;
        for (0..@intCast(dw)) |_| {
            if (@as(usize, @intFromFloat(si)) < src_px.len) {
                screen_buffer[di] = screen_buffer[di].blend(src_px[@intFromFloat(si)].mix(color));
            }
            si += sx_inc;
            di += 1;
        }
        di += @intCast(screen_ppr - dw);
    }
}

/// Push the transform stack
pub fn push() void {
    assert(transform_stack_index < options.options.RENDER_TRANSFORM_STACK_SIZE - 1); // Max transform stack size RENDER_TRANSFORM_STACK_SIZE reached"
    transform_stack[transform_stack_index + 1] = transform_stack[transform_stack_index];
    transform_stack_index += 1;
}

/// Pop the transform stack
pub fn pop() void {
    assert(transform_stack_index != 0); // Cannot pop from empty transform stack
    transform_stack_index -= 1;
}

/// Translate; can only be called if stack was pushed at least once
pub fn translate(t: Vec2) void {
    assert(transform_stack_index != 0); // Cannot translate initial transform. render.push() first.
    const t2 = t.mulf(screen_scale);
    transform_stack[transform_stack_index].translate(t2);
}

/// Scale; can only be called if stack was pushed at least once
pub fn scale(s: Vec2) void {
    assert(transform_stack_index != 0); // Cannot scale initial transform. render.push() first.
    transform_stack[transform_stack_index].scale(s);
}

/// Rotate; can only be called if stack was pushed at least once
pub fn rotate(rotation: f32) void {
    assert(transform_stack_index != 0); // Cannot rotate initial transform. render.push() first.
    transform_stack[transform_stack_index].rotate(rotation);
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
pub fn resize(available_size: Vec2i) void {
    // Determine Zoom
    if (options.options.RENDER_SCALE_MODE == options.RENDER_SCALE_NONE) {
        screen_scale = 1;
    } else {
        screen_scale = @min(
            @as(f32, @floatFromInt(available_size.x)) / @as(f32, @floatFromInt(options.options.RENDER_SIZE.x)),
            @as(f32, @floatFromInt(available_size.y)) / @as(f32, @floatFromInt(options.options.RENDER_SIZE.y)),
        );

        if (options.options.RENDER_SCALE_MODE == options.RENDER_SCALE_DISCRETE) {
            screen_scale = @max(@floor(screen_scale), 0.5);
        }
    }

    // Determine size
    if ((options.options.RENDER_RESIZE_MODE & options.RENDER_RESIZE_WIDTH) != 0) {
        screen_size.x = @max(available_size.x, options.options.RENDER_SIZE.x);
    } else {
        screen_size.x = @as(i32, @intCast(options.options.RENDER_SIZE.x)) * @as(i32, @intFromFloat(screen_scale));
    }

    if ((options.options.RENDER_RESIZE_MODE & options.RENDER_RESIZE_HEIGHT) != 0) {
        screen_size.y = @max(available_size.y, options.options.RENDER_SIZE.y);
    } else {
        screen_size.y = @as(i32, @intCast(options.options.RENDER_SIZE.y)) * @as(i32, @intFromFloat(screen_scale));
    }

    logical_size.x = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.x)) / screen_scale));
    logical_size.y = @intFromFloat(@ceil(@as(f32, @floatFromInt(screen_size.y)) / screen_scale));
    inv_screen_scale = 1.0 / screen_scale;
    backbuffer_size = screen_size;
    window_size = available_size;
}

pub fn setBlendMode(new_mode: BlendMode) void {
    if (new_mode == blend_mode)
        return;

    blend_mode = new_mode;
}

pub fn initTexture(size: Vec2i, pixels: []const Rgba) Texture {
    assert(texture.textures_len < options.options.RENDER_TEXTURES_MAX);

    textures[texture.textures_len].size = size;
    textures[texture.textures_len].pixels = alloc.bumpAlloc(Rgba, @intCast(size.x * size.y)) catch @panic("failed to alloc");
    @memcpy(textures[texture.textures_len].pixels, pixels);

    const texture_handle = .{ .index = texture.textures_len };
    texture.textures_len += 1;
    return texture_handle;
}

pub fn platform_prepare_frame() void {
    if (screen_size.x != screenbuffer_size.x or screen_size.y != screenbuffer_size.y) {
        if (screenbuffer != null) {
            sdl.SDL_DestroyTexture(screenbuffer);
        }
        screenbuffer = sdl.SDL_CreateTexture(platform.renderer, sdl.SDL_PIXELFORMAT_ABGR8888, sdl.SDL_TEXTUREACCESS_STREAMING, screen_size.x, screen_size.y);
        screenbuffer_size = screen_size;
    }
    var buffer: *u8 = undefined;
    _ = sdl.SDL_LockTexture(screenbuffer, null, @ptrCast(&buffer), &screen_pitch);
    const ptr: [*]align(1) Rgba = @ptrCast(buffer);
    screen_buffer = ptr[0..@intCast(screen_size.y * screen_size.x)];
}

pub fn platform_end_frame() void {
    screen_buffer = undefined;
    sdl.SDL_UnlockTexture(screenbuffer);
    const dx_screen: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(window_size.x - backbuffer_size.x)) / 2.0));
    const dy_screen: i32 = @as(i32, @intFromFloat(@as(f32, @floatFromInt(window_size.y - backbuffer_size.y)) / 2.0));
    const dst_rect: sdl.SDL_Rect = .{
        .x = dx_screen,
        .y = dy_screen,
        .w = backbuffer_size.x,
        .h = backbuffer_size.y,
    };
    _ = sdl.SDL_RenderClear(platform.renderer);
    _ = sdl.SDL_RenderCopy(platform.renderer, screenbuffer, null, &dst_rect);
    _ = sdl.SDL_RenderPresent(platform.renderer);
}
