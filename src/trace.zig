const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const Map = @import("map.zig").Map;

pub const Trace = struct {
    // The tile that was hit. 0 if no hit.
    tile: i32,

    // The tile position (in tile space) of the hit
    tile_pos: Vec2i = vec2i(0, 0),

    // The normalized 0..1 length of this trace. If this trace did not end in
    // a hit, length will be 1.
    length: f32,

    // The resulting position of the top left corne of the AABB that was traced
    pos: Vec2,

    // The normal vector of the surface that was hit
    normal: Vec2,
};

/// Trace map with the AABB's top left corner, the movement vecotr and size
pub fn trace(map: *Map, from: Vec2, vel: Vec2, size: Vec2) Trace {
    const to = from.add(vel);

    var res = Trace{ .tile = 0, .pos = to, .normal = vec2(0, 0), .length = 1 };

    // Quick check if the whole trace is out of bounds
    const map_size_px = map.size.muli(map.tile_size);
    if ((from.x + size.x < 0 and to.x + size.x < 0) or
        (from.y + size.y < 0 and to.y + size.y < 0) or
        (from.x > @as(f32, @floatFromInt(map_size_px.x)) and to.x > @as(f32, @floatFromInt(map_size_px.x))) or
        (from.y > @as(f32, @floatFromInt(map_size_px.y)) and to.y > @as(f32, @floatFromInt(map_size_px.y))) or
        (vel.x == 0 and vel.y == 0))
    {
        return res;
    }

    const offset = vec2(if (vel.x > 0) 1.0 else 0.0, if (vel.y > 0) 1.0 else 0.0);
    const corner = from.add(size.mul(offset));
    const dir = offset.mulf(-2).add(vec2(1, 1));

    const max_vel = @max(vel.x * -dir.x, vel.y * -dir.y);
    const stepsf = @ceil(max_vel / @as(f32, @floatFromInt(map.tile_size)));
    const steps: usize = @intFromFloat(stepsf);
    if (steps == 0) {
        return res;
    }
    const step_size = vel.divf(stepsf);

    var last_tile_pos = vec2i(-16, -16);
    var extra_step_for_slope = false;
    for (0..steps + 1) |i| {
        const tile_pos = types.fromVec2(corner.add(step_size.mulf(@floatFromInt(i))).divf(@floatFromInt(map.tile_size)));

        var corner_tile_checked: usize = 0;
        if (last_tile_pos.x != tile_pos.x) {
            // Figure out the number of tiles in Y direction we need to check.
            // This walks along the vertical edge of the object (height) from
            // the current tile_pos.x,tile_pos.y position.
            var max_y: f32 = from.y + size.y * (1 - offset.y);
            if (i > 0) {
                max_y += (vel.y / vel.x) * ((@as(f32, @floatFromInt(tile_pos.x)) + 1 - offset.x) * @as(f32, @floatFromInt(map.tile_size)) - corner.x);
            }

            const num_tilesf = @ceil(@abs(max_y / @as(f32, @floatFromInt(map.tile_size)) - @as(f32, @floatFromInt(tile_pos.y)) - offset.y));
            const num_tiles: usize = @intFromFloat(num_tilesf);
            for (0..num_tiles) |t| {
                check_tile(map, from, vel, size, vec2i(tile_pos.x, tile_pos.y + @as(i32, @intFromFloat(dir.y)) * @as(i32, @intCast(t))), &res);
            }

            last_tile_pos.x = tile_pos.x;
            corner_tile_checked = 1;
        }

        if (last_tile_pos.y != tile_pos.y) {
            // Figure out the number of tiles in X direction we need to
            // check. This walks along the horizontal edge of the object
            // (width) from the current tile_pos.x,tile_pos.y position.
            var max_x: f32 = from.x + size.x * (1 - offset.x);
            if (i > 0) {
                max_x += (vel.x / vel.y) * ((@as(f32, @floatFromInt(tile_pos.y)) + 1.0 - offset.y) * @as(f32, @floatFromInt(map.tile_size)) - corner.y);
            }

            const num_tilesf = @ceil(@abs(max_x / @as(f32, @floatFromInt(map.tile_size)) - @as(f32, @floatFromInt(tile_pos.x)) - offset.x));
            const num_tiles: usize = @intFromFloat(num_tilesf);
            for (corner_tile_checked..num_tiles) |t| {
                check_tile(map, from, vel, size, vec2i(tile_pos.x + @as(i32, @intFromFloat(dir.x)) * @as(i32, @intCast(t)), tile_pos.y), &res);
            }

            last_tile_pos.y = tile_pos.y;
        }

        // If we collided with a sloped tile, we have to check one more step
        // forward because we may still collide with another tile at an
        // earlier .length point. For fully solid tiles (id: 1), we can
        // return here.
        if (res.tile > 0 and (res.tile == 1 or extra_step_for_slope)) {
            return res;
        }
        extra_step_for_slope = true;
    }

    return res;
}

pub fn check_tile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, res: *Trace) void {
    const tile = map.tileAt(tile_pos);
    if (tile == 0) {
        return;
    } else if (tile == 1) {
        resolve_full_tile(map, pos, vel, size, tile_pos, res);
    } else {
        unreachable;
        //TODO: resolve_sloped_tile(map, pos, vel, size, tile_pos, tile, res);
    }
}

fn resolve_full_tile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, res: *Trace) void {
    // The minimum resulting x or y position in case of a collision. Only
    // the x or y coordinate is correct - depending on if we enter the tile
    // horizontaly or vertically. We will recalculate the wrong one again.

    var rp =
        types.fromVec2i(tile_pos.muli(map.tile_size)).add(vec2((if (vel.x > 0) -size.x else @floatFromInt(map.tile_size)), (if (vel.y > 0) -size.y else @floatFromInt(map.tile_size))));

    var length: f32 = 1;

    // If we don't move in Y direction, or we do move in X and the the tile
    // corners's cross product with the movement vector has the correct sign,
    // this is a horizontal collision, otherwise it's vertical.
    // float sign = vec2_cross(vel, vec2_sub(rp, pos)) * vel.x * vel.y;
    const sign: f32 = (vel.x * (rp.y - pos.y) - vel.y * (rp.x - pos.x)) * vel.x * vel.y;

    if (sign < 0 or vel.y == 0) {
        // Horizontal collison (x direction, left or right edge)
        length = @abs((pos.x - rp.x) / vel.x);
        if (length > res.length) {
            return;
        }

        rp.y = pos.y + length * vel.y;
        res.normal = vec2((if (vel.x > 0) -1 else 1), 0);
    } else {
        // Vertical collision (y direction, top or bottom edge)
        length = @abs((pos.y - rp.y) / vel.y);
        if (length > res.length) {
            return;
        }

        rp.x = pos.x + length * vel.x;
        res.normal = vec2(0, (if (vel.y > 0) -1 else 1));
    }

    res.tile = 1;
    res.tile_pos = tile_pos;
    res.length = length;
    res.pos = rp;
}
