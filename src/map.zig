const std = @import("std");
const assert = std.debug.assert;
const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const fromVec2 = types.fromVec2;
const img = @import("image.zig");
const alloc = @import("allocator.zig");
const engine = @import("engine.zig");
const render = @import("render.zig");
const ObjectMap = std.json.ObjectMap;
const Array = std.json.Array;
const Value = std.json.Value;

const MapAnimDef = struct {
    inv_frame_time: f32 = 0.0,
    sequence: []const u16 = &[0]u16{},
};

pub const Map = struct {
    // The size of the map in tiles
    size: Vec2i,

    // The size of a tile of this map
    tile_size: u16,

    // The name of the map. For collision maps this is usually "collision".
    // Background maps may have any name.
    name: [16]u8,

    // The "distance" of the map when drawing at a certain offset. Maps that
    // have a higher distance move slower. Default 1.
    distance: f32,

    // Whether the map repeats indefinitely when drawing
    repeat: bool,

    // Whether to draw this map in fround of all entities
    foreground: bool,

    // The tileset image to use when drawing. Might be NULL for collision maps
    tileset: img.Image,

    // Animations for certain tiles when drawing. Use map_set_anim() to add
    // animations.
    anims: ?[]?*MapAnimDef = null,

    // The tile indices with a length of size.x * size.y
    data: []u16,

    // The highest tile index in that map; used internally.
    max_tile: u16,

    /// Load a map from a json. The json must have the following layout.
    /// Note that tile indices have a bias of +1. I.e. index 0 will not draw anything
    /// and represent a blank tile. Index 1 will draw the 0th tile from the tileset.
    /// {
    /// 	"name": "background",
    /// 	"width": 4,
    /// 	"height": 2,
    /// 	"tilesetName": "assets/tiles/biolab.qoi",
    /// 	"repeat": true,
    /// 	"distance": 1.0,
    /// 	"tilesize": 8,
    /// 	"foreground": false,
    /// 	"data": [
    /// 		[0,1,2,3],
    /// 		[3,2,1,0],
    /// 	]
    /// }
    pub fn initFromJson(str: []const u8) Map {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const parsed = std.json.parseFromSlice(Value, gpa.allocator(), str, .{}) catch @panic("error when parsing map");
        const root = parsed.value;

        // TODO: assert(!engine.isRunning());

        var map: Map = undefined;
        map.anims = null;
        map.size = vec2i(getInt(i32, root.object, "width"), getInt(i32, root.object, "height"));
        map.tile_size = getInt(u16, root.object, "tilesize");
        map.distance = getFloat(root.object, "distance");
        map.foreground = root.object.get("foreground").?.bool;
        assert(map.distance != 0); // invalid distance for map
        map.repeat = root.object.get("repeat").?.bool;

        std.log.info("map_size: {}, map.tile_size: {}, map.distance: {}", .{ map.size, map.tile_size, map.distance });

        switch (root.object.get("name").?) {
            .string => |name| @memcpy(map.name[0..name.len], name),
            else => unreachable,
        }
        switch (root.object.get("tilesetName").?) {
            .string => |tileset_name| {
                std.log.info("loaded map {} {} {s}\n", .{ map.size.x, map.size.y, tileset_name });
                map.tileset = img.Image.init(tileset_name) catch @panic("error when parsing map");
            },
            else => unreachable,
        }

        switch (root.object.get("data").?) {
            .array => |data| {
                assert(data.items.len == map.size.y); // Map data height is %d expected %d", data.len, map.size.y
                map.data = gpa.allocator().alloc(u16, @intCast(map.size.x * map.size.y)) catch @panic("error when allocating data map");
                var index: usize = 0;
                for (data.items) |row| {
                    for (row.array.items) |r| {
                        map.data[index] = @intCast(r.integer);
                        map.max_tile = @max(map.max_tile, map.data[index]);
                        index += 1;
                    }
                }
            },
            else => unreachable,
        }

        return map;
    }

    /// Draw the map at the given offset. This will take the distance into account.
    pub fn draw(self: Map, off: Vec2) void {
        // assert(self.tileset); // "Cannot draw map without tileset");

        const offset = off.divf(self.distance);
        const rs = render.renderSize();
        const ts = self.tile_size;

        if (self.repeat) {
            const tile_offset = types.fromVec2(offset).divi(ts);
            const px_offset = vec2(@mod(offset.x, @as(f32, @floatFromInt(ts))), @mod(offset.y, @as(f32, @floatFromInt(ts))));
            const px_min = vec2(-px_offset.x - @as(f32, @floatFromInt(ts)), -px_offset.y - @as(f32, @floatFromInt(ts)));
            const px_max = vec2(-px_offset.x + @as(f32, @floatFromInt(rs.x)) + @as(f32, @floatFromInt(ts)), -px_offset.y + @as(f32, @floatFromInt(rs.y)) + @as(f32, @floatFromInt(ts)));

            var pos = px_min;
            var self_y: i32 = -1;
            while (pos.y < px_max.y) {
                const y = @mod(@mod((self_y + tile_offset.y), self.size.y) + self.size.y, self.size.y);

                pos.x = px_min.x;
                var self_x: i32 = -1;
                while (pos.x < px_max.x) {
                    const x = @mod(@mod((self_x + tile_offset.x), self.size.x) + self.size.x, self.size.x);

                    const tile = self.data[@intCast(y * self.size.x + x)];

                    if (tile > 0) {
                        self.drawTile(tile - 1, pos);
                    }
                    self_x += 1;
                    pos.x += @floatFromInt(ts);
                }
                self_y += 1;
                pos.y += @floatFromInt(ts);
            }
        } else {
            const tile_min = vec2i(@max(0, @divFloor(@as(i32, @intFromFloat(offset.x)), ts)), @max(0, @divFloor(@as(i32, @intFromFloat(offset.y)), ts)));
            const tile_max = vec2i(
                @min(self.size.x, @divFloor(@as(i32, @intFromFloat(offset.x)) + rs.x + ts, ts)),
                @min(self.size.y, @divFloor(@as(i32, @intFromFloat(offset.y)) + rs.y + ts, ts)),
            );

            var y = tile_min.y;
            while (y < tile_max.y) {
                var x = tile_min.x;
                while (x < tile_max.x) {
                    const tile = self.data[@intCast(y * self.size.x + x)];
                    if (tile > 0) {
                        const pos = vec2(@floatFromInt(x * ts), @floatFromInt(y * ts)).sub(offset);
                        self.drawTile(tile - 1, pos);
                    }
                    x += 1;
                }
                y += 1;
            }
        }
    }

    /// Set the frame time and animation sequence for a particular tile. You can
    /// only do this in your scene_init()
    pub fn setAnim(self: *Map, tile: u16, frame_time: f32, sequence: []const u16) void {
        // assert(!engine.isRunning()); // Cannot set map animation during gameplay
        assert(sequence.len > 0); // Map animation has empty sequence

        if (tile > self.max_tile) {
            return;
        }
        // TODO: var ba = alloc.BumpAllocator{};
        var ba = std.heap.GeneralPurposeAllocator(.{}){};
        if (self.anims == null) {
            const anims = ba.allocator().alloc(?*MapAnimDef, self.max_tile) catch @panic("error when setting map animation");
            @memset(anims, null);
            self.anims = anims;
        }

        var def_addr: []MapAnimDef = ba.allocator().alloc(MapAnimDef, 1) catch @panic("error when setting map animation");
        def_addr[0] = MapAnimDef{
            .inv_frame_time = 1.0 / frame_time,
            .sequence = ba.allocator().dupe(u16, sequence) catch @panic("error when setting map animation"),
        };
        self.anims.?[tile] = &def_addr[0];
    }

    /// Return the tile index at the tile position. Will return 0 when out of bounds
    pub fn tileAt(self: Map, tile_pos: Vec2i) i32 {
        if (tile_pos.x < 0 or tile_pos.x >= self.size.x or tile_pos.y < 0 or tile_pos.y >= self.size.y) {
            return 0;
        }
        return self.data[tile_pos.y * self.size.x + tile_pos.x];
    }

    /// Return the tile index at the pixel position. Will return 0 when out of bounds
    pub fn tileAtPx(self: Map, px_pos: Vec2) i32 {
        const tile_pos = fromVec2(px_pos).divi(self.tile_size);
        return self.tileAt(tile_pos);
    }

    fn drawTile(self: Map, t: u16, pos: Vec2) void {
        var tile = t;
        if (self.anims) |anims| {
            if (anims[tile]) |def| {
                const frame = @as(usize, @intFromFloat(engine.time * def.inv_frame_time)) % def.sequence.len;
                tile = def.sequence[frame];
            }
        }

        self.tileset.drawTile(tile, vec2i(self.tile_size, self.tile_size), pos);
    }

    fn getInt(comptime T: type, obj: ObjectMap, name: []const u8) T {
        return @as(T, @intCast(obj.get(name).?.integer));
    }

    fn getFloat(obj: ObjectMap, name: []const u8) f32 {
        return switch (obj.get(name).?) {
            .float => @floatCast(obj.get(name).?.float),
            .integer => @floatFromInt(obj.get(name).?.integer),
            else => unreachable,
        };
    }
};
