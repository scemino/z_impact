const std = @import("std");
const game = @import("../game.zig");
const ett = @import("../entity.zig");
const EntityVtab = ett.EntityVtab;
const Entity = game.Entity;
const Image = @import("../image.zig").Image;
const types = @import("../types.zig");
const animDef = @import("../anim.zig").animDef;
const AnimDef = @import("../anim.zig").AnimDef;
const anim = @import("../anim.zig").anim;
const Vec2i = types.Vec2i;
const vec2 = types.vec2;
const Vec2 = types.Vec2;
const vec2i = types.vec2i;
const Engine = @import("../engine.zig").Engine;
const engine = Engine(game.Entity, game.EntityKind);
const ziengine = @import("../engine.zig");
const g = @import("../global.zig");

var anim_idle: AnimDef = undefined;
// static sound_source_t *sound_collect;

fn load() void {
    const sheet = Image.init("assets/coin.qoi") catch @panic("failed to init image");
    anim_idle = animDef(sheet, vec2i(4, 4), 0.1, &[_]u16{ 0, 1 }, true);
    // sound_collect = sound_source("assets/coin.qoa");
}

fn init(self: *Entity) void {
    self.base.anim = anim(&anim_idle);
    self.base.size = vec2(6, 6);
    self.base.offset = vec2(-1, -1);

    self.base.check_against = ett.ENTITY_GROUP_PLAYER;
}

fn update(self: *Entity) void {
    if ((self.base.pos.y - ziengine.viewport.y) < -32) {
        engine.killEntity(self);
    }
}

fn touch(self: *Entity, other: *Entity) void {
    _ = other;
    g.score += 500;
    // sound_play(sound_collect);
    engine.killEntity(self);
}

pub var vtab: EntityVtab(Entity) = .{
    .load = load,
    .init = init,
    .update = update,
    .touch = touch,
};
