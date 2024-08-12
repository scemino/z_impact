const Vec2 = @import("types.zig").Vec2;
const Vec2i = @import("types.zig").Vec2i;

const Trace = struct {
    // The tile that was hit. 0 if no hit.
    tile: i32,

    // The tile position (in tile space) of the hit
    tile_pos: Vec2i,

    // The normalized 0..1 length of this trace. If this trace did not end in
    // a hit, length will be 1.
    length: f32,

    // The resulting position of the top left corne of the AABB that was traced
    pos: Vec2,

    // The normal vector of the surface that was hit
    normal: Vec2,
};
