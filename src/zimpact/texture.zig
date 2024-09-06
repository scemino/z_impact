const std = @import("std");
const assert = std.debug.assert;
const options = @import("options.zig").options;
const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const Rgba = types.Rgba;
const sokol = @import("sokol");
const sg = sokol.gfx;

pub const TextureMark = struct { index: usize = 0 };

pub const Vertex = struct {
    pos: Vec2,
    uv: Vec2,
    color: Rgba,
};

pub const Quad = struct {
    vertices: [4]Vertex,
};

pub const Texture = struct {
    index: usize,
};

pub var textures_len: usize = 0;

pub fn texturesMark() TextureMark {
    return .{ .index = textures_len };
}

pub fn texturesReset(mark: TextureMark) void {
    assert(mark.index <= textures_len);
    textures_len = mark.index;
}
