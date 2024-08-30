const std = @import("std");
const assert = std.debug.assert;
const Vec2 = @import("types.zig").Vec2;
const Vec2i = @import("types.zig").Vec2i;
const vec2 = @import("types.zig").vec2;
const types = @import("types.zig");
const Rgba = @import("types.zig").Rgba;
const alloc = @import("allocator.zig");
const img = @import("image.zig");
const texture = @import("texture.zig");
const platform = @import("platform.zig");
const ett = @import("entity.zig");
const anim = @import("anim.zig");
const EntityRef = ett.EntityRef;
const EntityList = ett.EntityList;
const Entity = ett.Entity;
const EntityVtab = ett.EntityVtab;
const entityRefNone = ett.entityRefNone;
const trace = @import("trace.zig").trace;
const render = @import("render.zig");
const ziscene = @import("scene.zig");
const Scene = ziscene.Scene;
const input = @import("input.zig");
const Map = @import("map.zig").Map;
const Trace = @import("trace.zig").Trace;
const snd = @import("sound.zig");
const options = @import("options.zig").options;
const ObjectMap = std.json.ObjectMap;

/// Various infos about the last frame
const Perf = struct {
    entities: usize,
    checks: usize,
    draw_calls: usize,
    update: f32,
    draw: f32,
    total: f32,
};

const EntitySettings = struct {
    entity: *Entity,
    settings: ObjectMap,
};

const Desc = struct {
    vtabs: []const EntityVtab,
    init: ?*const fn () void = null,
};

/// The game time in seconds since scene start
pub var time: f64 = 0.0;

/// A global multiplier for how fast game time should advance. Default: 1.0
var time_scale: f64 = 1.0;

/// The time difference in seconds from the last frame to the current.
/// Typically 0.01666 (assuming 60hz)
pub var tick: f64 = 0;

/// The frame number in this current scene. Increases by 1 for every frame.
var frame: u64 = 0;

/// The map to use for entity vs. world collisions. Reset for each scene.
/// Use engine_set_collision_map() to set it.
pub var collision_map: ?*Map = null;

/// The maps to draw. Reset for each scene. Use engine_add_background_map()
/// to add.
pub var background_maps: [options.ENGINE_MAX_BACKGROUND_MAPS]?*Map = [1]?*Map{null} ** options.ENGINE_MAX_BACKGROUND_MAPS;
var background_maps_len: u32 = 0;

/// The top left corner of the viewport. Internally just an offset when
/// drawing background_maps and entities.
pub var viewport: Vec2 = .{ .x = 0, .y = 0 };

/// A global multiplier that affects the gravity of all entities. This only
/// makes sense for side view games. For a top-down game you'd want to have
/// it at 0.0. Default: 1.0
pub var gravity: f32 = 1.0;

/// The real time in seconds since program start
pub var time_real: f64 = 0.0;

pub var perf: Perf = undefined;
var scene: ?*const Scene = null;
var scene_next: ?*const Scene = null;
var init_textures_mark: texture.TextureMark = .{};
var init_images_mark: img.ImageMark = .{};
var init_bump_mark: alloc.BumpMark = .{};
var init_sounds_mark: snd.SoundMark = .{};
pub var is_running = false;

pub var entity_vtab: []const EntityVtab = undefined;
pub var entities: [options.ENTITIES_MAX]*Entity = undefined;
pub var entities_storage: [options.ENTITIES_MAX]Entity = undefined;
pub var entities_len: usize = 0;
pub var entity_unique_id: u16 = 0;

