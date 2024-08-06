const std = @import("std");
const assert = std.debug.assert;
const types = @import("types.zig");
const Rgba = types.Rgba;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const Texture = @import("texture.zig").Texture;
const qoi = @import("qoi.zig");
const BumpAllocator = @import("allocator.zig").BumpAllocator;
const bumpAlloc = @import("allocator.zig").bumpAlloc;
const render = @import("render.zig");

const IMAGE_MAX_SOURCES = 1024;
var image_paths: [IMAGE_MAX_SOURCES][]u8 = undefined;
var images: [IMAGE_MAX_SOURCES]Image = undefined;
var images_len: usize = 0;

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

        image_paths[images_len] = try bumpAlloc(path.len);
        @memcpy(image_paths[images_len], path);

        var file = try std.fs.cwd().openFile(path, .{});
        defer file.close();

        var bump_alloc = BumpAllocator{};
        const reader = file.reader();
        const file_size = (try file.stat()).size;
        const buf = try bump_alloc.allocator().alloc(u8, file_size);
        _ = try reader.readAll(buf);
        // TODO defer temp.free(data);

        var image = try qoi.decodeBuffer(bump_alloc.allocator(), buf);
        defer image.deinit(bump_alloc.allocator());

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
};
