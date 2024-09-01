/// Every scene in your game must provide a Scene that specifies it's entry
/// functions.
pub const Scene = struct {
    /// Called once when the scene is set. Use it to load resources and
    /// instantiate your initial entities
    init: ?*const fn () void = null,

    /// Called once per frame. Uss this to update logic specific to your game.
    /// If you use this function, you probably want to call `sceneBaseUpdate()`
    /// in it somewhere.
    update: ?*const fn () void = null,

    /// Called once per frame. Use this to e.g. draw a background or hud.
    /// If you use this function, you probably want to call `sceneBaseDraw()`
    /// in it somewhere.
    draw: ?*const fn () void = null,

    /// Called once before the next scene is set or the game ends
    cleanup: ?*const fn () void = null,
};
