const std = @import("std");
const assert = std.debug.assert;
const sokol = @import("sokol");
const sapp = sokol.app;
const sg = sokol.gfx;
const sgl = sokol.gl;
const slog = sokol.log;
const sglue = sokol.glue;
const Vec2 = @import("types.zig").Vec2;
const vec2 = @import("types.zig").vec2;
const shaders = @import("shaders.zig");
const types = @import("types.zig");
const Rgba = @import("types.zig").Rgba;
const alloc = @import("allocator.zig");
const img = @import("image.zig");
const texture = @import("texture.zig");
const platform = @import("platform.zig");
const EntityVtab = @import("entity.zig").EntityVtab;

// The maximum difference in seconds from one frame to the next. If the
// difference  is larger than this, the game will slow down instead of having
// imprecise large time steps.
const ENGINE_MAX_TICK = 0.1;
const ENTITIES_MAX = 1024;

// Every scene in your game must provide a scene_t that specifies it's entry
// functions.
const Scene = struct {
    // Called once when the scene is set. Use it to load resources and
    // instaiate your initial entities
    init: *const fn () void,

    // Called once per frame. Uss this to update logic specific to your game.
    // If you use this function, you probably want to call scene_base_update()
    // in it somewhere.
    update: *const fn () void,

    // Called once per frame. Use this to e.g. draw a background or hud.
    // If you use this function, you probably want to call scene_base_draw()
    // in it somewhere.
    draw: *const fn () void,

    // Called once before the next scene is set or the game ends
    cleanup: *const fn () void,
};

// The engine is the main wrapper around your. For every frame, it will update
// your scene, update all entities and draw the whole frame.

// The engine takes care of timekeeping, a number background maps, a collision
// map some more global state. There's only one engine_t instance in high_impact
// and it's globally available at `engine`

/// The real time in seconds since program start
var time_real: f64 = 0.0;

/// The game time in seconds since scene start
pub var time: f64 = 0.0;

// A global multiplier for how fast game time should advance. Default: 1.0
var time_scale: f64 = 1.0;

// The time difference in seconds from the last frame to the current.
// Typically 0.01666 (assuming 60hz)
var tick: f64 = 0;

// The frame number in this current scene. Increases by 1 for every frame.
var frame: u64 = 0;

/// The map to use for entity vs. world collisions. Reset for each scene.
/// Use engine_set_collision_map() to set it.
// map_t *collision_map,

// The maps to draw. Reset for each scene. Use engine_add_background_map()
// to add.
// map_t *background_maps[ENGINE_MAX_BACKGROUND_MAPS];
// uint32_t background_maps_len;

// A global multiplier that affects the gravity of all entities. This only
// makes sense for side view games. For a top-down game you'd want to have
// it at 0.0. Default: 1.0
var gravity: f32 = 1.0;

// The top left corner of the viewport. Internally just an offset when
// drawing background_maps and entities.
var viewport: Vec2 = .{};

// var pip: sgl.Pipeline = .{};
var pass_action: sg.PassAction = .{};

// Various infos about the last frame
// struct {
// 	int entities;
// 	int checks;
// 	int draw_calls;
// 	float update;
// 	float draw;
// 	float total;
// } perf;

var scene_next: *Scene = null;
var init_textures_mark: texture.TextureMark = .{};
var init_images_mark: img.ImageMark = .{};
var init_bump_mark: alloc.BumpMark = .{};
// var init_sounds_mark: sound_mark_t = {};
var is_running = false;

pub fn Engine(comptime T: type) type {
    return struct {
        var entity_vtab: []const EntityVtab(T) = undefined;
        var entities: [ENTITIES_MAX]T = undefined;
        var entities_len: usize = 0;
        var entity_unique_id: u16 = 0;

        // const Self = @This();

        pub fn init(vtabs: []const EntityVtab(T)) void {
            time_real = platform.now();
            // render_init(platform.screen_size());
            renderInit();
            // sound_init(platform.samplerate());
            // platform_set_audio_mix_cb(sound_mix_stereo);
            // input_init();
            initEntities(vtabs);
            // main_init();

            init_bump_mark = alloc.bumpMark();
            init_images_mark = img.imagesMark();
            // init_sounds_mark = sound_mark();
            init_textures_mark = texture.texturesMark();
        }

        pub fn update() void {
            draw();
            const time_real_now = platform.now();
            const real_delta = time_real_now - time_real;
            time_real = time_real_now;

            tick = @min(real_delta * time_scale, ENGINE_MAX_TICK);
            // std.log.info("tick: {}", .{tick});
            time += tick;
        }

        pub fn cleanup() void {
            // entities_cleanup();
            // main_cleanup();
            // input_cleanup();
            // sound_cleanup();
            renderCleanup();
        }

        // Makes the scene_the current scene. This calls scene->cleanup() on the old
        // scene and scene->init() on the new one. The actual swap of scenes happens
        // at the beginning of the next frame, so it's ok to call engine_set_scene()
        // from the middle of a frame.
        // Your main_init() function must call engine_set_scene() to set first scene.
        pub fn setScene(scene: *Scene) void {
            scene_next = scene;
        }

        fn renderCleanup() void {
            sgl.shutdown();
            sg.shutdown();
        }

        fn renderInit() void {
            sg.setup(.{
                .environment = sglue.environment(),
                .logger = .{ .func = slog.func },
            });

            // setup sokol-gl
            sgl.setup(.{ .logger = .{ .func = slog.func } });

            // default pass action
            pass_action.colors[0] = .{
                .load_action = sg.LoadAction.CLEAR,
                .clear_value = .{ .r = 0.0, .g = 0.0, .b = 0.0, .a = 1.0 },
            };
        }

        fn draw() void {
            sg.beginPass(.{ .action = pass_action, .swapchain = sglue.swapchain() });
            sgl.draw();
            sg.endPass();
            sg.commit();
        }

        fn initEntities(vtabs: []const EntityVtab(T)) void {
            entity_vtab = vtabs;
            for (0..entity_vtab.len) |i| {
                const value = entity_vtab[i];
                if (value.load) |load| {
                    load();
                }
            }
        }

        pub fn initEntity(entity: *T) void {
            vtab(entity.kind).init.?(entity);
        }

        pub fn drawEntity(entity: *T, vp: Vec2) void {
            vtab(entity.kind).draw.?(entity, vp);
        }

        pub fn spawn(kind: anytype, pos: Vec2) T {
            const ent = &entities[entities_len];
            entities_len += 1;
            entity_unique_id += 1;
            ent.* = T{
                .base = .{
                    .id = entity_unique_id,
                    .is_alive = true,
                    .pos = pos,
                    .max_ground_normal = 0.69, // cosf(to_radians(46)),
                    .min_slide_normal = 1, // cosf(to_radians(0)),
                    .gravity = 1,
                    .mass = 1,
                    .size = vec2(8, 8),
                },
                .kind = kind,
                .entity = undefined,
            };

            initEntity(ent);
            return ent.*;
        }

        fn vtab(kind: anytype) EntityVtab(T) {
            return entity_vtab[@intFromEnum(kind)];
        }
    };
}
