const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const engine = @import("engine.zig");
const render = @import("render.zig");
const img = @import("image.zig");
const a = @import("anim.zig");
const Image = img.Image;
const types = @import("types.zig");
const vec2i = types.vec2i;
const vec2 = types.vec2;
const stm = @import("sokol").time;
const scale = @import("utils.zig").scale;
const clamp = std.math.clamp;

var img_biolab: Image = undefined;
var blob_sheet: Image = undefined;
var start_time: u64 = 0;
var blob_anim: a.Anim = undefined;
var anim_idle: a.AnimDef = undefined;

export fn init() void {
    stm.setup();
    start_time = stm.now();
    engine.init();
    img_biolab = Image.init("assets/title-biolab.qoi") catch @panic("failed to init image");
    blob_sheet = Image.init("assets/sprites/blob.qoi") catch @panic("failed to init image");
    anim_idle = a.animDef(&blob_sheet, vec2i(16, 16), 0.5, &[_]u16{ 1, 2, 2, 2, 2, 2, 2, 2, 2, 1, 1, 1, 1, 1, 1, 2, 2, 2, 2, 2, 2, 2, 2, 2 }, true);
    blob_anim = a.anim(&anim_idle);
}

export fn update() void {
    const d: f32 = @as(f32, @floatCast(stm.sec(stm.since(start_time)))) - 1.0;
    render.framePrepare();
    img_biolab.draw(types.vec2(scale(clamp(d * d * -d, 0.0, 1.0), 1.0, 0, -160, 44), 26));
    blob_anim.draw(vec2(16, 16));
    engine.update();
}

export fn cleanup() void {
    engine.cleanup();
}

pub fn main() void {
    sapp.run(.{
        .init_cb = init,
        .frame_cb = update,
        .cleanup_cb = cleanup,
        .window_title = "Z Impact Game",
        .width = 1280,
        .height = 720,
    });
}
