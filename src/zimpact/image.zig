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
const ziengine = @import("engine.zig");
const options = @import("options.zig").options;

var image_paths: [options.IMAGE_MAX_SOURCES][]u8 = undefined;
var images: [options.IMAGE_MAX_SOURCES]Image = undefined;
var images_len: usize = 0;

/// Called by the engine to manage image memory
pub const ImageMark = struct { index: usize = 0 };

/// Images can be loaded from QOI files or directly created with an array of
/// rgba_t pixels. If an image at a certain path is already loaded, calling
/// image() with that same path, will return the same image.
/// Images can be drawn to the screen in full, just parts of it, or as a "tile"
/// from it.
pub const Image = struct {
    size: Vec2i,
    texture: Texture,

    /// Load an image from a QOI file. Calling this function multiple times with the
    /// same path will return the same, cached image instance,
    pub fn init(path: []const u8) !*Image {
        for (0..images_len) |i| {
            if (std.mem.eql(u8, path, image_paths[i])) {
                return &images[i];
            }
        }

        assert(images_len < options.IMAGE_MAX_SOURCES);
        assert(!ziengine.is_running);

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

        var img = try qoi.decodeBuffer(temp_alloc.allocator(), buf);
        defer img.deinit(temp_alloc.allocator());

        const size = Vec2i{ .x = @intCast(img.width), .y = @intCast(img.height) };
        const image_pixels = std.mem.sliceAsBytes(img.pixels);
        const texture_pixels = std.mem.bytesAsSlice(Rgba, image_pixels);
        const texture = Texture.init(size, texture_pixels);

        images[images_len] = .{ .size = size, .texture = texture };
        images_len += 1;
        return &images[images_len - 1];
    }

    /// Draw the whole image at pos
    pub fn draw(self: Image, pos: Vec2) void {
        const size = types.fromVec2i(self.size);
        render.draw(pos, size, self.texture, .{ .x = 0, .y = 0 }, size, types.white());
    }

    /// Draw the src_pos, src_size rect of the image to dst_pos with dst_size and a tint color
    pub fn drawEx(self: Image, src_pos: Vec2, src_size: Vec2, dst_pos: Vec2, dst_size: Vec2, color: Rgba) void {
        render.draw(dst_pos, dst_size, self.texture, src_pos, src_size, color);
    }

    /// Draw a single tile from the image, as subdivided by tile_size
    pub fn drawTile(self: Image, tile: i32, tile_size: Vec2i, dst_pos: Vec2) void {
        self.drawTileEx(tile, tile_size, dst_pos, false, false, types.white());
    }

    /// Draw a single tile and specify x/y flipping and a tint color
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

/// Called by the engine to manage image memory
pub fn imagesMark() ImageMark {
    return .{ .index = images_len };
}

/// Called by the engine to manage image memory
pub fn imagesReset(mark: ImageMark) void {
    images_len = mark.index;
}

/// Load an image from a QOI file. Calling this function multiple times with the
/// same path will return the same, cached image instance,
pub fn image(path: []const u8) *Image {
    return Image.init(path) catch @panic("failed to init image");
}
