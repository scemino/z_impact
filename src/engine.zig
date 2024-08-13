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
const EntityRef = @import("entity.zig").EntityRef;
const EntityList = @import("entity.zig").EntityList;
const EntityGroup = @import("entity.zig").EntityGroup;
const entityRefNone = @import("entity.zig").entityRefNone;
const render = @import("render.zig");
const ziscene = @import("scene.zig");
const Scene = ziscene.Scene;
const Map = @import("map.zig").Map;
const ObjectMap = std.json.ObjectMap;

// The maximum difference in seconds from one frame to the next. If the
// difference  is larger than this, the game will slow down instead of having
// imprecise large time steps.
const ENGINE_MAX_TICK = 0.1;
const ENTITIES_MAX = 1024;
const ENGINE_MAX_BACKGROUND_MAPS = 4;

// The engine is the main wrapper around your. For every frame, it will update
// your scene, update all entities and draw the whole frame.

// The engine takes care of timekeeping, a number background maps, a collision
// map some more global state. There's only one engine_t instance in high_impact
// and it's globally available at `engine`

/// The game time in seconds since scene start
pub var time: f64 = 0.0;

// A global multiplier for how fast game time should advance. Default: 1.0
var time_scale: f64 = 1.0;

// The time difference in seconds from the last frame to the current.
// Typically 0.01666 (assuming 60hz)
pub var tick: f64 = 0;

// The frame number in this current scene. Increases by 1 for every frame.
var frame: u64 = 0;

/// The map to use for entity vs. world collisions. Reset for each scene.
/// Use engine_set_collision_map() to set it.
var collision_map: ?Map = null;

// The maps to draw. Reset for each scene. Use engine_add_background_map()
// to add.
pub var background_maps: [ENGINE_MAX_BACKGROUND_MAPS]?Map = [1]?Map{null} ** ENGINE_MAX_BACKGROUND_MAPS;
var background_maps_len: u32 = 0;

// The top left corner of the viewport. Internally just an offset when
// drawing background_maps and entities.
pub var viewport: Vec2 = .{ .x = 0, .y = 0 };

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

var scene: ?*Scene = null;
var scene_next: ?*Scene = null;
var init_textures_mark: texture.TextureMark = .{};
var init_images_mark: img.ImageMark = .{};
var init_bump_mark: alloc.BumpMark = .{};
// var init_sounds_mark: sound_mark_t = {};
pub var is_running = false;

