const std = @import("std");
const assert = std.debug.assert;
const img = @import("image.zig");
const types = @import("types.zig");
const engine = @import("engine.zig");
const render = @import("render.zig");
const vec2 = types.vec2;
const Rgba = types.Rgba;
const Vec2 = types.Vec2;
const Vec2i = types.Vec2i;

pub const AnimDef = struct {
    sheet: *const img.Image,
    frame_size: Vec2i,
    loop: bool,
    pivot: Vec2,
    frame_time: f32,
    inv_total_time: f32,
    sequence: []const u16,
};

pub const Anim = struct {
    def: *const AnimDef,
    start_time: f64,
    tile_offset: u16 = 0,
    flip_x: bool = false,
    flip_y: bool = false,
    rotation: f32 = 0.0,
    color: Rgba,

    pub fn draw(self: *Anim, pos: Vec2) void {
        var def = self.def;
        const rs = render.renderSize();
        if ((pos.x > @as(f32, @floatFromInt(rs.x))) or (pos.y > @as(f32, @floatFromInt(rs.y)) or
            (pos.x + @as(f32, @floatFromInt(def.frame_size.x)) < 0) or (pos.y + @as(f32, @floatFromInt(def.frame_size.y)) < 0) or
            (self.color.a() <= 0)))
            return;

        const diff: f64 = @max(0, engine.time - self.start_time);
        const looped: f64 = diff * def.inv_total_time;

        const frame = if (!def.loop and looped >= 1) def.sequence.len - 1 else @as(usize, @intFromFloat((looped - @floor(looped)) * @as(f64, @floatFromInt(def.sequence.len))));
        const tile = def.sequence[frame] + self.tile_offset;
        std.log.info("frame: {}, diff: {}, seq: {}", .{ frame, diff, def.sequence[frame] });

        // if (self.rotation == 0)
        {
            def.sheet.drawTileEx(tile, def.frame_size, pos, self.flip_x, self.flip_y, self.color);
        }
        // else {
        // 	render_push();
        // 	render_translate(vec2_add(pos, def.pivot));
        // 	render_rotate(self.rotation);
        // 	image_draw_tile_ex(
        // 		def.sheet, tile, def.frame_size, vec2_mulf(def.pivot, -1),
        // 		self.flip_x, self.flip_y, self.color
        // 	);
        // 	render_pop();
        // }
    }
};

/// Create an anim_def with the given sheet, frame_size, frame_time, sequence and loop.
/// E.g.: animDef(sheet, vec2i(16, 8), 0.5, [_]u16{0,1,2,3,4}, true);
pub fn animDef(sheet: *const img.Image, frame_size: Vec2i, frame_time: f32, sequence: []const u16, loop: bool) AnimDef {
    assert(sequence.len > 0);
    return .{
        .sheet = sheet,
        .frame_size = frame_size,
        .loop = loop,
        .pivot = vec2(0, 0),
        .frame_time = frame_time,
        .inv_total_time = 1.0 / (@as(f32, @floatFromInt(sequence.len)) * frame_time),
        .sequence = sequence,
    };
}

/// Create an Anim instance with the given AnimDef
pub fn anim(anim_def: *const AnimDef) Anim {
    return .{ .def = anim_def, .color = types.white(), .start_time = engine.time };
}
