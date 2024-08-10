const std = @import("std");
const game = @import("../game.zig");
const Entity = game.Entity;
const EntityVtab = @import("../entity.zig").EntityVtab;
const types = @import("../types.zig");
const Vec2 = types.Vec2;

fn load() void {}

fn init(e: *Entity) void {
    _ = e;
}

fn update(e: *Entity) void {
    _ = e;
}

fn draw(e: *Entity, pos: Vec2) void {
    _ = e;
    _ = pos;
    std.log.info("player: draw", .{});
}

pub var vtab: EntityVtab(Entity) = .{
    .load = load,
    .init = init,
    .update = update,
    .draw = draw,
};
