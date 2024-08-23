const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const zi = @import("zimpact");
const sgame = @import("scenes/game.zig");
const game = @import("game.zig");
const g = @import("global.zig");
const player = @import("entities/player.zig");

fn init() void {
    // Keyboard
    zi.input.bind(.INPUT_KEY_LEFT, player.A_LEFT);
    zi.input.bind(.INPUT_KEY_RIGHT, player.A_RIGHT);
    zi.input.bind(.INPUT_KEY_RETURN, player.A_START);

    g.font = zi.font("assets/font_04b03.qoi", "assets/font_04b03.json");
    g.font.color = zi.rgba(75, 84, 0, 255);

    game.Engine.setScene(&sgame.scene_game);
}

pub fn main() void {
    const vtabs = [_]game.EntityVtab{
        game.coin.vtab,
        game.player.vtab,
    };

    game.Engine.run(.{
        .vtabs = &vtabs,
        .window_title = "Z Drop",
        .render_size = zi.vec2i(64, 96),
        .window_size = zi.vec2i(64, 96).muli(5),
        .init = init,
    });
}
