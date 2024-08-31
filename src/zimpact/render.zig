const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
const types = @import("types.zig");
const texture = @import("texture.zig");
const Texture = @import("texture.zig").Texture;
const Quad = @import("texture.zig").Quad;
const Vertex = @import("texture.zig").Vertex;
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const fromVec2i = types.fromVec2i;
const Mat3 = types.Mat3;
const sokol = @import("sokol");
const sapp = sokol.app;
const slog = sokol.log;
const sg = sokol.gfx;
const sglue = sokol.glue;
const options = @import("options.zig");
const shd = @import("shaders.zig");

var logical_size: Vec2i = undefined;
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;
var inv_screen_scale: f32 = 1.0;
var screen_size: Vec2i = undefined;

var pip_normal: sg.Pipeline = .{};
var pip_lighter: sg.Pipeline = .{};
var pip: sg.Pipeline = .{};
var pass_action: sg.PassAction = .{};
var bindings: sg.Bindings = undefined;
var shader: sg.Shader = .{};

pub var NO_TEXTURE: Texture = undefined;
var blend_mode: BlendMode = .normal;
var backbuffer_size: Vec2i = undefined;
var window_size: Vec2i = undefined;
var transform_stack: [options.options.RENDER_TRANSFORM_STACK_SIZE]Mat3 = undefined;
var transform_stack_index: usize = 0;

var quad_buffer: [options.options.RENDER_BUFFER_CAPACITY * 4]Vertex = undefined;
var index_buffer: [options.options.RENDER_BUFFER_CAPACITY * 6]u16 = undefined;
var tex_buffer: [options.options.RENDER_BUFFER_CAPACITY]sg.Image = undefined;
var quad_buffer_len: usize = 0;
var index_buffer_len: usize = 0;
var tex_buffer_len: usize = 0;

pub const BlendMode = enum { normal, lighter };

/// A renderer is responsible for drawing on the screen. Images, Fonts and
/// Animations ulitmately use the render_* functions to be drawn.
/// Different renderer backends can be implemented by supporting just a handful
/// of functions.
///
/// Called by the platform
pub fn init() void {
    logical_size = options.options.RENDER_SIZE;
    backbuffer_size = options.options.RENDER_SIZE;
    window_size = options.options.RENDER_SIZE;
    sg.setup(.{
        .environment = sglue.environment(),
        .logger = .{ .func = slog.func },
    });

    bindings.vertex_buffers[0] = sg.makeBuffer(.{
        .size = @sizeOf(Vertex) * options.options.RENDER_BUFFER_CAPACITY * 4,
        .usage = sg.Usage.STREAM,
        .label = "quad-vertices",
    });

    // create an index buffer for the cube
    bindings.index_buffer = sg.makeBuffer(.{
        .type = sg.BufferType.INDEXBUFFER,
        .size = @sizeOf(u16) * options.options.RENDER_BUFFER_CAPACITY * 6,
        .usage = sg.Usage.STREAM,
        .label = "quad-indices",
    });
    // create a sampler object with default attributes
    bindings.fs.samplers[shd.SLOT_smp] = sg.makeSampler(.{
        .min_filter = sg.Filter.LINEAR,
        .mag_filter = sg.Filter.NEAREST,
        .wrap_u = sg.Wrap.CLAMP_TO_EDGE,
        .wrap_v = sg.Wrap.CLAMP_TO_EDGE,
        .label = "quad-sampler",
    });

    shader = sg.makeShader(shd.sglShaderDesc(sg.queryBackend()));
    var desc: sg.PipelineDesc = .{
        .shader = sg.makeShader(shd.sglShaderDesc(sg.queryBackend())),
        .index_type = sg.IndexType.UINT16,
    };
    desc.layout.attrs[shd.ATTR_vs_position].format = sg.VertexFormat.FLOAT2;
    desc.layout.attrs[shd.ATTR_vs_texcoord0].format = sg.VertexFormat.FLOAT2;
    desc.layout.attrs[shd.ATTR_vs_color0].format = sg.VertexFormat.UBYTE4N;
    desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = sg.BlendFactor.SRC_ALPHA,
        .dst_factor_rgb = sg.BlendFactor.ONE_MINUS_SRC_ALPHA,
    };
    desc.label = "normal-pipeline";
    pip_normal = sg.makePipeline(desc);
    desc.colors[0].blend = .{
        .enabled = true,
        .src_factor_rgb = sg.BlendFactor.SRC_ALPHA,
        .dst_factor_rgb = .ONE,
    };
    desc.label = "lighter-pipeline";
    pip_lighter = sg.makePipeline(desc);
    pip = pip_normal;

    // default pass action
    pass_action.colors[0] = .{
        .load_action = sg.LoadAction.CLEAR,
        .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
    };

    const white_pixels = [1]Rgba{types.white()} ** 4;
    NO_TEXTURE = Texture.init(vec2i(2, 2), &white_pixels);
}

