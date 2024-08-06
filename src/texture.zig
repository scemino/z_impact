const std = @import("std");
const assert = std.debug.assert;
const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const Rgba = types.Rgba;
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

const RENDER_TEXTURES_MAX = 1024;

const Vertex = struct {
    pos: Vec2,
    uv: Vec2,
    color: Rgba,
};

const Quad = struct {
    vertices: [4]Vertex,
};

var sampler: sg.Sampler = undefined;

pub const Texture = struct {
    index: u32,

    pub fn init(size: Vec2i, pixels: []const Rgba) Texture {
        const img = sg.makeImage(.{
            .width = size.x,
            .height = size.y,
            .pixel_format = .RGBA8,
            .usage = .STREAM,
        });
        sampler = sg.makeSampler(.{
            .min_filter = .LINEAR,
            .mag_filter = .LINEAR,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
        var img_data = sg.ImageData{};
        img_data.subimage[0][0] = sg.asRange(pixels);
        sg.updateImage(img, img_data);

        assert(textures_len < RENDER_TEXTURES_MAX);
        textures[textures_len] = .{ .size = size, .img = img };

        const texture_handle = Texture{
            .index = textures_len,
        };
        textures_len += 1;
        return texture_handle;
    }
};

var textures_len: u32 = 0;
const InternalTexture = struct {
    size: Vec2i,
    img: sg.Image,
};

var textures: [RENDER_TEXTURES_MAX]InternalTexture = undefined;

pub fn drawQuad(quad: Quad, texture_handle: Texture) void {
    const t = &textures[texture_handle.index];
    sgl.enableTexture();
    sgl.texture(t.img, sampler);
    sgl.beginQuads();
    for (quad.vertices) |v| {
        sgl.v2fT2fC4b(
            v.pos.x,
            v.pos.y,
            v.uv.x / @as(f32, @floatFromInt(t.size.x)),
            1.0 - v.uv.y / @as(f32, @floatFromInt(t.size.y)),
            v.color.components[0],
            v.color.components[1],
            v.color.components[2],
            v.color.components[3],
        );
    }
    sgl.end();
}
