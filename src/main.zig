const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const Engine = @import("Engine.zig");
const Image = @import("image.zig").Image;

var img_biolab: Image = undefined;

export fn init() void {
    Engine.init();
    img_biolab = Image.init("assets/title-biolab.qoi") catch @panic("failed to init image");
}

export fn update() void {
    Engine.framePrepare();
    img_biolab.draw(.{ .x = 16.0, .y = 16.0 });
    Engine.update();
}

export fn cleanup() void {
    Engine.cleanup();
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
