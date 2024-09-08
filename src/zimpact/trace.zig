const std = @import("std");
const cmn = @import("platform").cmn;
const types = cmn.types;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const Map = @import("map.zig").Map;

const SlopeDef = struct {
    start: Vec2 = vec2(0, 0),
    dir: Vec2 = vec2(0, 0),
    normal: Vec2 = vec2(0, 0),
    solid: bool = false,
};

// Define all sloped tiles by their start (x,y) and end (x,y) coordinates in
// normalized (0..1) space. We compute the direction of the slope and the
// slope's normal from this.

fn slopeLen(x: f32, y: f32) f32 {
    return std.math.sqrt(x * x + y * y);
}

fn slopeNormal(x: f32, y: f32) Vec2 {
    return vec2(y / slopeLen(x, y), -x / slopeLen(x, y));
}

fn slopeDef(sx: f32, sy: f32, ex: f32, ey: f32, solid: bool) SlopeDef {
    return .{
        .start = vec2(sx, sy),
        .dir = vec2(ex - sx, ey - sy),
        .normal = slopeNormal(ex - sx, ey - sy),
        .solid = solid,
    };
}

// Corner points for all slope tiles are either at 0.0, 1.0, 0.5, 0.333 or 0.666
// Defining these here as H, N and M hopefully makes this a bit easier to read.

const H = (1.0 / 2.0);
const N = (1.0 / 3.0);
const M = (2.0 / 3.0);
const SOLID = true;
const ONE_WAY = false;

const slope_definitions = [_]SlopeDef{
    .{}, // 0
    .{}, // 1
    slopeDef(0, 1, 1, 0, SOLID), //     45 NE
    slopeDef(0, 1, 1, H, SOLID),
    slopeDef(0, H, 1, 0, SOLID), //     22 NE
    slopeDef(0, 1, 1, M, SOLID),
    slopeDef(0, M, 1, N, SOLID),
    slopeDef(0, N, 1, 0, SOLID), //     15 NE
    slopeDef(H, 1, 0, 0, SOLID),
    slopeDef(1, 0, H, 1, SOLID),
    slopeDef(H, 1, 1, 0, SOLID),
    slopeDef(0, 0, H, 1, SOLID),
    slopeDef(0, 0, 1, 0, ONE_WAY), // One way N
    slopeDef(1, 1, 0, 0, SOLID), //     45 NW
    slopeDef(1, H, 0, 0, SOLID),
    slopeDef(1, 1, 0, H, SOLID), //     22 NW
    slopeDef(1, N, 0, 0, SOLID),
    slopeDef(1, M, 0, N, SOLID),
    slopeDef(1, 1, 0, M, SOLID), //     15 NW
    slopeDef(1, 1, H, 0, SOLID), //     67 NW
    slopeDef(H, 0, 0, 1, SOLID), //     67 SW
    slopeDef(0, 1, H, 0, SOLID), //     67 NE
    slopeDef(H, 0, 1, 1, SOLID), //     67 SE
    slopeDef(1, 1, 0, 1, ONE_WAY), // One way S
    slopeDef(0, 0, 1, 1, SOLID), //     45 SE */
    slopeDef(0, 0, 1, H, SOLID),
    slopeDef(0, H, 1, 1, SOLID), //     22 SE
    slopeDef(0, 0, 1, N, SOLID),
    slopeDef(0, N, 1, M, SOLID),
    slopeDef(0, M, 1, 1, SOLID), //     15 SE
    slopeDef(N, 1, 0, 0, SOLID),
    slopeDef(1, 0, M, 1, SOLID),
    slopeDef(M, 1, 1, 0, SOLID),
    slopeDef(0, 0, N, 1, SOLID),
    slopeDef(1, 0, 1, 1, ONE_WAY), // One way E
    slopeDef(1, 0, 0, 1, SOLID), //     45 SW
    slopeDef(1, H, 0, 1, SOLID),
    slopeDef(1, 0, 0, H, SOLID), //     22 SW
    slopeDef(1, M, 0, 1, SOLID),
    slopeDef(1, N, 0, M, SOLID),
    slopeDef(1, 0, 0, N, SOLID), //     15 SW
    slopeDef(M, 1, N, 0, SOLID),
    slopeDef(M, 0, N, 1, SOLID),
    slopeDef(N, 1, M, 0, SOLID),
    slopeDef(N, 0, M, 1, SOLID),
    slopeDef(0, 1, 0, 0, ONE_WAY), // One way W
    .{}, // 46
    .{}, // 47
    .{}, // 48
    .{}, // 49
    .{}, // 50
    .{}, // 51
    slopeDef(1, 1, M, 0, SOLID), //     75 NW
    slopeDef(N, 0, 0, 1, SOLID), //     75 SW
    slopeDef(0, 1, N, 0, SOLID), //     75 NE
    slopeDef(M, 0, 1, 1, SOLID), //     75 SE
};

pub const Trace = struct {
    /// The tile that was hit. 0 if no hit.
    tile: i32,

    /// The tile position (in tile space) of the hit
    tile_pos: Vec2i = vec2i(0, 0),

    /// The normalized 0..1 length of this trace. If this trace did not end in
    /// a hit, length will be 1.
    length: f32,

    /// The resulting position of the top left corne of the AABB that was traced
    pos: Vec2,

    /// The normal vector of the surface that was hit
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
                checkTile(map, from, vel, size, vec2i(tile_pos.x, tile_pos.y + @as(i32, @intFromFloat(dir.y)) * @as(i32, @intCast(t))), &res);
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
                checkTile(map, from, vel, size, vec2i(tile_pos.x + @as(i32, @intFromFloat(dir.x)) * @as(i32, @intCast(t)), tile_pos.y), &res);
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

fn checkTile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, res: *Trace) void {
    const tile = map.tileAt(tile_pos);
    if (tile == 0) {
        return;
    } else if (tile == 1) {
        resolveFullTile(map, pos, vel, size, tile_pos, res);
    } else {
        resolveSlopedTile(map, pos, vel, size, tile_pos, tile, res);
    }
}

