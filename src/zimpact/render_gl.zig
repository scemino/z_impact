const std = @import("std");
const assert = std.debug.assert;
const Rgba = types.Rgba;
pub const cmn = @import("common");
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
const Mat3 = types.Mat3;
const options = cmn.opt;
const shd = cmn.shd;
const gl = @import("gl3v3.zig");

const InternalTexture = struct {
    size: Vec2i,
    id: gl.GLuint,
};

var textures: [options.options.RENDER_TEXTURES_MAX]InternalTexture = undefined;

var logical_size: Vec2i = undefined;
var screen_scale: f32 = 0.0;
var draw_calls: usize = 0;
var inv_screen_scale: f32 = 1.0;
var screen_size: Vec2i = undefined;

pub var NO_TEXTURE: Texture = undefined;
var blend_mode: BlendMode = .normal;
var backbuffer_size: Vec2i = undefined;
var window_size: Vec2i = undefined;

var vbo_quads: gl.GLuint = undefined;
var vbo_indices: gl.GLuint = undefined;
var backbuffer: gl.GLuint = 0;
var backbuffer_texture: gl.GLuint = 0;

var transform_stack: [options.options.RENDER_TRANSFORM_STACK_SIZE]Mat3 = undefined;
var transform_stack_index: usize = 0;

var quad_buffer: [options.options.RENDER_BUFFER_CAPACITY * 4]Vertex = undefined;
var index_buffer: [options.options.RENDER_BUFFER_CAPACITY * 6]u16 = undefined;
var tex_buffer: [options.options.RENDER_BUFFER_CAPACITY]gl.GLuint = [1]gl.GLuint{0} ** options.options.RENDER_BUFFER_CAPACITY;
var quad_buffer_len: usize = 0;
var tex_buffer_len: usize = 0;
var prg_game: *PrgGame = undefined;

pub const BlendMode = enum { normal, lighter };

const PrgGame = struct {
    program: gl.GLuint,
    vao: gl.GLuint,
    uniform: struct {
        screen: gl.GLint,
        time: gl.GLuint,
    },
    attribute: struct {
        pos: gl.GLint,
        uv: gl.GLint,
        color: gl.GLint,
    },
};

fn compileShader(shader_type: gl.GLenum, source: [*c]const u8) gl.GLuint {
    const shader = gl.createShader(shader_type);
    gl.shaderSource(shader, 1, &source, null);
    gl.compileShader(shader);

    var success: gl.GLint = undefined;
    gl.getShaderiv(shader, gl.COMPILE_STATUS, &success);
    if (success == 0) {
        var log_written: c_int = undefined;
        var log: [256:0]u8 = undefined;
        gl.getShaderInfoLog(shader, 256, &log_written, log[0..]);
        var logMsgBuf: [4 * 256]u8 = undefined;
        const logMsg = std.fmt.bufPrint(&logMsgBuf, "Error compiling shader: {s}\nwith source:\n{s}", .{ log, source }) catch @panic("Failed to compile shader");
        @panic(logMsg);
    }
    return shader;
}

fn createProgram(vs_source: [*c]const u8, fs_source: [*c]const u8) gl.GLuint {
    const vs = compileShader(gl.VERTEX_SHADER, vs_source);
    const fs = compileShader(gl.FRAGMENT_SHADER, fs_source);

    const program = gl.createProgram();
    gl.attachShader(program, vs);
    gl.attachShader(program, fs);
    gl.linkProgram(program);
    gl.useProgram(program);
    return program;
}

inline fn bind_va_f(index: gl.GLuint, TContainer: type, member: []const u8, start: gl.GLsizei) void {
    var field_size: usize = 0;
    inline for (@typeInfo(TContainer).Struct.fields) |field| {
        if (std.mem.eql(u8, field.name, member)) {
            field_size = @sizeOf(field.type);
            break;
        }
    }

    gl.vertexAttribPointer(
        index,
        @intCast(field_size / 4),
        gl.FLOAT,
        gl.FALSE,
        @sizeOf(TContainer),
        @ptrFromInt(@offsetOf(TContainer, member) + start),
    );
}

inline fn bind_va_color(index: gl.GLuint, TContainer: type, member: []const u8, start: gl.GLsizei) void {
    gl.vertexAttribPointer(
        index,
        4,
        gl.UNSIGNED_BYTE,
        gl.TRUE,
        @sizeOf(TContainer),
        @ptrFromInt(@offsetOf(TContainer, member) + start),
    );
}

fn shaderGameInit() *PrgGame {
    var s = alloc.bumpCreate(PrgGame) catch @panic("Failed to create game shader");

    s.program = createProgram(@embedFile("shader_vs.glsl"), @embedFile("shader_fs.glsl"));
    s.uniform.screen = gl.getUniformLocation(s.program, "screen");

    s.attribute.pos = gl.getAttribLocation(s.program, "pos");
    s.attribute.uv = gl.getAttribLocation(s.program, "uv");
    s.attribute.color = gl.getAttribLocation(s.program, "color");

    gl.enableVertexAttribArray(@bitCast(s.attribute.pos));
    bind_va_f(@bitCast(s.attribute.pos), Vertex, "pos", 0);

    gl.enableVertexAttribArray(@bitCast(s.attribute.uv));
    bind_va_f(@bitCast(s.attribute.uv), Vertex, "uv", 0);

    gl.enableVertexAttribArray(@bitCast(s.attribute.color));
    bind_va_color(@bitCast(s.attribute.color), Vertex, "color", 0);

    return s;
}

