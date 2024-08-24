const types = @import("types.zig");
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const Map = @import("map.zig").Map;

// const SlopeDef = struct {
// 	 start: Vec2,
// 	 dir: Vec2,
// 	 normal: Vec2,
// 	 solid: bool,
// } ;

// const slope_definitions = []SlopeDef {
// 	 [ 5] = SLOPE(0,1, 1,M, SOLID), [ 6] = SLOPE(0,M, 1,N, SOLID), [ 7] = SLOPE(0,N, 1,0, SOLID), //     15 NE
// 	 [ 3] = SLOPE(0,1, 1,H, SOLID), [ 4] = SLOPE(0,H, 1,0, SOLID), //     22 NE
// 	 [ 2] = SLOPE(0,1, 1,0, SOLID), //     45 NE
// 	 [10] = SLOPE(H,1, 1,0, SOLID), [21] = SLOPE(0,1, H,0, SOLID), //     67 NE
// 	 [32] = SLOPE(M,1, 1,0, SOLID), [43] = SLOPE(N,1, M,0, SOLID), [54] = SLOPE(0,1, N,0, SOLID), //     75 NE
// 	 [27] = SLOPE(0,0, 1,N, SOLID), [28] = SLOPE(0,N, 1,M, SOLID), [29] = SLOPE(0,M, 1,1, SOLID), //     15 SE
// 	 [25] = SLOPE(0,0, 1,H, SOLID), [26] = SLOPE(0,H, 1,1, SOLID), //     22 SE
// 	 [24] = SLOPE(0,0, 1,1, SOLID), //     45 SE */
// 	 [11] = SLOPE(0,0, H,1, SOLID), [22] = SLOPE(H,0, 1,1, SOLID), //     67 SE
// 	 [33] = SLOPE(0,0, N,1, SOLID), [44] = SLOPE(N,0, M,1, SOLID), [55] = SLOPE(M,0, 1,1, SOLID), //     75 SE
// 	 [16] = SLOPE(1,N, 0,0, SOLID), [17] = SLOPE(1,M, 0,N, SOLID), [18] = SLOPE(1,1, 0,M, SOLID), //     15 NW
// 	 [14] = SLOPE(1,H, 0,0, SOLID), [15] = SLOPE(1,1, 0,H, SOLID), //     22 NW
// 	 [13] = SLOPE(1,1, 0,0, SOLID), //     45 NW
// 	 [ 8] = SLOPE(H,1, 0,0, SOLID), [19] = SLOPE(1,1, H,0, SOLID), //     67 NW
// 	 [30] = SLOPE(N,1, 0,0, SOLID), [41] = SLOPE(M,1, N,0, SOLID), [52] = SLOPE(1,1, M,0, SOLID), //     75 NW
// 	 [38] = SLOPE(1,M, 0,1, SOLID), [39] = SLOPE(1,N, 0,M, SOLID), [40] = SLOPE(1,0, 0,N, SOLID), //     15 SW
// 	 [36] = SLOPE(1,H, 0,1, SOLID), [37] = SLOPE(1,0, 0,H, SOLID), //     22 SW
// 	 [35] = SLOPE(1,0, 0,1, SOLID), //     45 SW
// 	 [ 9] = SLOPE(1,0, H,1, SOLID), [20] = SLOPE(H,0, 0,1, SOLID), //     67 SW
// 	 [31] = SLOPE(1,0, M,1, SOLID), [42] = SLOPE(M,0, N,1, SOLID), [53] = SLOPE(N,0, 0,1, SOLID), //     75 SW
// 	 [12] = SLOPE(0,0, 1,0, ONE_WAY), // One way N
// 	 [23] = SLOPE(1,1, 0,1, ONE_WAY), // One way S
// 	 [34] = SLOPE(1,0, 1,1, ONE_WAY), // One way E
// 	 [45] = SLOPE(0,1, 0,0, ONE_WAY)  // One way W
// };

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
        unreachable;
        //TODO: resolve_sloped_tile(map, pos, vel, size, tile_pos, tile, res);
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

// fn resolveSlopedTile(map: *Map, pos: Vec2, vel: Vec2, size: Vec2, tile_pos: Vec2i, tile: i32, res: *Trace) void {
//     if (tile < 2 or tile >= slope_definitions.len) {
//         return;
//     }

//     const slope = &slope_definitions[tile];

//     // Transform the slope line's starting point (s) and line's direction (d)
//     // into world space coordinates.
//     const tile_pos_px = types.fromVec2i(tile_pos).mulf(map.tile_size);

//     const ss = slope.start.mulf(map.tile_size);
//     const sd = slope.dir.mulf(map.tile_size);
//     const local_pos = pos.sub(tile_pos_px);

