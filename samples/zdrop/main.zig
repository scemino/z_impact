const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const zi = @import("zimpact");
const sgame = @import("scenes/game.zig");
const game = @import("game.zig");
const g = @import("global.zig");
const player = @import("entities/player.zig");

/// -----------------------------------------------------------------------------
/// Z Impact configuration
///
/// These defines are ALL optional. They overwrite the defaults set by
/// z_impact and configure aspects of the library
///
/// The values here (particularly resource limits) have been dialed in to this
/// particular game. Increase them as needed. Allocating a few GB and thousands
/// of entities is totally fine.
pub const zi_options = .{
    .ALLOC_SIZE = (2 * 1024 * 1024),
    .ALLOC_TEMP_OBJECTS_MAX = 8,
    .ENTITIES_MAX = 64,
    .ENTITY_TYPE = game.UEntity,
    .RENDER_RESIZE_MODE = zi.options.RENDER_RESIZE_NONE,
    .RENDER_SIZE = zi.vec2i(64, 96),
    .WINDOW_TITLE = "Z Drop",
    .WINDOW_SIZE = zi.vec2i(64, 96).muli(5),
};

fn init() void {
    // Keyboard
    zi.input.bind(.INPUT_KEY_LEFT, player.A_LEFT);
    zi.input.bind(.INPUT_KEY_RIGHT, player.A_RIGHT);
    zi.input.bind(.INPUT_KEY_RETURN, player.A_START);

    g.font = zi.font("assets/font_04b03.qoi", "assets/font_04b03.json");
    g.font.color = zi.rgba(75, 84, 0, 255);

    zi.Engine.setScene(&sgame.scene_game);
}

pub fn main() void {
    const vtabs = [_]zi.EntityVtab{
        game.coin.vtab,
        game.player.vtab,
    };

    zi.Engine.run(.{
        .vtabs = &vtabs,
        .init = init,
    });
}
