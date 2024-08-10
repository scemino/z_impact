const render = @import("render.zig");
const engine = @import("engine.zig");

pub const Scene = struct {
    /// Called once when the scene is set. Use it to load resources and
    /// instantiate your initial entities
    init: ?*const fn () void = null,

    /// Called once per frame. Uss this to update logic specific to your game.
    /// If you use this function, you probably want to call scene_base_update()
    /// in it somewhere.
    update: ?*const fn () void = null,

    /// Called once per frame. Use this to e.g. draw a background or hud.
    /// If you use this function, you probably want to call scene_base_draw()
    /// in it somewhere.
    draw: ?*const fn () void = null,

    /// Called once before the next scene is set or the game ends
    cleanup: ?*const fn () void = null,
};

pub fn baseDraw() void {
    const px_viewport = render.snapPx(engine.viewport);

    // Background maps
    for (engine.background_maps) |map| {
        if (!map.foreground) {
            map.draw(px_viewport);
        }
    }

    // TODO: entities.draw(px_viewport);

    // Foreground maps
    for (engine.background_maps) |map| {
        if (!map.foreground) {
            map.draw(px_viewport);
        }
    }
}
