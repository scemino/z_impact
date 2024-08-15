const std = @import("std");
const Scene = @import("../scene.zig").Scene;
const img = @import("../image.zig");
const Image = @import("../image.zig").Image;
const Map = @import("../map.zig").Map;
const Font = @import("../font.zig").Font;
const font = @import("../font.zig").font;
const game = @import("../game.zig");
const types = @import("../types.zig");
const rgba = types.rgba;
const vec2 = types.vec2;
const vec2i = types.vec2i;
const Rgba = types.Rgba;
const Entity = game.Entity;
const ziengine = @import("../engine.zig");
const render = @import("../render.zig");
const utils = @import("../utils.zig");
const g = @import("../global.zig");
const input = @import("../input.zig");
const p = @import("../entities/player.zig");
const Engine = @import("../engine.zig").Engine;
const engine = Engine(game.Entity, game.EntityKind);

var map: Map = undefined;
var game_over: bool = false;
var player: *Entity = undefined;
// sound_source_t *sound_game_over;
var backdrop: *Image = undefined;

fn generate_row(row: usize) void {
    // Randomly generate a row of block for the map. This is a naive approach,
    // that sometimes leaves the player hanging with no block to jump to. It's
    // random after all.
    for (0..8) |col| {
        const f = utils.rand_float(0, 1);
        map.data[row * @as(usize, @intCast(map.size.x)) + col] = if (f > 0.93) 1 else 0;
    }
}

fn place_coin(row: i32) void {
    // Randomly find a free spot for the coin, max 12 tries
    for (0..12 * 2) |_| {
        const x = utils.rand_int(0, 7);
        if (map.tileAt(vec2i(x, row - 1)) == 1 and map.tileAt(vec2i(x, row - 2)) == 0) {
            const pos = vec2(
                @floatFromInt(x * map.tile_size + 1),
                @floatFromInt((row - 2) * map.tile_size + 2),
            );
            _ = engine.spawn(.coin, pos);
            return;
        }
    }
}

fn init() void {
    utils.rand_seed(@intFromFloat(engine.time_real * 10000000.0));

    engine.gravity = 240;
    g.score = 0;
    g.speed = 1;
    game_over = false;
    backdrop = Image.init("assets/backdrop.qoi") catch @panic("failed to init image");
    // sound_game_over = sound_source("assets/game_over.qoa");

    map = Map.initWithData(8, vec2i(8, 18), null);
    map.tileset = Image.init("assets/tiles.qoi") catch @panic("failed to init image");
    map.data[@intCast(4 * map.size.x + 3)] = 1;
    map.data[@intCast(4 * map.size.x + 4)] = 1;
    for (8..@intCast(map.size.y)) |i| {
        generate_row(i);
    }

    // The map is used as CollisionMap AND BackgroundMap
    engine.setCollisionMap(&map);
    engine.addBackgroundMap(&map);

    player = engine.spawn(.player, vec2(@as(f32, @floatFromInt(render.renderSize().x)) / 2.0 - 2.0, 16));

    g.font = font("assets/font_04b03.qoi", "assets/font_04b03.json");
    g.font.color = rgba(75, 84, 0, 255);
}

fn update() void {
    if (input.pressed(p.A_START))
        engine.setScene(&scene_game);

    if (game_over)
        return;

    g.speed += @as(f32, @floatCast(ziengine.tick)) * (10.0 / g.speed);
    g.score += @as(f32, @floatCast(ziengine.tick)) * g.speed;
    ziengine.viewport.y += @as(f32, @floatCast(ziengine.tick)) * g.speed;

    // Do we need a new row?
    if (ziengine.viewport.y > 40) {

        // Move screen and entities one tile up
        ziengine.viewport.y -= 8;
        player.base.pos.y -= 8;
        const coins = engine.entitiesByType(.coin);
        for (coins.items) |coin| {
            const entity = engine.entityByRef(coin);
            entity.?.base.pos.y -= 8;
        }

        // Move all tiles up one row
        std.mem.copyForwards(u16, map.data[0..@intCast((map.size.y - 1) * map.size.x)], map.data[@intCast(map.size.x)..@intCast(map.size.y * map.size.x)]);

        // Generate new last row
        generate_row(@intCast(map.size.y - 1));
        if (utils.rand_int(0, 1) == 1) {
            place_coin(@intCast(map.size.y - 1));
        }
    }

    engine.sceneBaseUpdate();

    // Check for gameover
    const pp = player.base.pos.y - ziengine.viewport.y;
    if (pp > @as(f32, @floatFromInt(render.renderSize().y)) + 8.0 or pp < -32) {
        game_over = true;
        // sound_play(sound_game_over);
    }
}

fn draw() void {
    backdrop.drawEx(vec2(0, 0), types.fromVec2i(backdrop.size), vec2(0, 0), types.fromVec2i(render.renderSize()), types.white());

    if (game_over) {
        g.font.draw(vec2(@as(f32, @floatFromInt(render.renderSize().x)) / 2.0, 32.0), "Game Over!", .FONT_ALIGN_CENTER);
        g.font.draw(vec2(@as(f32, @floatFromInt(render.renderSize().x)) / 2.0, 48.0), "Press Enter", .FONT_ALIGN_CENTER);
        g.font.draw(vec2(@as(f32, @floatFromInt(render.renderSize().x)) / 2.0, 56.0), "to Restart", .FONT_ALIGN_CENTER);
    } else {
        engine.baseDraw();
    }

    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{@as(i32, @intFromFloat(g.score))}) catch @panic("failed to format score");
    g.font.draw(vec2(@as(f32, @floatFromInt(render.renderSize().x)) - 2.0, 2.0), text, .FONT_ALIGN_RIGHT);
}

pub var scene_game: Scene = .{
    .init = init,
    .update = update,
    .draw = draw,
};
