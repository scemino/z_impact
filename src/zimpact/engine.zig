const std = @import("std");
const assert = std.debug.assert;
const Vec2 = @import("types.zig").Vec2;
const Vec2i = @import("types.zig").Vec2i;
const vec2 = @import("types.zig").vec2;
const shaders = @import("shaders.zig");
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
    render_size: Vec2i,
    init: ?*const fn () void = null,
    window_title: ?[:0]const u8 = null,
    window_size: Vec2i = types.vec2i(1280, 720),
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

var entity_vtab: []const EntityVtab = undefined;
var entities: [options.ENTITIES_MAX]*Entity = undefined;
var entities_storage: [options.ENTITIES_MAX]Entity = undefined;
var entities_len: usize = 0;
var entity_unique_id: u16 = 0;

/// The engine is the main wrapper around your. For every frame, it will update
/// your scene, update all entities and draw the whole frame.
/// The engine takes care of timekeeping, a number background maps, a collision
/// map some more global state. There's only one engine_t instance in high_impact
/// and it's globally available at `engine`
pub const Engine = struct {
    const Self = @This();

    var render_size: Vec2i = undefined;
    var main_init: ?*const fn () void = null;

    pub fn run(desc: Desc) void {
        std.log.info("Run with {} max entities", .{entities.len});
        entity_vtab = desc.vtabs;
        render_size = desc.render_size;
        main_init = desc.init;
        platform.run(.{
            .init_cb = engineInit,
            .cleanup_cb = cleanup,
            .update_cb = update,
            .window_title = desc.window_title,
            .window_size = desc.window_size,
        });
    }

    fn engineInit() void {
        time_real = platform.now();
        renderInit(platform.screenSize());
        snd.init(platform.samplerate());
        platform.setAudioMixCb(snd.mixStereo);
        // input_init();
        entitiesInit(entity_vtab);
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
            entitiesReset();

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
        entitiesCleanup();
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

    /// Updates the entity's position and velocity according to its physics. This
    /// also checks for collision against the game world. If you use update() in your
    /// vtab, you may still want to call this function.
    pub fn entityBaseUpdate(self: *Entity) void {
        if ((self.physics & ett.ENTITY_PHYSICS_MOVE) != ett.ENTITY_PHYSICS_MOVE)
            return;

        // Integrate velocity
        const v = self.vel;

        self.vel.y = @floatCast(self.vel.y + gravity * self.gravity * tick);
        const friction = vec2(@min(@as(f32, @floatCast(self.friction.x * tick)), 1), @min(@as(f32, @floatCast(self.friction.y * tick)), 1));
        self.vel = Vec2.add(self.vel, Vec2.sub(Vec2.mulf(self.accel, @as(f32, @floatCast(tick))), Vec2.mul(self.vel, friction)));

        const vstep = Vec2.mulf(Vec2.add(v, self.vel), @as(f32, @floatCast(tick * 0.5)));
        self.on_ground = false;
        entityMove(self, vstep);
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

        entitiesDraw(px_viewport);

        // Foreground maps
        for (background_maps[0..background_maps_len]) |map| {
            if (map) |m| {
                if (m.foreground) {
                    m.draw(px_viewport);
                }
            }
        }
    }

    /// Draws the entity.anim. If you use draw() in you vtab, you may still want to
    /// call this function.
    pub fn entityBaseDraw(self: *Entity, vp: Vec2) void {
        if (self.anim.def != null) {
            self.anim.draw(Vec2.sub(Vec2.sub(self.pos, vp), self.offset));
        }
    }

    /// Deduct damage from health; calls entityKill() when health <= 0. If you use
    /// damage() in your vtab, you may still want to call this function.
    pub fn entityBaseDamage(self: *Entity, _: *Entity, damage: f32) void {
        self.health -= damage;

        if (self.health <= 0 and self.is_alive) {
            entityKill(self);
        }
    }

    /// Update all entities
    pub fn sceneBaseUpdate() void {
        entitiesUpdate();
    }

    fn renderInit(avaiable_size: Vec2i) void {
        render.init(render_size);
        render.resize(avaiable_size);
    }

    fn contains(g1: u8, g2: u8) bool {
        return (g1 & g2) != 0;
    }

    fn cmpEntityPos(context: void, a: *Entity, b: *Entity) bool {
        _ = context;
        return a.pos.x <= b.pos.x;
    }

    // Functions to call the correct function on each entity according to the vtab.
    fn entityInit(entity: *Entity) void {
        vtab(entity).init(entity);
    }

    fn entitySettings(e: *Entity, value: ObjectMap) void {
        vtab(e).settings(e, value);
    }

    fn entityUpdate(entity: *Entity) void {
        vtab(entity).update(entity);
    }

    pub fn entityDraw(entity: *Entity, vp: Vec2) void {
        vtab(entity).draw(entity, vp);
    }

    pub fn entityKill(entity: *Entity) void {
        entity.is_alive = false;
        vtab(entity).kill(entity);
    }

    pub fn entityTouch(e1: *Entity, e2: *Entity) void {
        vtab(e1).touch(e1, e2);
    }

    pub fn entityCollide(e: *Entity, normal: Vec2, t: ?Trace) void {
        vtab(e).collide(e, normal, t);
    }

    pub fn entityDamage(entity: *Entity, other: *Entity, value: f32) void {
        vtab(entity).damage(entity, other, value);
    }

    pub fn entityTrigger(e: *Entity, other: *Entity) void {
        vtab(e).trigger(e, other);
    }

    pub fn entityMessage(e1: *Entity, message: anytype, data: ?*anyopaque) void {
        vtab(e1).message(e1, @ptrFromInt(@intFromEnum(message)), data);
    }

    /// The center position of an entity, according to its pos and size
    pub fn entityCenter(ent: *Entity) Vec2 {
        return ent.pos.add(ent.size.mulf(0.5));
    }

    /// The distance (in pixels) between two entities
    pub fn entityDist(a: *Entity, b: *Entity) f32 {
        return entityCenter(a).dist(entityCenter(b));
    }

    /// The angle in radians of a line between two entities
    pub fn entityAngle(a: *Entity, b: *Entity) f32 {
        return entityCenter(a).angle(entityCenter(b));
    }

    fn entityResolveCollision(a: *Entity, b: *Entity) void {
        const overlap_x = if (a.pos.x < b.pos.x) a.pos.x + a.size.x - b.pos.x else b.pos.x + b.size.x - a.pos.x;
        const overlap_y = if (a.pos.y < b.pos.y) a.pos.y + a.size.y - b.pos.y else b.pos.y + b.size.y - a.pos.y;
        var a_move: f32 = undefined;
        var b_move: f32 = undefined;
        if ((a.physics & ett.ENTITY_COLLIDES_LITE) != 0 or (b.physics & ett.ENTITY_COLLIDES_FIXED) != 0) {
            a_move = 1;
            b_move = 0;
        } else if ((a.physics & ett.ENTITY_COLLIDES_FIXED) != 0 or (b.physics & ett.ENTITY_COLLIDES_LITE) != 0) {
            a_move = 0;
            b_move = 1;
        } else {
            const total_mass = a.mass + b.mass;
            a_move = b.mass / total_mass;
            b_move = a.mass / total_mass;
        }

        if (overlap_y > overlap_x) {
            if (a.pos.x < b.pos.x) {
                entitiesSeparateOnXAxis(a, b, a_move, b_move, overlap_x);
                entityCollide(a, vec2(-1, 0), null);
                entityCollide(b, vec2(1, 0), null);
            } else {
                entitiesSeparateOnXAxis(b, a, b_move, a_move, overlap_x);
                entityCollide(a, vec2(1, 0), null);
                entityCollide(b, vec2(-1, 0), null);
            }
        } else {
            if (a.pos.y < b.pos.y) {
                entitiesSeparateOnYAxis(a, b, a_move, b_move, overlap_y);
                entityCollide(a, vec2(0, -1), null);
                entityCollide(b, vec2(0, 1), null);
            } else {
                entitiesSeparateOnYAxis(b, a, b_move, a_move, overlap_y);
                entityCollide(a, vec2(0, 1), null);
                entityCollide(b, vec2(0, -1), null);
            }
        }
    }

    fn entitiesSeparateOnXAxis(left: *Entity, right: *Entity, left_move: f32, right_move: f32, overlap: f32) void {
        const impact_velocity = left.vel.x - right.vel.x;

        if (left_move > 0) {
            left.vel.x = right.vel.x * left_move + left.vel.x * right_move;

            const bounce = impact_velocity * left.restitution;
            if (bounce > options.ENTITY_MIN_BOUNCE_VELOCITY) {
                left.vel.x -= bounce;
            }
            entityMove(left, vec2(-overlap * left_move, 0));
        }
        if (right_move > 0) {
            right.vel.x = left.vel.x * right_move + right.vel.x * left_move;

            const bounce = impact_velocity * right.restitution;
            if (bounce > options.ENTITY_MIN_BOUNCE_VELOCITY) {
                right.vel.x += bounce;
            }
            entityMove(right, vec2(overlap * right_move, 0));
        }
    }

    fn entitiesSeparateOnYAxis(top: *Entity, bottom: *Entity, tm: f32, bm: f32, overlap: f32) void {
        var top_move = tm;
        var bottom_move = bm;
        if (bottom.on_ground and top_move > 0) {
            top_move = 1;
            bottom_move = 0;
        }

        const impact_velocity = top.vel.y - bottom.vel.y;
        const top_vel_y = top.vel.y;

        if (top_move > 0) {
            top.vel.y = (top.vel.y * bottom_move + bottom.vel.y * top_move);

            var move_x: f32 = 0;
            const bounce = impact_velocity * top.restitution;
            if (bounce > options.ENTITY_MIN_BOUNCE_VELOCITY) {
                top.vel.y -= bounce;
            } else {
                top.on_ground = true;
                move_x = @floatCast(bottom.vel.x * tick);
            }
            entityMove(top, vec2(move_x, -overlap * top_move));
        }
        if (bottom_move > 0) {
            bottom.vel.y = bottom.vel.y * top_move + top_vel_y * bottom_move;

            const bounce = impact_velocity * bottom.restitution;
            if (bounce > options.ENTITY_MIN_BOUNCE_VELOCITY) {
                bottom.vel.y += bounce;
            }
            entityMove(bottom, vec2(0, overlap * bottom_move));
        }
    }

    fn entityMove(self: *Entity, vstep: Vec2) void {
        if (((self.physics & ett.ENTITY_PHYSICS_WORLD) != 0) and collision_map != null) {
            const t = trace(collision_map.?, self.pos, vstep, self.size);
            entityHandleTraceResult(self, t);

            // The previous trace was stopped short and we still have some velocity
            // left? Do a second trace with the new velocity. this allows us
            // to slide along tiles;
            if (t.length < 1) {
                const rotated_normal = vec2(-t.normal.y, t.normal.x);
                const vel_along_normal = vstep.dot(rotated_normal);

                if (vel_along_normal != 0) {
                    const remaining = 1 - t.length;
                    const vstep2 = rotated_normal.mulf(vel_along_normal * remaining);
                    const t2 = trace(collision_map.?, self.pos, vstep2, self.size);
                    entityHandleTraceResult(self, t2);
                }
            }
        } else {
            self.pos = self.pos.add(vstep);
        }
    }

    fn entityHandleTraceResult(self: *Entity, t: Trace) void {
        self.pos = t.pos;

        if (t.tile == 0) {
            return;
        }

        entityCollide(self, t.normal, t);

        // If this entity is bouncy, calculate the velocity against the
        // slope's normal (the dot product) and see if we want to bounce
        // back.
        if (self.restitution > 0) {
            const vel_against_normal = self.vel.dot(t.normal);

            if (@abs(vel_against_normal) * self.restitution > options.ENTITY_MIN_BOUNCE_VELOCITY) {
                const vn = t.normal.mulf(vel_against_normal * 2.0);
                self.vel = self.vel.sub(vn).mulf(self.restitution);
                return;
            }
        }

        // If this game has gravity, we may have to set the on_ground flag.
        if (gravity != 0 and t.normal.y < -self.max_ground_normal) {
            self.on_ground = true;

            // If we don't want to slide on slopes, we cheat a bit by
            // fudging the y velocity.
            if (t.normal.y < -self.min_slide_normal) {
                self.vel.y = self.vel.x * t.normal.x;
            }
        }

        // Rotate the normal vector by 90° ([nx, ny] . [-ny, nx]) to get
        // the slope vector and calculate the dot product with the velocity.
        // This is the velocity with which we will slide along the slope.
        const rotated_normal = vec2(-t.normal.y, t.normal.x);
        const vel_along_normal = self.vel.dot(rotated_normal);
        self.vel = rotated_normal.mulf(vel_along_normal);
    }

    // Return a reference for to given entity
    pub fn entityRef(self: ?*Entity) EntityRef {
        if (self) |me| {
            return .{
                .id = me.id,
                .index = @intCast((@as(usize, @intFromPtr(me)) - @as(usize, @intFromPtr(&entities_storage[0]))) / @sizeOf(Entity)),
            };
        }
        return entityRefNone();
    }

    fn spawnByTypeName(comptime TKind: type, tag: TKind, pos: Vec2) ?*Entity {
        if (entities_len >= options.ENTITIES_MAX) return null;
        const ent = entities[entities_len];
        entities_len += 1;
        entity_unique_id += 1;
        ent.* = Entity{
            .id = entity_unique_id,
            .is_alive = true,
            .on_ground = false,
            .draw_order = 0,
            .physics = ett.ENTITY_GROUP_NONE,
            .group = ett.ENTITY_GROUP_NONE,
            .check_against = ett.ENTITY_GROUP_NONE,
            .pos = pos,
            .vel = vec2(0, 0),
            .accel = vec2(0, 0),
            .friction = vec2(0, 0),
            .offset = vec2(0, 0),
            .health = 0,
            .restitution = 0,
            .max_ground_normal = 0.69, // cosf(to_radians(46)),
            .min_slide_normal = 1, // cosf(to_radians(0)),
            .gravity = 1,
            .mass = 1,
            .size = vec2(8, 8),
            .entity = switch (tag) {
                inline else => |t| @unionInit(options.T, @tagName(t), undefined),
            },
        };

        entityInit(ent);
        return ent;
    }

    // Spawn entity of the given type at the given position, returns null if entity
    // storage is full.
    pub fn entitySpawn(kind: anytype, pos: Vec2) ?*Entity {
        if (entities_len >= options.ENTITIES_MAX) return null;
        const ent = entities[entities_len];
        entities_len += 1;
        entity_unique_id += 1;
        ent.* = Entity{
            .id = entity_unique_id,
            .is_alive = true,
            .on_ground = false,
            .draw_order = 0,
            .physics = ett.ENTITY_GROUP_NONE,
            .group = ett.ENTITY_GROUP_NONE,
            .check_against = ett.ENTITY_GROUP_NONE,
            .pos = pos,
            .vel = vec2(0, 0),
            .accel = vec2(0, 0),
            .friction = vec2(0, 0),
            .offset = vec2(0, 0),
            .health = 0,
            .restitution = 0,
            .max_ground_normal = 0.69, // cosf(to_radians(46)),
            .min_slide_normal = 1, // cosf(to_radians(0)),
            .gravity = 1,
            .mass = 1,
            .size = vec2(8, 8),
            .entity = @unionInit(options.ENTITY_TYPE, @tagName(kind), undefined),
        };

        entityInit(ent);
        return ent;
    }

    inline fn vtab(ent: *Entity) EntityVtab {
        const tag = std.meta.activeTag(ent.entity);
        return entity_vtab[@intFromEnum(tag)];
    }

    /// Whether two entities are overlapping
    pub fn entityIsTouching(self: *Entity, other: *Entity) bool {
        return !(self.pos.x >= other.pos.x + other.size.x or
            self.pos.x + self.size.x <= other.pos.x or
            self.pos.y >= other.pos.y + other.size.y or
            self.pos.y + self.size.y <= other.pos.y);
    }

    /// Get the name of an entity (usually the name is specified through "settings"
    /// in a level json). May be null.
    pub fn entityByName(name: []const u8) ?*Entity {
        // FIXME:PERF: linear search
        for (entities[0..entities_len]) |entity| {
            if (entity.is_alive and entity.name.len > 0 and std.mem.eql(u8, name, entity.name)) {
                return entity;
            }
        }

        return null;
    }

    /// Get a list of entities that are within the radius of this entity. Optionally
    /// filter by one entity type. Use ENTITY_TYPE_NONE to get all entities in
    /// proximity.
    /// If called while the game is running (as opposed to during scene init), the
    /// list is only valid for the duration of the current frame.
    pub fn entitiesByProximity(kind: anytype, ent: *Entity, radius: f32) EntityList {
        const pos = entityCenter(ent);
        return entitiesByLocation(kind, pos, radius, ent);
    }

    /// Same as entities_by_proximity() but with a center position instead of an
    /// entity.
    /// If called while the game is running (as opposed to during scene init), the
    /// list is only valid for the duration of the current frame.
    pub fn entitiesByLocation(kind: anytype, pos: Vec2, radius: f32, exclude: *Entity) EntityList {
        var ba = alloc.BumpAllocator{};
        var list = std.ArrayList(EntityRef).init(ba.allocator());
        defer list.deinit();

        const start_pos = pos.x - radius;
        const end_pos = start_pos + radius * 2;

        const radius_squared = radius * radius;

        // Binary search to the last entity that is below ENTITY_MAX_SIZE of the
        // start point
        var lower_bound: usize = 0;
        var upper_bound: usize = entities_len - 1;
        const search_pos: f32 = start_pos - options.ENTITY_MAX_SIZE;
        while (lower_bound <= upper_bound) {
            const current_index = (lower_bound + upper_bound) / 2;
            const current_pos = entities[current_index].pos.x;

            if (current_pos < search_pos) {
                lower_bound = current_index + 1;
            } else if (current_pos > search_pos) {
                upper_bound = current_index - 1;
            } else {
                break;
            }
        }

        // Find entities in the sweep range
        for (@max(upper_bound, 0)..entities_len) |i| {
            const entity = entities[i];

            // Have we reached the end of the search range?
            if (entity.pos.x > end_pos) {
                break;
            }

            // Is this entity in the search range and has the right type?
            if (entity.pos.x + entity.size.x >= start_pos and
                entity != exclude and
                (@as(u8, @intFromEnum(kind)) == 0 or entity.entity == kind) and
                entity.is_alive)
            {
                // Is the bounding box in the radius?
                const xd = entity.pos.x + (if (entity.pos.x < pos.x) entity.size.x else 0) - pos.x;
                const yd = entity.pos.y + (if (entity.pos.y < pos.y) entity.size.y else 0) - pos.y;
                if ((xd * xd) + (yd * yd) <= radius_squared) {
                    list.append(entityRef(entity)) catch @panic("failed to append entity");
                }
            }
        }

        return EntityList{ .entities = ba.allocator().dupe(EntityRef, list.items) catch @panic("failed to append") };
    }

    /// Get a list of all entities of a certain type
    /// If called while the game is running (as opposed to during scene init), the
    /// list is only valid for the duration of the current frame.
    /// Get a list of all entities of a certain type
    /// If called while the game is running (as opposed to during scene init), the
    /// list is only valid for the duration of the current frame.
    pub fn entitiesByType(kind: anytype) EntityList {
        var ba = alloc.BumpAllocator{};
        var list = std.ArrayList(EntityRef).init(ba.allocator());
        defer list.deinit();

        // FIXME:PERF: linear search
        var i: usize = 0;
        while (i < entities_len) {
            const entity = entities[i];
            if (std.meta.activeTag(entity.entity) == kind and entity.is_alive) {
                list.append(entityRef(entity)) catch @panic("failed to append");
            }
            i += 1;
        }

        return EntityList{ .entities = ba.allocator().dupe(EntityRef, list.items) catch @panic("failed to append") };
    }

    // Get a list of entities by name, with json_t array or object of names.
    // If called while the game is running (as opposed to during scene init), the
    // list is only valid for the duration of the current frame.
    pub fn entitiesFromJsonNames(targets: std.json.ObjectMap) EntityList {
        var ba = alloc.BumpAllocator{};
        var list = std.ArrayList(EntityRef).init(ba.allocator());
        defer list.deinit();

        for (targets.values()) |value| {
            const target_name = value.string;
            if (entityByName(target_name)) |target| {
                list.append(entityRef(target)) catch @panic("failed to append");
            }
        }

        return EntityList{ .entities = ba.allocator().dupe(EntityRef, list.items) catch @panic("failed to append") };
    }

    /// Get an entity by its reference. This will be NULL if the referred entity is
    /// not valid anymore.
    pub fn entityByRef(ref: EntityRef) ?*Entity {
        const ent = &entities_storage[ref.index];
        if (ent.is_alive and ent.id == ref.id) {
            return ent;
        }

        return null;
    }

    fn cmpEntity(context: void, lhs: *Entity, rhs: *Entity) bool {
        _ = context;
        return lhs.draw_order <= rhs.draw_order;
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
    pub fn loadLevel(comptime TKind: type, json_path: []const u8) void {
        var gpa = std.heap.GeneralPurposeAllocator(.{}){};
        const json = platform.loadAssetJson(json_path, gpa.allocator());
        defer json.deinit();

        entitiesReset();
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
        var entity_settings = gpa.allocator().alloc(EntitySettings, entities.len) catch @panic("error when allcoating settings");
        var entity_settings_len: usize = 0;

        for (etts.?.array.items) |def| {
            const type_name = def.object.get("type").?.string;
            assert(type_name.len > 0); // "Entity has no type"

            const kind = std.meta.stringToEnum(TKind, type_name);
            if (kind == null) {
                std.log.warn("Entity {s} not found", .{type_name});
                continue;
            }

            const pos = vec2(@as(f32, @floatFromInt(def.object.get("x").?.integer)), @as(f32, @floatFromInt(def.object.get("y").?.integer)));

            if (spawnByTypeName(TKind, kind.?, pos)) |ent| {
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
            entitySettings(settings.entity, settings.settings);
        }
        // temp_free(json);
    }

    /// Makes the scene_the current scene. This calls scene.cleanup() on the old
    /// scene and scene.init() on the new one. The actual swap of scenes happens
    /// at the beginning of the next frame, so it's ok to call engine_set_scene()
    /// from the middle of a frame.
    /// Your main_init() function must call engine_set_scene() to set first scene.
    pub fn setScene(s: *const Scene) void {
        scene_next = s;
    }

    // These functions are called by the engine during scene init/update/cleanup
    fn entitiesInit(vtabs: []const EntityVtab) void {
        entity_vtab = vtabs;

        // Call load function on all entity types
        for (vtabs) |v| {
            v.load();
        }

        entitiesReset();
    }

    fn entitiesCleanup() void {
        entitiesReset();
    }

    fn entitiesReset() void {
        for (0..options.ENTITIES_MAX) |i| {
            entities[i] = &entities_storage[i];
        }
        entities_len = 0;
    }

    fn entitiesUpdate() void {
        // Update all entities
        var i: usize = 0;
        while (i < entities_len) {
            const ent = entities[i];
            entityUpdate(ent);

            if (!ent.is_alive) {
                // If this entity is dead overwrite it with the last one and
                // decrease count.
                entities_len -= 1;
                if (i < entities_len) {
                    const last = entities[entities_len];
                    entities[entities_len] = entities[i];
                    entities[i] = last;
                    i -%= 1;
                }
            }
            i +%= 1;
        }

        // Sort by x or y position - insertion sort
        std.sort.insertion(*Entity, entities[0..entities_len], {}, cmpEntityPos);

        const len: usize = entities_len;

        // Sweep touches
        perf.checks = 0;
        i = 0;
        for (entities[0..len]) |e1| {
            if (e1.check_against != ett.ENTITY_GROUP_NONE or
                e1.group != ett.ENTITY_GROUP_NONE or (e1.physics > ett.ENTITY_COLLIDES_LITE))
            {
                const max_pos = e1.pos.x + e1.size.x;
                var j: usize = i + 1;
                while (j < len and entities[j].pos.x < max_pos) {
                    const e2 = entities[j];
                    perf.checks += 1;

                    if (entityIsTouching(e1, e2)) {
                        if (contains(e1.check_against, e2.group)) {
                            entityTouch(e1, e2);
                        }
                        if (contains(e1.group, e2.check_against)) {
                            entityTouch(e2, e1);
                        }

                        if (e1.physics >= ett.ENTITY_COLLIDES_LITE and
                            e2.physics >= ett.ENTITY_COLLIDES_LITE and
                            (e1.physics + e2.physics) >= (ett.ENTITY_COLLIDES_ACTIVE | ett.ENTITY_COLLIDES_LITE) and
                            e1.mass + e2.mass > 0)
                        {
                            entityResolveCollision(e1, e2);
                        }
                    }
                    j += 1;
                }
            }
            i += 1;
        }

        perf.entities = entities_len;
    }

    fn entitiesDraw(vp: Vec2) void {
        // Sort entities by draw_order
        // FIXME: this copies the entity array - which is sorted by pos.x/y and
        // sorts it again by draw_order. It's using insertion sort, which is slow
        // for data that is not already mostly sorted.
        var ba = alloc.BumpAllocator{};
        const draw_ents = ba.allocator().alloc(*Entity, entities_len) catch @panic("failed to alloc");
        @memcpy(draw_ents[0..], entities[0..entities_len]);

        std.sort.insertion(*Entity, draw_ents[0..entities_len], {}, cmpEntity);

        for (0..entities_len) |i| {
            const ent = draw_ents[i];
            entityDraw(ent, vp);
        }
    }
};
