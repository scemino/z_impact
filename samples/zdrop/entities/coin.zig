const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const g = @import("../global.zig");
const Entity = zi.Entity;

var anim_idle: zi.AnimDef = undefined;
var sound_collect: *zi.sound.SoundSource = undefined;

fn load() void {
    const sheet = zi.image("assets/coin.qoi");
    anim_idle = zi.animDef(sheet, zi.vec2i(4, 4), 0.1, &[_]u16{ 0, 1 }, true);
    sound_collect = zi.sound.source("assets/coin.qoa");
}

fn init(self: *Entity) void {
    self.anim = zi.anim(&anim_idle);
    self.size = zi.vec2(6, 6);
    self.offset = zi.vec2(-1, -1);

    self.check_against = zi.entity.ENTITY_GROUP_PLAYER;
}

fn update(self: *Entity) void {
    if ((self.pos.y - zi.engine.viewport.y) < -32) {
        zi.entity.entityKill(self);
    }
}

fn touch(self: *Entity, other: *Entity) void {
    _ = other;
    g.score += 500;
    zi.sound.play(sound_collect);
    zi.entity.entityKill(self);
}

pub const vtab: zi.EntityVtab = .{
    .load = load,
    .init = init,
    .update = update,
    .touch = touch,
};