fn useProgram(shader: *PrgGame) void {
    gl.useProgram(shader.program);
}

/// A renderer is responsible for drawing on the screen. Images, Fonts and
/// Animations ulitmately use the render_* functions to be drawn.
/// Different renderer backends can be implemented by supporting just a handful
/// of functions.
///
/// Called by the platform
pub fn init() void {
    // Quad buffer
    gl.genBuffers(1, &vbo_quads);
    gl.bindBuffer(gl.ARRAY_BUFFER, vbo_quads);

    var i: u16 = 0;
    var j: u16 = 0;
    while (i < options.options.RENDER_BUFFER_CAPACITY) : (i += 6) {
        index_buffer[i + 0] = j + 3;
        index_buffer[i + 1] = j + 1;
        index_buffer[i + 2] = j + 0;
        index_buffer[i + 3] = j + 3;
        index_buffer[i + 4] = j + 2;
        index_buffer[i + 5] = j + 1;
        j += 4;
    }
    // Index buffer
    gl.genBuffers(1, &vbo_indices);
    gl.bindBuffer(gl.ELEMENT_ARRAY_BUFFER, vbo_indices);
    gl.bufferData(gl.ELEMENT_ARRAY_BUFFER, @sizeOf(@TypeOf(index_buffer)), @ptrCast(&index_buffer[0]), gl.STATIC_DRAW);

    // Game shader
    prg_game = shaderGameInit();

    // gl.enable(gl.CULL_FACE);
    gl.enable(gl.BLEND);
    gl.blendFunc(gl.SRC_ALPHA, gl.ONE_MINUS_SRC_ALPHA);

    // Create white texture
    const white_pixels = [1]Rgba{types.white()} ** 4;
    NO_TEXTURE = initTexture(vec2i(2, 2), &white_pixels);
}

/// Called by the engine
pub fn cleanup() void {}

/// Called by the engine
pub fn framePrepare() void {
    const dx: gl.GLint = @intFromFloat(@as(f32, @floatFromInt(window_size.x - backbuffer_size.x)) / 2.0);
    const dy: gl.GLint = @intFromFloat(@as(f32, @floatFromInt(window_size.y - backbuffer_size.y)) / 2.0);

    gl.viewport(dx, dy, backbuffer_size.x, backbuffer_size.y);
    gl.uniform2f(prg_game.uniform.screen, @as(f32, @floatFromInt(backbuffer_size.x)), @as(f32, @floatFromInt(backbuffer_size.y)));
    gl.clearColor(0, 0, 0, 1);
    gl.clear(gl.COLOR_BUFFER_BIT | gl.DEPTH_BUFFER_BIT);
    gl.disable(gl.DEPTH_TEST);
}

/// Called by the engine
pub fn frameEnd() void {
    flush();
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

    const t = textures[texture_handle.index];
    var q = quad;
    q.vertices[0].uv = q.vertices[0].uv.div(types.fromVec2i(t.size));
    q.vertices[1].uv = q.vertices[1].uv.div(types.fromVec2i(t.size));
    q.vertices[2].uv = q.vertices[2].uv.div(types.fromVec2i(t.size));
    q.vertices[3].uv = q.vertices[3].uv.div(types.fromVec2i(t.size));

    tex_buffer[tex_buffer_len] = t.id;
    tex_buffer_len += 1;

    // zig fmt: off
    quad_buffer[quad_buffer_len] = q.vertices[0]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[1]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[2]; quad_buffer_len += 1;
    quad_buffer[quad_buffer_len] = q.vertices[3]; quad_buffer_len += 1;
    // zig fmt: on
}

fn flush() void {
    if (quad_buffer_len == 0)
        return;

    gl.bufferData(gl.ARRAY_BUFFER, @intCast(quad_buffer_len * @sizeOf(Vertex)), @ptrCast(&quad_buffer[0]), gl.STREAM_DRAW);

    gl.bindTexture(gl.TEXTURE_2D, tex_buffer[0]);
    // gl.drawElements(gl.TRIANGLES, @intCast(6 * quad_buffer_len / 4), gl.UNSIGNED_SHORT, @ptrFromInt(0));
    var i: usize = 0;
    var j: usize = 0;
    while (i < tex_buffer_len) : (i += 1) {
        gl.bindTexture(gl.TEXTURE_2D, tex_buffer[i]);
        gl.drawElements(gl.TRIANGLES, 6, gl.UNSIGNED_SHORT, @ptrFromInt(j * @sizeOf(u16)));
        j += 6;
    }

    quad_buffer_len = 0;
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
}

pub fn initTexture(size: Vec2i, pixels: []const Rgba) Texture {
    var id: gl.GLuint = undefined;
    gl.genTextures(1, &id);
    gl.bindTexture(gl.TEXTURE_2D, id);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.LINEAR);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
    gl.texParameteri(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
    gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, size.x, size.y, 0, gl.RGBA, gl.UNSIGNED_BYTE, @ptrCast(pixels.ptr));

    assert(texture.textures_len < options.options.RENDER_TEXTURES_MAX);
    textures[texture.textures_len] = .{ .size = size, .id = id };

    const texture_handle = Texture{
        .index = texture.textures_len,
    };
    texture.textures_len += 1;
    return texture_handle;
}