//     // Do a line vs. line collision with the object's velocity and the slope
//     // itself. This still has problems with precision: When we're moving very
//     // slowly along the slope, we might slip behind it.
//     // FIXME: maybe the better approach would be to treat every sloped tile as
//     // a triangle defined by 3 infinite lines. We could quickly check if the
//     // point is within it - but we would still need to determine from which side
//     // we're moving into the triangle.

//     const epsilon = 0.001;
//     const determinant = vel.cross(sd);

//     if (determinant < -epsilon) {
//         const corner =
//             vec2_sub(local_pos, ss).add(vec2(if (sd.y < 0) size.x else 0, if (sd.x > 0) size.y else 0));

//         const point_at_slope = vel.cross(corner) / determinant;
//         const point_at_vel = sd.cross(corner) / determinant;

//         // Are we in front of the slope and moving into it?
//         if (point_at_vel > -epsilon and
//             point_at_vel < 1 + epsilon and
//             point_at_slope > -epsilon and
//             point_at_slope < 1 + epsilon)
//         {
//             // Is this an earlier point than one that we already collided with?
//             if (point_at_vel <= res.length) {
//                 res.tile = tile;
//                 res.tile_pos = tile_pos;
//                 res.length = point_at_vel;
//                 res.normal = slope.normal;
//                 res.pos = vec2_add(pos, vec2_mulf(vel, point_at_vel));
//             }
//             return;
//         }
//     }
//     // Is this a non-solid (one-way) tile and we're coming from the wrong side?
//     if (!slope.solid and (determinant > 0 or sd.x * sd.y != 0)) {
//         return;
//     }

//     // We did not collide with the slope itself, but we still have to check
//     // if we collide with the slope's corners or the remaining sides of the
//     // tile.

//     // Figure out the potential collision points for a horizontal or
//     // vertical collision and calculate the min and max coords that will
//     // still collide with the tile.

//     var rp: Vec2 = undefined;
//     var min: Vec2 = undefined;
//     var max: Vec2 = undefined;
//     var length: f32 = 1.0;

//     if (sd.y >= 0) {
//         // left tile edge
//         min.x = -size.x - epsilon;

//         // left or right slope corner?
//         max.x = (if (vel.y > 0) ss.x else ss.x + sd.x) - epsilon;
//         rp.x = if (vel.x > 0) min.x else @max(ss.x, ss.x + sd.x);
//     } else {
//         // left or right slope corner?
//         min.x = (if (vel.y > 0) ss.x + sd.x else ss.x) - size.x + epsilon;

//         // right tile edge
//         max.x = map.tile_size + epsilon;
//         rp.x = if (vel.x > 0) @min(ss.x, ss.x + sd.x) - size.x else max.x;
//     }

//     if (sd.x > 0) {
//         // top or bottom slope corner?
//         min.y = (if (vel.x > 0) ss.y else ss.y + sd.y) - size.y + epsilon;

//         // bottom tile edge
//         max.y = map.tile_size + epsilon;
//         rp.y = if (vel.y > 0) @min(ss.y, ss.y + sd.y) - size.y else max.y;
//     } else {
//         // top tile edge
//         min.y = -size.y - epsilon;

//         // top or bottom slope corner?
//         max.y = (if (vel.x > 0) ss.y + sd.y else ss.y) - epsilon;
//         rp.y = if (vel.y > 0) min.y else max(ss.y, ss.y + sd.y);
//     }

//     // Figure out if this is a horizontal or vertical collision. This
//     // step is similar to what we do with full tile collisions.

//     const sign = vel.cross(rp.sub(local_pos)) * vel.x * vel.y;
//     if (sign < 0 or vel.y == 0) {
//         // Horizontal collision (x direction, left or right edge)
//         length = fabsf((local_pos.x - rp.x) / vel.x);
//         rp.y = local_pos.y + length * vel.y;

//         if (rp.y >= max.y or rp.y <= min.y or
//             length > res.length or
//             (!slope.solid and sd.y == 0))
//         {
//             return;
//         }

//         res.normal.x = (if (vel.x > 0) -1 else 1);
//         res.normal.y = 0;
//     } else {
//         // Vertical collision (y direction, top or bottom edge)
//         length = fabsf((local_pos.y - rp.y) / vel.y);
//         rp.x = local_pos.x + length * vel.x;

//         if (rp.x >= max.x or rp.x <= min.x or
//             length > res.length or
//             (!slope.solid and sd.x == 0))
//         {
//             return;
//         }

//         res.normal.x = 0;
//         res.normal.y = (if (vel.y > 0) -1 else 1);
//     }

//     res.tile = tile;
//     res.tile_pos = tile_pos;
//     res.length = length;
//     res.pos = vec2_add(rp, tile_pos_px);
// }
