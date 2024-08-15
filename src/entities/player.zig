const std = @import("std");
const game = @import("../game.zig");
const Entity = game.Entity;
const Image = @import("../image.zig").Image;
const EntityVtab = @import("../entity.zig").EntityVtab;
const types = @import("../types.zig");
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const animDef = @import("../anim.zig").animDef;
const anim = @import("../anim.zig").anim;
const AnimDef = @import("../anim.zig").AnimDef;
const render = @import("../render.zig");
const input = @import("../input.zig");
const ett = @import("../entity.zig");
const Engine = @import("../engine.zig").Engine;
const engine = Engine(game.Entity, game.EntityKind);
const Trace = @import("../trace.zig").Trace;
const snd = @import("../sound.zig");

pub const A_LEFT: u8 = 1;
pub const A_RIGHT: u8 = 2;
pub const A_START: u8 = 4;

var anim_idle: AnimDef = undefined;
var hints: *Image = undefined;
var sound_bounce: *snd.SoundSource = undefined;

fn load() void {
    const sheet = Image.init("assets/player.qoi") catch @panic("failed to init image");
    anim_idle = animDef(sheet, vec2i(4, 4), 1.0, &[_]u16{0}, true);
    sound_bounce = snd.source("assets/bounce.qoa");
    hints = Image.init("assets/hints.qoi") catch @panic("failed to init image");
}

fn init(self: *Entity) void {
    self.base.anim = anim(&anim_idle);
    self.base.size = vec2(4, 4);
    self.base.friction = vec2(4, 0);
    self.base.restitution = 0.5;

    self.base.group = ett.ENTITY_GROUP_PLAYER;
    self.base.physics = ett.ENTITY_PHYSICS_WORLD;
}

fn update(self: *Entity) void {
    if (input.stateb(A_LEFT)) {
        self.base.accel.x = -300;
    } else if (input.stateb(A_RIGHT)) {
        self.base.accel.x = 300;
    } else {
        self.base.accel.x = 0;
    }
    engine.baseUpdate(self);
}

fn draw(self: *Entity, vp: Vec2) void {
    engine.entityBaseDraw(self, vp);

    // Draw arrows when player is off-screen
    if (self.base.pos.y < vp.y - 4) {
        hints.drawTile(1, vec2i(4, 4), vec2(self.base.pos.x, 0));
    } else if (self.base.pos.x < -4) {
        hints.drawTile(0, vec2i(4, 4), vec2(0, self.base.pos.y - vp.y));
    } else if (self.base.pos.x > @as(f32, @floatFromInt(render.renderSize().x))) {
        hints.drawTile(2, vec2i(4, 4), vec2(@as(f32, @floatFromInt(render.renderSize().x)) - 4, self.base.pos.y - vp.y));
    }
}

fn collide(self: *Entity, normal: Vec2, _: ?Trace) void {
    if (normal.y == -1 and self.base.vel.y > 32) {
        snd.play(sound_bounce);
    }
}

pub var vtab: EntityVtab(Entity) = .{
    .load = load,
    .init = init,
    .update = update,
    .draw = draw,
    .collide = collide,
};