/// The engine is the main wrapper around your. For every frame, it will update
/// your scene, update all entities and draw the whole frame.
/// The engine takes care of timekeeping, a number background maps, a collision
/// map some more global state. There's only one engine_t instance in high_impact
/// and it's globally available at `engine`
pub const Engine = struct {
    const Self = @This();

    var main_init: ?*const fn () void = null;

    pub fn run(desc: Desc) void {
        entity_vtab = desc.vtabs;
        main_init = desc.init;
        platform.run(.{
            .init_cb = engineInit,
            .cleanup_cb = cleanup,
            .update_cb = update,
        });
    }

    fn engineInit() void {
        time_real = platform.now();
        renderInit(platform.screenSize());
        snd.init(platform.samplerate());
        platform.setAudioMixCb(snd.mixStereo);
        // input_init();
        ett.entitiesInit(entity_vtab);
        if (main_init) |i| i();

        init_bump_mark = alloc.bumpMark();
        init_images_mark = img.imagesMark();
        init_sounds_mark = snd.mark();
        init_textures_mark = texture.texturesMark();
    }

    pub fn update() void {
        const time_frame_start = platform.now();

        // Do we want to switch scenes?
        if (scene_next) |scene_n| {
            is_running = false;
            if (scene) |scn| {
                if (scn.cleanup) |cb|
                    cb();
            }

            texture.texturesReset(init_textures_mark);
            img.imagesReset(init_images_mark);
            snd.reset(init_sounds_mark);
            alloc.bumpReset(init_bump_mark);
            ett.entitiesReset();

            background_maps_len = 0;
            collision_map = null;
            time = 0;
            frame = 0;
            viewport = vec2(0, 0);

            scene = scene_n;
            if (scene) |scn| {
                if (scn.init) |cb|
                    cb();
            }
            scene_next = null;
        }
        is_running = true;

        const time_real_now = platform.now();
        const real_delta = time_real_now - time_real;
        time_real = time_real_now;

        tick = @min(real_delta * time_scale, options.ENGINE_MAX_TICK);
        // std.log.info("tick: {}", .{tick});
        time += tick;
        frame += 1;

        var mark = alloc.bumpMark();
        while (mark.index != 0xFFFFFFFF) {
            if (scene) |scn| {
                if (scn.update) |cb|
                    cb();
            } else {
                sceneBaseUpdate();
            }

            perf.update = @floatCast(platform.now() - time_real_now);

            render.framePrepare();

            if (scene) |scn| {
                if (scn.draw) |cb|
                    cb();
            } else {
                sceneBaseDraw();
            }

            render.frameEnd();
            perf.draw = @as(f32, @floatCast(platform.now() - time_real_now)) - perf.update;
            alloc.bumpReset(mark);
            mark.index = 0xFFFFFFFF;
        }

        input.clear();
        alloc.tempAllocCheck();

        // perf.draw_calls = render.drawCalls();
        perf.total = @floatCast(platform.now() - time_frame_start);
    }

    pub fn cleanup() void {
        ett.entitiesCleanup();
        // main_cleanup();
        // input_cleanup();
        snd.cleanup();
        render.cleanup();
    }

    /// Whether the game is running or we are in a loading phase (i.e. when swapping
    /// scenes)
    pub fn isRunning() bool {
        return is_running;
    }

    /// Draw all background maps and entities
    pub fn sceneBaseDraw() void {
        const px_viewport = render.snapPx(viewport);

        // Background maps
        for (background_maps[0..background_maps_len]) |map| {
            if (map) |m| {
                if (!m.foreground) {
                    m.draw(px_viewport);
                }
            }
        }

        ett.entitiesDraw(px_viewport);

        // Foreground maps
        for (background_maps[0..background_maps_len]) |map| {
            if (map) |m| {
                if (m.foreground) {
                    m.draw(px_viewport);
                }
            }
        }
    }

    /// Update all entities
    pub fn sceneBaseUpdate() void {
        ett.entitiesUpdate();
    }

    fn renderInit(avaiable_size: Vec2i) void {
        render.init();
        render.resize(avaiable_size);
    }

    /// Add a background map; typically done through engine_load_level()
    pub fn addBackgroundMap(map: *Map) void {
        assert(background_maps_len < options.ENGINE_MAX_BACKGROUND_MAPS); // "BACKGROUND_MAPS_MAX reached"
        background_maps[background_maps_len] = map;
        background_maps_len += 1;
    }

    /// Set the collision map; typically done through engine_load_level()
    pub fn setCollisionMap(map: *Map) void {
        collision_map = map;
    }

    /// Load a level (background maps, collision map and entities) from a json path.
    /// This should only be called from within your scenes init() function.
    pub fn loadLevel(json_path: []const u8) void {
        var ba = alloc.BumpAllocator{};
        const json = platform.loadAssetJson(json_path, ba.allocator());
        defer json.deinit();

        ett.entitiesReset();
        background_maps_len = 0;
        collision_map = null;

        const maps = json.value.object.get("maps");
        for (maps.?.array.items) |map_def| {
            const name = map_def.object.get("name").?.string;
            const map = Map.initFromJson(map_def);

            if (std.mem.eql(u8, name, "collision")) {
                collision_map = map;
            } else {
                addBackgroundMap(map);
            }
        }

        const etts = json.value.object.get("entities");

        // Remember all entities with settings; we want to apply these settings
        // only after all entities have been spawned.
        // FIXME: we do this on the stack. Should maybe use the temp alloc instead.
        var entity_settings = ba.allocator().alloc(EntitySettings, entities.len) catch @panic("error when allcoating settings");
        var entity_settings_len: usize = 0;

        for (etts.?.array.items) |def| {
            const type_name = def.object.get("type").?.string;
            assert(type_name.len > 0); // "Entity has no type"

            const kind_type = std.meta.Tag(options.ENTITY_TYPE);
            const kind = std.meta.stringToEnum(kind_type, type_name);
            if (kind == null) {
                std.log.warn("Entity {s} not found", .{type_name});
                continue;
            }

            const pos = vec2(@as(f32, @floatFromInt(def.object.get("x").?.integer)), @as(f32, @floatFromInt(def.object.get("y").?.integer)));

            if (ett.spawnByTypeName(kind_type, kind.?, pos)) |ent| {
                const settings = def.object.get("settings");
                if (settings) |s| {
                    switch (s) {
                        .object => |obj| {
                            // Copy name, if we have one
                            if (obj.get("name")) |name| {
                                ent.name = name.string;
                            }
                            entity_settings[entity_settings_len].entity = ent;
                            entity_settings[entity_settings_len].settings = obj;
                            entity_settings_len += 1;
                        },
                        else => {},
                    }
                }
            }
        }

        for (entity_settings[0..entity_settings_len]) |*settings| {
            ett.entitySettings(settings.entity, settings.settings);
        }
    }

    /// Makes the scene_the current scene. This calls scene.cleanup() on the old
    /// scene and scene.init() on the new one. The actual swap of scenes happens
    /// at the beginning of the next frame, so it's ok to call engine_set_scene()
    /// from the middle of a frame.
    /// Your main_init() function must call engine_set_scene() to set first scene.
    pub fn setScene(s: *const Scene) void {
        scene_next = s;
    }
};