/// Called by the platform
pub fn cleanup() void {
    sg.shutdown();
}

pub fn framePrepare() void {}

pub fn frameEnd() void {
    const dw = @as(f32, @floatFromInt(backbuffer_size.x));
    const dh = @as(f32, @floatFromInt(backbuffer_size.y));
    const dx = @as(f32, @floatFromInt(window_size.x - backbuffer_size.x)) / 2.0;
    const dy = @as(f32, @floatFromInt(window_size.y - backbuffer_size.y)) / 2.0;
    const vs_params = shd.VsParams{
        .screen = [2]f32{ dw, dh },
    };

    sg.updateBuffer(bindings.vertex_buffers[0], sg.asRange(quad_buffer[0..quad_buffer_len]));
    sg.updateBuffer(bindings.index_buffer, sg.asRange(index_buffer[0..index_buffer_len]));

    sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
    sg.applyViewportf(dx, dy, dw, dh, true);
    sg.applyPipeline(pip);
    sg.applyUniforms(sg.ShaderStage.VS, shd.SLOT_vs_params, sg.asRange(&vs_params));
    flush();
    sg.endPass();
    sg.commit();
}

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
    if (quad_buffer_len >= quad_buffer.len) {
        unreachable;
    }

    const t = texture.textures[texture_handle.index];
    var q = quad;
    q.vertices[0].uv = q.vertices[0].uv.div(types.fromVec2i(t.size));
    q.vertices[1].uv = q.vertices[1].uv.div(types.fromVec2i(t.size));
    q.vertices[2].uv = q.vertices[2].uv.div(types.fromVec2i(t.size));
    q.vertices[3].uv = q.vertices[3].uv.div(types.fromVec2i(t.size));

    tex_buffer[tex_buffer_len] = t.img;
    tex_buffer_len += 1;

    // zig fmt: off
    quad_buffer[quad_buffer_len] = q.vertices[0]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[1]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[2]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[3]; quad_buffer_len += 1;
    // zig fmt: on

    const indices = [_]u16{
        0, 1, 2, 0, 2, 3,
    };
    for (0..6) |i| {
        index_buffer[index_buffer_len + i] = @as(u16, @intCast(quad_buffer_len - 4)) + indices[i];
    }
    index_buffer_len += 6;
}

fn flush() void {
    if (quad_buffer_len == 0)
        return;

    var i: usize = 0;
    var j: usize = 0;
    while (i < tex_buffer_len) : (i += 1) {
        bindings.fs.images[shd.SLOT_tex] = tex_buffer[i];
        sg.applyBindings(bindings);
        sg.draw(@intCast(j), 6, 1);
        j += 6;
    }
    quad_buffer_len = 0;
    index_buffer_len = 0;
    tex_buffer_len = 0;
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
    pip = if (blend_mode == .normal) pip_normal else pip_lighter;
}
