const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const stm = sokol.time;
const zi = @import("zimpact");
const Engine = zi.Engine;
const render = zi.render;
const rgba = zi.rgba;
const Map = zi.Map;
const entity = zi.entity;
const font = zi.font;
const input = zi.input;
const EntityVtab = zi.EntityVtab;
const platform = zi.platform;
const vec2i = zi.vec2i;

const sgame = @import("scenes/game.zig");
const game = @import("game.zig");
const g = @import("global.zig");
const player = @import("entities/player.zig");

const engine = Engine(game.Entity, game.EntityKind);
var vtabs: [@typeInfo(game.EntityKind).Enum.fields.len]EntityVtab(game.Entity) = undefined;

fn main_init() void {
    // Keyboard
    input.bind(.INPUT_KEY_LEFT, player.A_LEFT);
    input.bind(.INPUT_KEY_RIGHT, player.A_RIGHT);
    input.bind(.INPUT_KEY_RETURN, player.A_START);

    g.font = font("assets/font_04b03.qoi", "assets/font_04b03.json");
    g.font.color = rgba(75, 84, 0, 255);

    engine.setScene(&sgame.scene_game);
}

export fn init() void {
    stm.setup();

    vtabs = [_]EntityVtab(game.Entity){
        game.coin.vtab,
        game.player.vtab,
    };
    engine.init(.{
        .vtabs = &vtabs,
        .render_size = vec2i(64, 96),
        .main_init = main_init,
    });
}

export fn update() void {
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
        .event_cb = &platform.platformHandleEvent,
        .window_title = "Z Drop",
        .width = 64 * 5,
        .height = 96 * 5,
    });
}
