const std = @import("std");
const assert = std.debug.assert;
const cmn = @import("platform").cmn;
const alloc = cmn.alloc;
const types = cmn.types;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const fromVec2 = types.fromVec2;
const img = @import("image.zig");
const engine = @import("engine.zig");
const render = @import("platform").render;
const ObjectMap = std.json.ObjectMap;
const Array = std.json.Array;
const Value = std.json.Value;

const MapAnimDef = struct {
    inv_frame_time: f32 = 0.0,
    sequence: []const u16 = &[0]u16{},
};

pub const Map = struct {
    /// The size of the map in tiles
    size: Vec2i,

    /// The size of a tile of this map
    tile_size: u16,

    /// The name of the map. For collision maps this is usually "collision".
    /// Background maps may have any name.
    name: [16]u8 = [1]u8{0} ** 16,

    /// The "distance" of the map when drawing at a certain offset. Maps that
    /// have a higher distance move slower. Default 1.
    distance: f32 = 1.0,

    /// Whether the map repeats indefinitely when drawing
    repeat: bool = false,

    /// Whether to draw this map in fround of all entities
    foreground: bool = false,

    /// The tileset image to use when drawing. Might be `null` for collision maps
    tileset: ?*img.Image = null,

    /// Animations for certain tiles when drawing. Use `map.setAanim()` to add
    /// animations.
    anims: ?[]?*MapAnimDef = null,

    /// The tile indices with a length of `size.x * size.y`
    data: []u16,

    /// The highest tile index in that map; used internally.
    max_tile: u16 = 0,

    /// Load a map from a json. The json must have the following layout.
    /// Note that tile indices have a bias of +1. I.e. index 0 will not draw anything
    /// and represent a blank tile. Index 1 will draw the 0th tile from the tileset.
    /// ```json
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
    /// ```
    pub fn initFromJson(root: Value) *Map {
        assert(!engine.is_running);

        var ba = alloc.BumpAllocator{};
        var map: *Map = ba.allocator().create(Map) catch @panic("failed to allocate map");
        map.anims = null;
        map.size = vec2i(getInt(i32, root.object, "width"), getInt(i32, root.object, "height"));
        map.tile_size = getInt(u16, root.object, "tilesize");
        map.distance = getFloat(root.object, "distance");
        map.foreground = root.object.get("foreground").?.bool;
        assert(map.distance != 0); // invalid distance for map
        map.repeat = root.object.get("repeat").?.bool;

        // std.log.info("map_size: {}, map.tile_size: {}, map.distance: {}", .{ map.size, map.tile_size, map.distance });

        switch (root.object.get("name").?) {
            .string => |name| @memcpy(map.name[0..name.len], name),
            else => unreachable,
        }
        switch (root.object.get("tilesetName").?) {
            .string => |tileset_name| {
                std.log.info("loaded map {} {} {s}", .{ map.size.x, map.size.y, tileset_name });
                map.tileset = img.Image.init(tileset_name) catch @panic("error when parsing map");
            },
            .null => {},
            else => unreachable,
        }

        switch (root.object.get("data").?) {
            .array => |data| {
                assert(data.items.len == map.size.y); // Map data height is %d expected %d", data.len, map.size.y
                map.data = ba.allocator().alloc(u16, @intCast(map.size.x * map.size.y)) catch @panic("error when allocating data map");
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

    /// Create a map with the given data. If data is not null, it must be least
    /// `size.x * size.y` elements long. The data is _not_ copied. If data is `null`,
    /// an array of sufficent length will be allocated.
    pub fn initWithData(tile_size: u16, size: Vec2i, data: ?[]u16) Map {
        assert(!engine.is_running); // "Cannot create map during gameplay");

        var ba = alloc.BumpAllocator{};
        const map_data = if (data) |d| d else ba.allocator().alloc(u16, @intCast(size.x * size.y)) catch @panic("failed to alloc");
        @memset(map_data, 0);
        return .{
            .size = size,
            .tile_size = tile_size,
            .distance = 1,
            .data = map_data,
        };
    }

    /// Set the frame time and animation sequence for a particular tile. You can
    /// only do this in your scene_init()
    pub fn setAnim(self: *Map, tile: u16, frame_time: f32, sequence: []const u16) void {
        // assert(!engine.isRunning()); // Cannot set map animation during gameplay
        assert(sequence.len > 0); // Map animation has empty sequence

        if (tile > self.max_tile) {
            return;
        }
        var ba = alloc.BumpAllocator{};
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
        return self.data[@intCast(tile_pos.y * self.size.x + tile_pos.x)];
    }

    /// Return the tile index at the pixel position. Will return 0 when out of bounds
    pub fn tileAtPx(self: Map, px_pos: Vec2) i32 {
        const tile_pos = fromVec2(px_pos).divi(self.tile_size);
        return self.tileAt(tile_pos);
    }

    /// Draw the map at the given offset. This will take the distance into account.
    pub fn draw(self: Map, off: Vec2) void {
        // assert(self.tileset); // "Cannot draw map without tileset");

        const offset = off.divf(self.distance);
        const rs = render.renderSize();
        const rsf = types.fromVec2i(render.renderSize());
        const ts = self.tile_size;
        const tsf: f32 = @floatFromInt(ts);

        if (self.repeat) {
            const tile_offset = types.fromVec2(offset).divi(ts);
            const px_offset = vec2(@mod(offset.x, tsf), @mod(offset.y, tsf));
            const px_min = vec2(-px_offset.x - tsf, -px_offset.y - tsf);
            const px_max = vec2(-px_offset.x + rsf.x + tsf, -px_offset.y + rsf.y + tsf);

            var pos = px_min;
            var map_y: i32 = -1;
            while (pos.y < px_max.y) {
                const y: i32 = @mod(@mod((map_y + tile_offset.y), self.size.y) + self.size.y, self.size.y);

                pos.x = px_min.x;
                var map_x: i32 = -1;
                while (pos.x < px_max.x) {
                    const x: i32 = @mod(@mod((map_x + tile_offset.x), self.size.x) + self.size.x, self.size.x);

                    const tile: u16 = self.data[@intCast(y * self.size.x + x)];

                    if (tile != 0) {
                        self.drawTile(tile - 1, pos);
                    }
                    map_x += 1;
                    pos.x += tsf;
                }
                map_y += 1;
                pos.y += tsf;
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

    fn drawTile(self: Map, t: u16, pos: Vec2) void {
        var tile = t;
        if (self.anims) |anims| {
            if (anims[tile]) |def| {
                const frame = @as(usize, @intFromFloat(engine.time * def.inv_frame_time)) % def.sequence.len;
                tile = def.sequence[frame];
            }
        }

        self.tileset.?.drawTile(tile, vec2i(self.tile_size, self.tile_size), pos);
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
