const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const g = @import("../global.zig");
const ett = zi.entity;
const EntityVtab = ett.EntityVtab;
const Entity = game.Entity;
const Image = zi.Image;
const animDef = zi.animDef;
const AnimDef = zi.AnimDef;
const anim = zi.anim;
const Vec2i = zi.Vec2i;
const vec2 = zi.vec2;
const Vec2 = zi.Vec2;
const vec2i = zi.vec2i;
const engine = zi.engine;
const snd = zi.sound;
const Engine = zi.Engine(game.Entity, game.EntityKind);

var anim_idle: AnimDef = undefined;
var sound_collect: *snd.SoundSource = undefined;

fn load() void {
    const sheet = Image.init("assets/coin.qoi") catch @panic("failed to init image");
    anim_idle = animDef(sheet, vec2i(4, 4), 0.1, &[_]u16{ 0, 1 }, true);
    sound_collect = snd.source("assets/coin.qoa");
}

fn init(self: *Entity) void {
    self.base.anim = anim(&anim_idle);
    self.base.size = vec2(6, 6);
    self.base.offset = vec2(-1, -1);

    self.base.check_against = ett.ENTITY_GROUP_PLAYER;
}

fn update(self: *Entity) void {
    if ((self.base.pos.y - engine.viewport.y) < -32) {
        Engine.killEntity(self);
    }
}

fn touch(self: *Entity, other: *Entity) void {
    _ = other;
    g.score += 500;
    snd.play(sound_collect);
    Engine.killEntity(self);
}

pub var vtab: EntityVtab(Entity) = .{
    .load = load,
    .init = init,
    .update = update,
    .touch = touch,
};
