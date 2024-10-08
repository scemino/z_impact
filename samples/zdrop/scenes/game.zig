const std = @import("std");
const zi = @import("zimpact");
const game = @import("../game.zig");
const g = @import("../global.zig");
const p = @import("../entities/player.zig");
const Entity = zi.Entity;

var map: zi.Map = undefined;
var game_over: bool = false;
var player: *Entity = undefined;
var sound_game_over: *zi.sound.SoundSource = undefined;
var backdrop: *zi.Image = undefined;

fn generate_row(row: usize) void {
    // Randomly generate a row of block for the map. This is a naive approach,
    // that sometimes leaves the player hanging with no block to jump to. It's
    // random after all.
    for (0..8) |col| {
        const f = zi.utils.randFloat(0, 1);
        map.data[row * @as(usize, @intCast(map.size.x)) + col] = if (f > 0.93) 1 else 0;
    }
}

fn place_coin(row: i32) void {
    // Randomly find a free spot for the coin, max 12 tries
    for (0..12 * 2) |_| {
        const x = zi.utils.randInt(0, 7);
        if (map.tileAt(zi.vec2i(x, row - 1)) == 1 and map.tileAt(zi.vec2i(x, row - 2)) == 0) {
            const pos = zi.vec2(
                @floatFromInt(x * map.tile_size + 1),
                @floatFromInt((row - 2) * map.tile_size + 2),
            );
            _ = zi.entity.entitySpawn(.coin, pos);
            return;
        }
    }
}

fn init() void {
    zi.utils.randSeed(@intFromFloat(zi.engine.time_real * 10000000.0));

    zi.engine.gravity = 240;
    g.score = 0;
    g.speed = 1;
    game_over = false;
    backdrop = zi.image("assets/backdrop.qoi");
    sound_game_over = zi.sound.source("assets/game_over.qoa");

    map = zi.Map.initWithData(8, zi.vec2i(8, 18), null);
    map.tileset = zi.image("assets/tiles.qoi");
    map.data[@intCast(4 * map.size.x + 3)] = 1;
    map.data[@intCast(4 * map.size.x + 4)] = 1;
    for (8..@intCast(map.size.y)) |i| {
        generate_row(i);
    }

    // The map is used as CollisionMap AND BackgroundMap
    zi.Engine.setCollisionMap(&map);
    zi.Engine.addBackgroundMap(&map);

    player = zi.entity.entitySpawn(.player, zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) / 2.0 - 2.0, 16)).?;
}

fn update() void {
    if (zi.input.pressed(p.A_START))
        zi.Engine.setScene(&scene_game);

    if (game_over)
        return;

    g.speed += @as(f32, @floatCast(zi.engine.tick)) * (10.0 / g.speed);
    g.score += @as(f32, @floatCast(zi.engine.tick)) * g.speed;
    zi.engine.viewport.y += @as(f32, @floatCast(zi.engine.tick)) * g.speed;

    // Do we need a new row?
    if (zi.engine.viewport.y > 40) {

        // Move screen and entities one tile up
        zi.engine.viewport.y -= 8;
        player.pos.y -= 8;
        const coins = zi.entity.entitiesByType(.coin);
        for (coins.entities) |coin| {
            const entity = zi.entity.entityByRef(coin);
            entity.?.pos.y -= 8;
        }

        // Move all tiles up one row
        std.mem.copyForwards(u16, map.data[0..@intCast((map.size.y - 1) * map.size.x)], map.data[@intCast(map.size.x)..@intCast(map.size.y * map.size.x)]);

        // Generate new last row
        generate_row(@intCast(map.size.y - 1));
        if (zi.utils.randInt(0, 1) == 1) {
            place_coin(@intCast(map.size.y - 1));
        }
    }

    zi.Engine.sceneBaseUpdate();

    // Check for gameover
    const pp = player.pos.y - zi.engine.viewport.y;
    if (pp > @as(f32, @floatFromInt(zi.render.renderSize().y)) + 8.0 or pp < -32) {
        game_over = true;
        zi.sound.play(sound_game_over);
    }
}

fn draw() void {
    backdrop.drawEx(zi.vec2(0, 0), zi.fromVec2i(backdrop.size), zi.vec2(0, 0), zi.fromVec2i(zi.render.renderSize()), zi.white());

    if (game_over) {
        g.font.draw(zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) / 2.0, 32.0), "Game Over!", .FONT_ALIGN_CENTER);
        g.font.draw(zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) / 2.0, 48.0), "Press Enter", .FONT_ALIGN_CENTER);
        g.font.draw(zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) / 2.0, 56.0), "to Restart", .FONT_ALIGN_CENTER);
    } else {
        zi.Engine.sceneBaseDraw();
    }

    var buf: [64]u8 = undefined;
    const text = std.fmt.bufPrint(&buf, "{d}", .{@as(i32, @intFromFloat(g.score))}) catch @panic("failed to format score");
    g.font.draw(zi.vec2(@as(f32, @floatFromInt(zi.render.renderSize().x)) - 2.0, 2.0), text, .FONT_ALIGN_RIGHT);
}

pub var scene_game: zi.Scene = .{
    .init = init,
    .update = update,
    .draw = draw,
};