pub fn Engine(comptime T: type, comptime TKind: type) type {
    return struct {
        // A global multiplier that affects the gravity of all entities. This only
        // makes sense for side view games. For a top-down game you'd want to have
        // it at 0.0. Default: 1.0
        pub var gravity: f32 = 1.0;

        /// The real time in seconds since program start
        pub var time_real: f64 = 0.0;
        var entity_vtab: []const EntityVtab(T) = undefined;
        var entities: [ENTITIES_MAX]T = undefined;
        var entities_storage: [ENTITIES_MAX]T = undefined;
        var entities_len: usize = 0;
        var entity_unique_id: u16 = 0;

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
            // const time_frame_start = platform.now();

            // Do we want to switch scenes?
            if (scene_next) |scene_n| {
                is_running = false;
                if (scene) |scn| {
                    if (scn.cleanup) |cb|
                        cb();
                }

                texture.texturesReset(init_textures_mark);
                img.imagesReset(init_images_mark);
                // sound.reset(init_sounds_mark);
                // bump.reset(init_bump_mark);
                // entities.reset();

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

            tick = @min(real_delta * time_scale, ENGINE_MAX_TICK);
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

                // perf.update = platform_now() - time_real_now;

                render.framePrepare();

                if (scene) |scn| {
                    if (scn.draw) |cb|
                        cb();
                } else {
                    baseDraw();
                }

                frameEnd();
                // engine.perf.draw = (platform_now() - time_real_now) - engine.perf.update;
                alloc.bumpReset(mark);
                mark.index = 0xFFFFFFFF;
            }

            // input.clear();
            // temp.alloc_check();

            // engine.perf.draw_calls = render_draw_calls();
            // engine.perf.total = platform_now() - time_frame_start;
        }

        pub fn cleanup() void {
            // entities_cleanup();
            // main_cleanup();
            // input_cleanup();
            // sound_cleanup();
            renderCleanup();
        }

        // Makes the scene_the current scene. This calls scene.cleanup() on the old
        // scene and scene.init() on the new one. The actual swap of scenes happens
        // at the beginning of the next frame, so it's ok to call engine_set_scene()
        // from the middle of a frame.
        // Your main_init() function must call engine_set_scene() to set first scene.
        pub fn setScene(s: *Scene) void {
            scene_next = s;
        }

        pub fn baseDraw() void {
            const px_viewport = render.snapPx(viewport);

            // Background maps
            for (background_maps) |map| {
                if (map) |m| {
                    if (!m.foreground) {
                        m.draw(px_viewport);
                    }
                }
            }

            entitiesDraw(px_viewport);

            // Foreground maps
            for (background_maps) |map| {
                if (map) |m| {
                    if (!m.foreground) {
                        m.draw(px_viewport);
                    }
                }
            }
        }

        pub fn entityBaseDraw(self: *T, vp: Vec2) void {
            if (self.base.anim.def != null) {
                self.base.anim.draw(Vec2.sub(Vec2.sub(self.base.pos, vp), self.base.offset));
            }
        }

        pub fn baseUpdate(self: *T) void {
            // if (!(self.physics & .ENTITY_PHYSICS_MOVE)) {
            //     return;
            // }

            // Integrate velocity
            const v = self.base.vel;

            self.base.vel.y = @floatCast(self.base.vel.y + gravity * self.base.gravity * tick);
            const friction = vec2(@min(@as(f32, @floatCast(self.base.friction.x * tick)), 1), @min(@as(f32, @floatCast(self.base.friction.y * tick)), 1));
            self.base.vel = Vec2.add(self.base.vel, Vec2.sub(Vec2.mulf(self.base.accel, @as(f32, @floatCast(tick))), Vec2.mul(self.base.vel, friction)));

            const vstep = Vec2.mulf(Vec2.add(v, self.base.vel), @as(f32, @floatCast(tick * 0.5)));
            self.base.on_ground = false;
            entity_move(self, vstep);
        }

        pub fn sceneBaseUpdate() void {
            updateEntities();
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

        fn frameEnd() void {
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

        fn updateEntities() void {
            // Update all entities
            var i: usize = 0;
            while (i < entities_len) {
                const ent = &entities[i];
                updateEntity(ent);

                if (!ent.base.is_alive) {
                    // If this entity is dead overwrite it with the last one and
                    // decrease count.
                    entities_len -= 1;
                    if (i < entities_len) {
                        const last = entities[entities_len];
                        entities[entities_len] = entities[i];
                        entities[i] = last;
                        i -= 1;
                    }
                }
                i += 1;
            }

            // Sort by x or y position - insertion sort
            std.sort.heap(T, &entities, {}, cmpEntityPos);

            // Sweep touches
            // engine.perf.checks = 0;
            i = 0;
            for (&entities) |*e1| {
                if (e1.base.check_against != .ENTITY_GROUP_NONE or
                    e1.base.group != .ENTITY_GROUP_NONE
                // or (e1.base.physics > .ENTITY_COLLIDES_LITE)
                ) {
                    const max_pos = e1.base.pos.x + e1.base.size.x;
                    var j: usize = i + 1;
                    while (j < entities_len and entities[j].base.pos.x < max_pos) {
                        const e2 = &entities[j];
                        // engine.perf.checks += 1;

                        if (entityIsTouching(e1, e2)) {
                            if (contains(e1.base.check_against, e2.base.group)) {
                                touchEntity(e1, e2);
                            }
                            if (contains(e1.base.group, e2.base.check_against)) {
                                touchEntity(e2, e1);
                            }

                            // if (e1.base.physics >= .ENTITY_COLLIDES_LITE and
                            //     e2.base.physics >= .ENTITY_COLLIDES_LITE and
                            //     (e1.base.physics + e2.base.physics) >= (.ENTITY_COLLIDES_ACTIVE | .ENTITY_COLLIDES_LITE) and
                            //     e1.base.mass + e2.base.mass > 0)
                            // {
                            //     entityResolveCollision(e1, e2);
                            // }
                        }
                        j += 1;
                    }
                }
                i += 1;
            }

            //engine.perf.entities = entities_len;
        }
        fn contains(g1: EntityGroup, g2: EntityGroup) bool {
            return (@intFromEnum(g1) & @intFromEnum(g2)) > 0;
        }

        fn cmpEntityPos(context: void, a: T, b: T) bool {
            _ = context;
            return a.base.pos.x > b.base.pos.x;
        }

        fn initEntity(entity: *T) void {
            vtab(entity.kind).init.?(entity);
        }

        fn updateEntity(entity: *T) void {
            vtab(entity.kind).update.?(entity);
        }

        pub fn drawEntity(entity: *T, vp: Vec2) void {
            vtab(entity.kind).draw.?(entity, vp);
        }

        fn touchEntity(e1: *T, e2: *T) void {
            vtab(e1.kind).touch.?(e1, e2);
        }

        pub fn killEntity(entity: *T) void {
            entity.base.is_alive = false;
            vtab(entity.kind).kill.?(entity);
        }

        fn settingsEntity(e: *T, settings: ObjectMap) void {
            _ = e;
            _ = settings;
            // vtab(e.kind).settings.?(e, settings);
        }

        fn collideEntity(e: *T, settings: ObjectMap) void {
            vtab(e.kind).collide.?(e, settings);
        }

        fn entityResolveCollision(a: *T, b: *T) void {
            const overlap_x = if (a.pos.x < b.pos.x) a.pos.x + a.size.x - b.pos.x else b.pos.x + b.size.x - a.pos.x;
            const overlap_y = if (a.pos.y < b.pos.y) a.pos.y + a.size.y - b.pos.y else b.pos.y + b.size.y - a.pos.y;
            var a_move: f32 = undefined;
            var b_move: f32 = undefined;
            if (a.physics & .ENTITY_COLLIDES_LITE or b.physics & .ENTITY_COLLIDES_FIXED) {
                a_move = 1;
                b_move = 0;
            } else if (a.physics & .ENTITY_COLLIDES_FIXED or b.physics & .ENTITY_COLLIDES_LITE) {
                a_move = 0;
                b_move = 1;
            } else {
                const total_mass = a.mass + b.mass;
                a_move = b.mass / total_mass;
                b_move = a.mass / total_mass;
            }

            if (overlap_y > overlap_x) {
                if (a.pos.x < b.pos.x) {
                    entities_separate_on_x_axis(a, b, a_move, b_move, overlap_x);
                    collideEntity(a, vec2(-1, 0), null);
                    collideEntity(b, vec2(1, 0), null);
                } else {
                    entities_separate_on_x_axis(b, a, b_move, a_move, overlap_x);
                    collideEntity(a, vec2(1, 0), null);
                    collideEntity(b, vec2(-1, 0), null);
                }
            } else {
                if (a.pos.y < b.pos.y) {
                    entities_separate_on_y_axis(a, b, a_move, b_move, overlap_y);
                    collideEntity(a, vec2(0, -1), null);
                    collideEntity(b, vec2(0, 1), null);
                } else {
                    entities_separate_on_y_axis(b, a, b_move, a_move, overlap_y);
                    collideEntity(a, vec2(0, 1), null);
                    collideEntity(b, vec2(0, -1), null);
                }
            }
        }

        fn entities_separate_on_x_axis(left: T, right: T, left_move: f32, right_move: f32, overlap: f32) void {
            const impact_velocity = left.vel.x - right.vel.x;

            if (left_move > 0) {
                left.vel.x = right.vel.x * left_move + left.vel.x * right_move;

                const bounce = impact_velocity * left.restitution;
                if (bounce > .ENTITY_MIN_BOUNCE_VELOCITY) {
                    left.vel.x -= bounce;
                }
                entity_move(left, vec2(-overlap * left_move, 0));
            }
            if (right_move > 0) {
                right.vel.x = left.vel.x * right_move + right.vel.x * left_move;

                const bounce = impact_velocity * right.restitution;
                if (bounce > .ENTITY_MIN_BOUNCE_VELOCITY) {
                    right.vel.x += bounce;
                }
                entity_move(right, vec2(overlap * right_move, 0));
            }
        }

        fn entities_separate_on_y_axis(top: T, bottom: T, top_move: f32, bottom_move: f32, overlap: f32) void {
            if (bottom.on_ground and top_move > 0) {
                top_move = 1;
                bottom_move = 0;
            }

            const impact_velocity = top.vel.y - bottom.vel.y;
            const top_vel_y = top.vel.y;

            if (top_move > 0) {
                top.vel.y = (top.vel.y * bottom_move + bottom.vel.y * top_move);

                const move_x = 0;
                const bounce = impact_velocity * top.restitution;
                if (bounce > .ENTITY_MIN_BOUNCE_VELOCITY) {
                    top.vel.y -= bounce;
                } else {
                    top.on_ground = true;
                    move_x = bottom.vel.x * tick;
                }
                entity_move(top, vec2(move_x, -overlap * top_move));
            }
            if (bottom_move > 0) {
                bottom.vel.y = bottom.vel.y * top_move + top_vel_y * bottom_move;

                const bounce = impact_velocity * bottom.restitution;
                if (bounce > .ENTITY_MIN_BOUNCE_VELOCITY) {
                    bottom.vel.y += bounce;
                }
                entity_move(bottom, vec2(0, overlap * bottom_move));
            }
        }

        fn entity_move(self: *T, vstep: Vec2) void {
            _ = self;
            _ = vstep;
        }

        fn entityRef(self: ?*T) EntityRef {
            if (self) |me| {
                return .{
                    .id = me.base.id,
                    .index = @intCast(@intFromPtr(me) - @intFromPtr(&entities_storage[0])),
                };
            }
            return entityRefNone();
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

        fn entityIsTouching(self: *T, other: *T) bool {
            return !(self.base.pos.x >= other.base.pos.x + other.base.size.x or
                self.base.pos.x + self.base.size.x <= other.base.pos.x or
                self.base.pos.y >= other.base.pos.y + other.base.size.y or
                self.base.pos.y + self.base.size.y <= other.base.pos.y);
        }

        pub fn entitiesByType(kind: TKind) std.ArrayList(EntityRef) {
            var ba = alloc.BumpAllocator{};
            var list = std.ArrayList(EntityRef).init(ba.allocator());
            // FIXME:PERF: linear search
            for (&entities) |*entity| {
                if (entity.kind == kind and entity.base.is_alive) {
                    list.append(entityRef(entity)) catch @panic("failed to append");
                }
            }

            return list;
        }

        pub fn entityByRef(ref: EntityRef) ?*T {
            const ent = &entities_storage[ref.index];
            if (ent.base.is_alive and ent.base.id == ref.id) {
                return ent;
            }

            return null;
        }

        fn entitiesDraw(vp: Vec2) void {
            // Sort entities by draw_order
            // FIXME: this copies the entity array - which is sorted by pos.x/y and
            // sorts it again by draw_order. It's using insertion sort, which is slow
            // for data that is not already mostly sorted.
            // TODO: var ba = alloc.BumpAllocator{};
            var ba = std.heap.GeneralPurposeAllocator(.{}){};
            const draw_ents = ba.allocator().alloc(T, entities_len) catch @panic("failed to alloc");
            @memcpy(draw_ents[0..], entities[0..entities_len]);

            std.sort.heap(T, draw_ents, {}, cmpEntity);

            for (0..entities_len) |i| {
                const ent = &draw_ents[i];
                drawEntity(ent, vp);
            }
        }

        fn cmpEntity(context: void, lhs: T, rhs: T) bool {
            _ = context;
            return lhs.base.draw_order > rhs.base.draw_order;
        }

        const EntitySettings = struct {
            entity: T,
            settings: ObjectMap,
        };

        /// Load a level (background maps, collision map and entities) from a json path.
        /// This should only be called from within your scenes init() function.
        pub fn loadLevel(json_path: []const u8) void {
            const root = platform.loadAssetJson(json_path);

            // entities.reset();
            background_maps_len = 0;
            collision_map = null;

            const maps = root.object.get("maps");
            for (maps.?.array.items) |map_def| {
                const name = map_def.object.get("name").?.string;
                const map = Map.initFromJson(map_def);

                if (std.mem.eql(u8, name, "collision")) {
                    collision_map = map;
                } else {
                    addBackgroundMap(map);
                }
            }

            const etts = root.object.get("entities");

            // Remember all entities with settings; we want to apply these settings
            // only after all entities have been spawned.
            // FIXME: we do this on the stack. Should maybe use the temp alloc instead.
            var gpa = std.heap.GeneralPurposeAllocator(.{}){};
            var entity_settings = gpa.allocator().alloc(EntitySettings, entities.len) catch @panic("error when allcoating settings");
            var entity_settings_len: usize = 0;

            for (etts.?.array.items) |def| {
                const type_name = def.object.get("type").?.string;
                assert(type_name.len > 0); // "Entity has no type"

                const kind = std.meta.stringToEnum(TKind, type_name);
                if (kind == null) continue;
                std.log.info("type_name: {s}, {?}", .{ type_name, kind });
                const pos = vec2(@as(f32, @floatFromInt(def.object.get("x").?.integer)), @as(f32, @floatFromInt(def.object.get("y").?.integer)));

                var ent = spawn(kind, pos);
                const settings = def.object.get("settings");
                if (settings) |s| {
                    switch (s) {
                        .object => |obj| {
                            // Copy name, if we have one
                            const name = obj.get("name").?.string;
                            ent.base.name = name;
                            entity_settings[entity_settings_len].entity = ent;
                            entity_settings[entity_settings_len].settings = obj;
                            entity_settings_len += 1;
                        },
                        else => {},
                    }
                }
            }

            for (entity_settings[0..entities.len]) |*settings| {
                settingsEntity(&settings.entity, settings.settings);
            }
            // temp_free(json);
        }

        pub fn addBackgroundMap(map: Map) void {
            assert(background_maps_len < ENGINE_MAX_BACKGROUND_MAPS); // "BACKGROUND_MAPS_MAX reached"
            background_maps[background_maps_len] = map;
            background_maps_len += 1;
        }
    };
}
