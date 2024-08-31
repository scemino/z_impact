const std = @import("std");
const assert = std.debug.assert;
const options = @import("options.zig").options;
const render = @import("render.zig");
const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const Rgba = types.Rgba;
const sokol = @import("sokol");
const sg = sokol.gfx;
const sgl = sokol.gl;

pub const TextureMark = struct { index: usize = 0 };

pub const Vertex = struct {
    pos: Vec2,
    uv: Vec2,
    color: Rgba,
};

pub const Quad = struct {
    vertices: [4]Vertex,
};

var sampler: sg.Sampler = undefined;

pub const Texture = struct {
    index: usize,

    pub fn init(size: Vec2i, pixels: []const Rgba) Texture {
        const img = sg.makeImage(.{
            .width = size.x,
            .height = size.y,
            .pixel_format = .RGBA8,
            .usage = .STREAM,
        });
        sampler = sg.makeSampler(.{
            .min_filter = .NEAREST,
            .mag_filter = .NEAREST,
            .wrap_u = .CLAMP_TO_EDGE,
            .wrap_v = .CLAMP_TO_EDGE,
        });
        var img_data = sg.ImageData{};
        img_data.subimage[0][0] = sg.asRange(pixels);
        sg.updateImage(img, img_data);

        assert(textures_len < options.RENDER_TEXTURES_MAX);
        textures[textures_len] = .{ .size = size, .img = img };

        const texture_handle = Texture{
            .index = textures_len,
        };
        textures_len += 1;
        return texture_handle;
    }
};

var textures_len: usize = 0;
const InternalTexture = struct {
    size: Vec2i,
    img: sg.Image,
};

pub var textures: [options.RENDER_TEXTURES_MAX]InternalTexture = undefined;

pub fn texturesMark() TextureMark {
    return .{ .index = textures_len };
}

pub fn texturesReset(mark: TextureMark) void {
    assert(mark.index <= textures_len);
    textures_len = mark.index;
}
