const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const Image = @import("../image.zig").Image;
const engine = @import("../engine.zig");
const Engine = @import("../engine.zig").Engine;
const types = @import("../types.zig");
const game = @import("../game.zig");
const vec2 = @import("../types.zig").vec2;
const scale = @import("../utils.zig").scale;
const clamp = std.math.clamp;

var img_biolab: ?Image = null;
var img_disaster: ?Image = null;
var img_player: ?Image = null;

fn init() void {
    img_biolab = Image.init("assets/title-biolab.qoi") catch @panic("failed to init image");
    // img_disaster = Image.init("assets/title-disaster.qoi") catch @panic("failed to init image");
    // img_player = Image.init("assets/title-player.qoi") catch @panic("failed to init image");
    Engine(game.Entity, game.EntityKind).loadLevel("assets/levels/biolab-1.json");
}

fn update() void {}

fn draw() void {
    const d: f32 = @as(f32, @floatCast(engine.time - 1.0));
    img_biolab.?.draw(types.vec2(scale(clamp(d * d * -d, 0.0, 1.0), 1.0, 0, -160, 44), 26));
    // img_disaster.?.draw(vec2(scale(clamp(d * d * -d, 0, 1), 1.0, 0, 300, 44), 70));
    // img_player.?.draw(vec2(scale(clamp(d * d * -d, 0, 1), 0.5, 0, 240, 166), 56));
}

pub var scene_title: Scene = .{
    .init = init,
    .update = update,
    .draw = draw,
};
