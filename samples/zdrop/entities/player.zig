const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const Entity = zi.Entity;
const Image = zi.Image;
const EntityVtab = zi.EntityVtab;
const Vec2 = zi.Vec2;
const vec2 = zi.vec2;
const vec2i = zi.vec2i;
const animDef = zi.animDef;
const anim = zi.anim;
const AnimDef = zi.AnimDef;
const render = zi.render;
const input = zi.input;
const ett = zi.entity;
const snd = zi.sound;

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
    self.anim = anim(&anim_idle);
    self.size = vec2(4, 4);
    self.friction = vec2(4, 0);
    self.restitution = 0.5;

    self.group = ett.ENTITY_GROUP_PLAYER;
    self.physics = ett.ENTITY_PHYSICS_WORLD;
}

fn update(self: *Entity) void {
    if (input.stateb(A_LEFT)) {
        self.accel.x = -300;
    } else if (input.stateb(A_RIGHT)) {
        self.accel.x = 300;
    } else {
        self.accel.x = 0;
    }
    zi.entity.entityBaseUpdate(self);
}

fn draw(self: *Entity, vp: Vec2) void {
    ett.entityBaseDraw(self, vp);

    // Draw arrows when player is off-screen
    if (self.pos.y < vp.y - 4) {
        hints.drawTile(1, vec2i(4, 4), vec2(self.pos.x, 0));
    } else if (self.pos.x < -4) {
        hints.drawTile(0, vec2i(4, 4), vec2(0, self.pos.y - vp.y));
    } else if (self.pos.x > @as(f32, @floatFromInt(render.renderSize().x))) {
        hints.drawTile(2, vec2i(4, 4), vec2(@as(f32, @floatFromInt(render.renderSize().x)) - 4, self.pos.y - vp.y));
    }
}

fn collide(self: *Entity, normal: Vec2, _: ?zi.Trace) void {
    if (normal.y == -1 and self.vel.y > 32) {
        snd.play(sound_bounce);
    }
}

pub const vtab: zi.EntityVtab = .{
    .load = load,
    .init = init,
    .update = update,
    .draw = draw,
    .collide = collide,
};
