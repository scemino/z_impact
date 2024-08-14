const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const Engine = @import("engine.zig").Engine;
const render = @import("render.zig");
const types = @import("types.zig");
const rgba = types.rgba;
const vec2 = types.vec2;
const stm = @import("sokol").time;
const Map = @import("map.zig").Map;
const entity = @import("entity.zig");
const sgame = @import("scenes/game.zig");
const game = @import("game.zig");
const input = @import("input.zig");
const g = @import("global.zig");
const Font = @import("font.zig").Font;
const platform = @import("platform.zig");
const font = @import("font.zig").font;
const player = @import("entities/player.zig");
const EntityVtab = @import("entity.zig").EntityVtab;

var map: Map = undefined;
var blob_entity: game.Entity = undefined;
var player_entity: game.Entity = undefined;

const engine = Engine(game.Entity, game.EntityKind);
var vtabs: [@typeInfo(game.EntityKind).Enum.fields.len]EntityVtab(game.Entity) = undefined;

export fn init() void {
    stm.setup();

    vtabs = [_]EntityVtab(game.Entity){
        game.coin.vtab,
        game.player.vtab,
    };
    engine.init(&vtabs);

    // Keyboard
    input.bind(.INPUT_KEY_LEFT, player.A_LEFT);
    input.bind(.INPUT_KEY_RIGHT, player.A_RIGHT);
    input.bind(.INPUT_KEY_RETURN, player.A_START);

    g.font = font("assets/font_04b03.qoi", "assets/font_04b03.json");
    g.font.color = rgba(75, 84, 0, 255);

    engine.setScene(&sgame.scene_game);
}

export fn update() void {
    render.framePrepare();
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
        .event_cb = &platform.platform_handle_event,
        .window_title = "Z Impact Game",
        .width = render.RENDER_WIDTH * 5,
        .height = render.RENDER_HEIGHT * 5,
    });
}
