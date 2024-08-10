const std = @import("std");
const game = @import("../game.zig");
const Entity = game.Entity;
const EntityVtab = @import("../entity.zig").EntityVtab;
const Image = @import("../image.zig").Image;
const engine = @import("../engine.zig");
const utils = @import("../utils.zig");
const Vec2 = types.Vec2;
const types = @import("../types.zig");
const scale = utils.scale;
const clamp = std.math.clamp;

var img_biolab: ?Image = null;
var img_disaster: ?Image = null;
var img_player: ?Image = null;

fn load() void {
    img_biolab = Image.init("assets/title-biolab.qoi") catch @panic("failed to init image");
}

fn init(e: *Entity) void {
    _ = e;
}

fn update(e: *Entity) void {
    _ = e;
}

fn draw(e: *Entity, pos: Vec2) void {
    _ = e;
    _ = pos;
    const d: f32 = @as(f32, @floatCast(engine.time - 1.0));
    img_biolab.?.draw(types.vec2(scale(clamp(d * d * -d, 0.0, 1.0), 1.0, 0, -160, 44), 26));
    std.log.info("blob: draw", .{});
}

pub var vtab: EntityVtab(Entity) = .{
    .load = load,
    .init = init,
    .update = update,
    .draw = draw,
};
