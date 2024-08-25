const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const g = @import("../global.zig");
const Entity = zi.Entity;
const Image = zi.Image;
const animDef = zi.animDef;
const AnimDef = zi.AnimDef;
const anim = zi.anim;
const Vec2i = zi.Vec2i;
const vec2 = zi.vec2;
const Vec2 = zi.Vec2;
const vec2i = zi.vec2i;
const snd = zi.sound;

var anim_idle: AnimDef = undefined;
var sound_collect: *snd.SoundSource = undefined;

fn load() void {
    const sheet = Image.init("assets/coin.qoi") catch @panic("failed to init image");
    anim_idle = animDef(sheet, vec2i(4, 4), 0.1, &[_]u16{ 0, 1 }, true);
    sound_collect = snd.source("assets/coin.qoa");
}

fn init(self: *Entity) void {
    self.anim = anim(&anim_idle);
    self.size = vec2(6, 6);
    self.offset = vec2(-1, -1);

    self.check_against = zi.entity.ENTITY_GROUP_PLAYER;
}

fn update(self: *Entity) void {
    if ((self.pos.y - zi.engine.viewport.y) < -32) {
        zi.Engine.entityKill(self);
    }
}

fn touch(self: *Entity, other: *Entity) void {
    _ = other;
    g.score += 500;
    snd.play(sound_collect);
    zi.Engine.entityKill(self);
}

pub const vtab: zi.EntityVtab = .{
    .load = load,
    .init = init,
    .update = update,
    .touch = touch,
};
