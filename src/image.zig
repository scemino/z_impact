const std = @import("std");
const assert = std.debug.assert;
const types = @import("types.zig");
const Rgba = types.Rgba;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const Texture = @import("texture.zig").Texture;
const qoi = @import("qoi.zig");
const BumpAllocator = @import("allocator.zig").BumpAllocator;
const TempAllocator = @import("allocator.zig").TempAllocator;
const bumpAlloc = @import("allocator.zig").bumpAlloc;
const render = @import("render.zig");

const IMAGE_MAX_SOURCES = 1024;
var image_paths: [IMAGE_MAX_SOURCES][]u8 = undefined;
var images: [IMAGE_MAX_SOURCES]Image = undefined;
var images_len: usize = 0;

pub const ImageMark = struct { index: usize = 0 };

pub const Image = struct {
    size: Vec2i,
    texture: Texture,

    /// Load an image from a QOI file. Calling this function multiple times with the
    /// same path will return the same, cached image instance,
    pub fn init(path: []const u8) !Image {
        for (0..images_len) |i| {
            if (std.mem.eql(u8, path, image_paths[i])) {
                return images[i];
            }
        }

        assert(images_len < IMAGE_MAX_SOURCES);
        // TODO: assert !engine_is_running()

        image_paths[images_len] = try bumpAlloc(u8, path.len);
        @memcpy(image_paths[images_len], path);

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var temp_alloc = TempAllocator{};
        const reader = file.reader();
        const file_size = (try file.stat()).size;
        const buf = try temp_alloc.allocator().alloc(u8, file_size);
        _ = try reader.readAll(buf);
        defer temp_alloc.allocator().free(buf);

        var image = try qoi.decodeBuffer(temp_alloc.allocator(), buf);
        defer image.deinit(temp_alloc.allocator());

        const size = Vec2i{ .x = @intCast(image.width), .y = @intCast(image.height) };
        const image_pixels = std.mem.sliceAsBytes(image.pixels);
        const texture_pixels = std.mem.bytesAsSlice(Rgba, image_pixels);
        const texture = Texture.init(size, texture_pixels);

        images[images_len] = .{ .size = size, .texture = texture };
        images_len += 1;
        return images[images_len - 1];
    }

    pub fn draw(self: Image, pos: Vec2) void {
        const size = types.fromVec2i(self.size);
        render.draw(pos, size, self.texture, .{ .x = 0, .y = 0 }, size, types.white());
    }

    pub fn drawEx(self: Image, src_pos: Vec2, src_size: Vec2, dst_pos: Vec2, dst_size: Vec2, color: Rgba) void {
        render.draw(dst_pos, dst_size, self.texture, src_pos, src_size, color);
    }

    pub fn drawTile(self: Image, tile: i32, tile_size: Vec2i, dst_pos: Vec2) void {
        self.drawTileEx(tile, tile_size, dst_pos, false, false, types.white());
    }

    pub fn drawTileEx(self: Image, tile: i32, tile_size: Vec2i, dst_pos: Vec2, flip_x: bool, flip_y: bool, color: Rgba) void {
        assert(self.size.x > 0);
        var src_pos = types.vec2(
            @floatFromInt(@mod(tile * tile_size.x, self.size.x)),
            @as(f32, @floatFromInt(@divFloor(tile * tile_size.x, self.size.x))) * @as(f32, @floatFromInt(tile_size.y)),
        );
        var src_size = types.fromVec2i(types.vec2i(tile_size.x, tile_size.y));
        const dst_size = src_size;

        if (flip_x) {
            src_pos.x = src_pos.x + @as(f32, @floatFromInt(tile_size.x));
            src_size.x = @as(f32, @floatFromInt(-tile_size.x));
        }
        if (flip_y) {
            src_pos.y = src_pos.y + @as(f32, @floatFromInt(tile_size.y));
            src_size.y = @as(f32, @floatFromInt(-tile_size.y));
        }
        // std.log.info("tile: {}, src_pos: {}", .{ tile, src_pos });
        render.draw(dst_pos, dst_size, self.texture, src_pos, src_size, color);
    }
};

pub fn imagesMark() ImageMark {
    return .{ .index = images_len };
}

pub fn imagesReset(mark: ImageMark) void {
    images_len = mark.index;
}
