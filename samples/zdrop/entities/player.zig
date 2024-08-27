const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const Entity = zi.Entity;

pub const A_LEFT: u8 = 1;
pub const A_RIGHT: u8 = 2;
pub const A_START: u8 = 4;

var anim_idle: zi.AnimDef = undefined;
var hints: *zi.Image = undefined;
var sound_bounce: *zi.sound.SoundSource = undefined;

fn load() void {
    const sheet = zi.image("assets/player.qoi");
    anim_idle = zi.animDef(sheet, zi.vec2i(4, 4), 1.0, &[_]u16{0}, true);
    sound_bounce = zi.sound.source("assets/bounce.qoa");
    hints = zi.image("assets/hints.qoi");
}

fn init(self: *Entity) void {
    self.anim = zi.anim(&anim_idle);
    self.size = zi.vec2(4, 4);
    self.friction = zi.vec2(4, 0);
    self.restitution = 0.5;

    self.group = zi.entity.ENTITY_GROUP_PLAYER;
    self.physics = zi.entity.ENTITY_PHYSICS_WORLD;
}

fn update(self: *Entity) void {
    if (zi.input.stateb(A_LEFT)) {
        self.accel.x = -300;
    } else if (zi.input.stateb(A_RIGHT)) {
        self.accel.x = 300;
    } else {
        self.accel.x = 0;
    }
    zi.entity.entityBaseUpdate(self);
}

fn draw(self: *Entity, vp: zi.Vec2) void {
    zi.entity.entityBaseDraw(self, vp);

    // Draw arrows when player is off-screen
    if (self.pos.y < vp.y - 4) {
        hints.drawTile(1, zi.vec2i(4, 4), zi.vec2(self.pos.x, 0));
    } else if (self.pos.x < -4) {
        hints.drawTile(0, zi.vec2i(4, 4), zi.vec2(0, self.pos.y - vp.y));
    } else if (self.pos.x > @as(f32, @floatFromInt(zi.render.renderSize().x))) {
        hints.drawTile(2, zi.vec2i(4, 4), zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) - 4, self.pos.y - vp.y));
    }
}

fn collide(self: *Entity, normal: zi.Vec2, _: ?zi.Trace) void {
    if (normal.y == -1 and self.vel.y > 32) {
        zi.sound.play(sound_bounce);
    }
}

pub const vtab: zi.EntityVtab = .{
    .load = load,
    .init = init,
    .update = update,
    .draw = draw,
    .collide = collide,
};