fn resolveFullTile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, res: *Trace) void {
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

fn resolveSlopedTile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, tile: i32, res: *Trace) void {
    if (tile < 2 or tile >= slope_definitions.len) {
        return;
    }

    const slope = &slope_definitions[@intCast(tile)];

    // Transform the slope line's starting point (s) and line's direction (d)
    // into world space coordinates.
    const tile_pos_px = types.fromVec2i(tile_pos).mulf(@floatFromInt(map.tile_size));

    const ss = slope.start.mulf(@floatFromInt(map.tile_size));
    const sd = slope.dir.mulf(@floatFromInt(map.tile_size));
    const local_pos = pos.sub(tile_pos_px);

    // Do a line vs. line collision with the object's velocity and the slope
    // itself. This still has problems with precision: When we're moving very
    // slowly along the slope, we might slip behind it.
    // FIXME: maybe the better approach would be to treat every sloped tile as
    // a triangle defined by 3 infinite lines. We could quickly check if the
    // point is within it - but we would still need to determine from which side
    // we're moving into the triangle.

    const epsilon = 0.001;
    const determinant = vel.cross(sd);

    if (determinant < -epsilon) {
        const corner =
            local_pos.sub(ss).add(vec2(if (sd.y < 0) size.x else 0, if (sd.x > 0) size.y else 0));

        const point_at_slope = vel.cross(corner) / determinant;
        const point_at_vel = sd.cross(corner) / determinant;

        // Are we in front of the slope and moving into it?
        if (point_at_vel > -epsilon and
            point_at_vel < 1 + epsilon and
            point_at_slope > -epsilon and
            point_at_slope < 1 + epsilon)
        {
            // Is this an earlier point than one that we already collided with?
            if (point_at_vel <= res.length) {
                res.tile = tile;
                res.tile_pos = tile_pos;
                res.length = point_at_vel;
                res.normal = slope.normal;
                res.pos = pos.add(vel.mulf(point_at_vel));
            }
            return;
        }
    }
    // Is this a non-solid (one-way) tile and we're coming from the wrong side?
    if (!slope.solid and (determinant > 0 or sd.x * sd.y != 0)) {
        return;
    }

    // We did not collide with the slope itself, but we still have to check
    // if we collide with the slope's corners or the remaining sides of the
    // tile.

    // Figure out the potential collision points for a horizontal or
    // vertical collision and calculate the min and max coords that will
    // still collide with the tile.

    var rp: Vec2 = undefined;
    var min: Vec2 = undefined;
    var max: Vec2 = undefined;
    var length: f32 = 1.0;

    if (sd.y >= 0) {
        // left tile edge
        min.x = -size.x - epsilon;

        // left or right slope corner?
        max.x = (if (vel.y > 0) ss.x else ss.x + sd.x) - epsilon;
        rp.x = if (vel.x > 0) min.x else @max(ss.x, ss.x + sd.x);
    } else {
        // left or right slope corner?
        min.x = (if (vel.y > 0) ss.x + sd.x else ss.x) - size.x + epsilon;

        // right tile edge
        max.x = @as(f32, @floatFromInt(map.tile_size)) + epsilon;
        rp.x = if (vel.x > 0) @min(ss.x, ss.x + sd.x) - size.x else max.x;
    }

    if (sd.x > 0) {
        // top or bottom slope corner?
        min.y = (if (vel.x > 0) ss.y else ss.y + sd.y) - size.y + epsilon;

        // bottom tile edge
        max.y = @as(f32, @floatFromInt(map.tile_size)) + epsilon;
        rp.y = if (vel.y > 0) @min(ss.y, ss.y + sd.y) - size.y else max.y;
    } else {
        // top tile edge
        min.y = -size.y - epsilon;

        // top or bottom slope corner?
        max.y = (if (vel.x > 0) ss.y + sd.y else ss.y) - epsilon;
        rp.y = if (vel.y > 0) min.y else @max(ss.y, ss.y + sd.y);
    }

    // Figure out if this is a horizontal or vertical collision. This
    // step is similar to what we do with full tile collisions.

    const sign = vel.cross(rp.sub(local_pos)) * vel.x * vel.y;
    if (sign < 0 or vel.y == 0) {
        // Horizontal collision (x direction, left or right edge)
        length = @abs((local_pos.x - rp.x) / vel.x);
        rp.y = local_pos.y + length * vel.y;

        if (rp.y >= max.y or rp.y <= min.y or
            length > res.length or
            (!slope.solid and sd.y == 0))
        {
            return;
        }

        res.normal.x = (if (vel.x > 0) -1 else 1);
        res.normal.y = 0;
    } else {
        // Vertical collision (y direction, top or bottom edge)
        length = @abs((local_pos.y - rp.y) / vel.y);
        rp.x = local_pos.x + length * vel.x;

        if (rp.x >= max.x or rp.x <= min.x or
            length > res.length or
            (!slope.solid and sd.x == 0))
        {
            return;
        }

        res.normal.x = 0;
        res.normal.y = (if (vel.y > 0) -1 else 1);
    }

    res.tile = tile;
    res.tile_pos = tile_pos;
    res.length = length;
    res.pos = rp.add(tile_pos_px);
}
