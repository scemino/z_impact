const std = @import("std");
const sokol = @import("sokol");
const sapp = sokol.app;
const Engine = @import("engine.zig").Engine;
const render = @import("render.zig");
const types = @import("types.zig");
const vec2 = types.vec2;
const stm = @import("sokol").time;
const Map = @import("map.zig").Map;
const entity = @import("entity.zig");
const title = @import("scenes/title.zig");
const game = @import("game.zig");
const EntityVtab = @import("entity.zig").EntityVtab;

var map: Map = undefined;
var blob_entity: game.Entity = undefined;
var player_entity: game.Entity = undefined;

const engine = Engine(game.Entity, game.EntityKind);
var vtabs: [@typeInfo(game.EntityKind).Enum.fields.len]EntityVtab(game.Entity) = undefined;

export fn init() void {
    stm.setup();

    vtabs = [_]EntityVtab(game.Entity){
        game.blob.vtab,
        game.player.vtab,
    };
    engine.init(&vtabs);
    engine.setScene(&title.scene_title);
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
        .window_title = "Z Impact Game",
        .width = 1280,
        .height = 720,
    });
}
