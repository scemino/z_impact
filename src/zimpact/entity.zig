const std = @import("std");
const alloc = @import("allocator.zig");
const Vec2 = @import("types.zig").Vec2;
const Anim = @import("anim.zig").Anim;
const Trace = @import("trace.zig").Trace;
const vec2 = @import("types.zig").vec2;
const engine = @import("engine.zig");
const Engine = engine.Engine;
const ObjectMap = std.json.ObjectMap;
const options = @import("options.zig").options;
const trace = @import("trace.zig").trace;

/// Entity refs can be used to safely keep track of entities. Refs can be
/// resolved to an actual Entity with `entityByRef()`. Refs will resolve to
/// `null`, if the referenced entity is no longer valid (i.e. dead). This prevents
/// errors with direct `*Entity` which will always point to a valid entity
/// storage, but may no longer be the entity that you wanted.
pub const EntityRef = struct {
    id: u16,
    index: u16,
};

/// A list of entity refs. Usually bump allocated and thus only valid for the
/// current frame.
pub const EntityList = struct {
    entities: []EntityRef,
};

/// entity_ref_none will always resolve to NULL
pub fn entityRefNone() EntityRef {
    return .{ .id = 0, .index = 0 };
}

/// Entities can be members of one or more groups (through `ent.group`). This can
/// be used in conjunction with `ent.check_against` to indicate for which pairs
/// of entities you want to get notified by `entityTouch()`. Groups can be or-ed
/// together.
/// E.g. with the following two entities
/// ```zig
///   ent_a.group = ENTITY_GROUP_ITEM | ENTITY_GROUP_BREAKABLE;
///   ent_b.check_against = ENTITY_GROUP_BREAKABLE;
/// ```
/// The function
///   `entity_touch(ent_b, ent_a)`
/// will be called when those two entities overlap.
pub const ENTITY_GROUP_NONE = 0;
pub const ENTITY_GROUP_PLAYER = (1 << 0);
pub const ENTITY_GROUP_NPC = (1 << 1);
pub const ENTITY_GROUP_ENEMY = (1 << 2);
pub const ENTITY_GROUP_ITEM = (1 << 3);
pub const ENTITY_GROUP_PROJECTILE = (1 << 4);
pub const ENTITY_GROUP_PICKUP = (1 << 5);
pub const ENTITY_GROUP_BREAKABLE = (1 << 6);

pub const ENTITY_COLLIDES_WORLD = (1 << 1);
pub const ENTITY_COLLIDES_LITE = (1 << 4);
pub const ENTITY_COLLIDES_PASSIVE = (1 << 5);
pub const ENTITY_COLLIDES_ACTIVE = (1 << 6);
pub const ENTITY_COLLIDES_FIXED = (1 << 7);

/// The ent->physics determines how and if entities are moved and collide.
/// Don't collide, don't move. Useful for items that just sit there.
pub const ENTITY_PHYSICS_NONE = 0;

/// Move the entity according to its velocity, but don't collide
pub const ENTITY_PHYSICS_MOVE = (1 << 0);

/// Move the entity and collide with the collision_map
pub const ENTITY_PHYSICS_WORLD = (1 << 0) | ENTITY_COLLIDES_WORLD;

/// Move the entity, collide with the collision_map and other entities, but
/// only those other entities that have matching physics:
/// In ACTIVE vs. LITE or FIXED vs. ANY collisions, only the "weak" entity
/// moves, while the other one stays fixed. In ACTIVE vs. ACTIVE and ACTIVE
/// vs. PASSIVE collisions, both entities are moved. LITE or PASSIVE entities
/// don't collide with other LITE or PASSIVE entities at all. The behaiviour
/// for FIXED vs. FIXED collisions is undefined.
pub const ENTITY_PHYSICS_LITE = ENTITY_PHYSICS_WORLD | ENTITY_COLLIDES_LITE;
pub const ENTITY_PHYSICS_PASSIVE = ENTITY_PHYSICS_WORLD | ENTITY_COLLIDES_PASSIVE;
pub const ENTITY_PHYSICS_ACTIVE = ENTITY_PHYSICS_WORLD | ENTITY_COLLIDES_ACTIVE;
pub const ENTITY_PHYSICS_FIXED = ENTITY_PHYSICS_WORLD | ENTITY_COLLIDES_FIXED;

pub const Entity = struct {
    /// A unique id for this entity, assigned on spawn
    id: u16,
    /// Determines if this entity is in use
    is_alive: bool,
    /// True for engine.gravity > 0 and standing on something
    on_ground: bool = false,
    /// Entities are sorted (ascending) by this before drawing
    draw_order: i32 = 0,
    /// Physics behavior
    physics: u8 = ENTITY_PHYSICS_NONE,
    /// The groups this entity belongs to
    group: u8 = ENTITY_GROUP_NONE,
    /// The groups that this entity can touch
    check_against: u8 = ENTITY_GROUP_NONE,
    /// Top left position of the bounding box in the game world; usually not manipulated directly
    pos: Vec2 = vec2(0, 0),
    /// The bounding box for physics
    size: Vec2 = vec2(0, 0),
    /// Velocity
    vel: Vec2 = vec2(0, 0),
    /// Acceleration
    accel: Vec2 = vec2(0, 0),
    /// Friction as a factor of engine.tick * velocity
    friction: Vec2 = vec2(0, 0),
    /// Offset from position to draw the anim
    offset: Vec2 = vec2(0, 0),
    /// Name used for targets etc. usually set through json data
    name: []const u8 = &[0]u8{},
    /// When entity is damaged an resulting health < 0, the entity is killed
    health: f32 = 0,
    /// Gravity factor with engine.gravity. Default 1.0
    gravity: f32 = 0,
    /// Mass factor for active collisions. Default 1.0
    mass: f32 = 0,
    /// The "bounciness factor"
    restitution: f32 = 0,
    /// For slopes, determines on how steep the slope can be to set on_ground flag. Default cosf(to_radians(46))
    max_ground_normal: f32 = 0,
    /// For slopes, determines how steep the slope has to be for entity to slide down. Default cosf(to_radians(0))
    min_slide_normal: f32 = 0,
    /// The animation that is automatically drawn
    anim: Anim = undefined,

    entity: options.ENTITY_TYPE,
};

/// The `EntityVtab` struct must implemented by all your entity types. It holds
/// the functions to call for each entity type. All of these are optional. In
/// the simplest case you just have a global:
/// `const vtabs = [_]zi.EntityVtab{}`;
pub const EntityVtab = struct {
    /// Called once at program start, just before main `init()`. Use this to
    /// load assets and animations for your entity types.
    load: *const fn () void = noopLoad,

    /// Called once for each entity, when the entity is created through
    /// `entitySpawn()`. Use this to set all properties (size, offset, animation)
    /// of your entity.
    init: *const fn (self: *Entity) void = noopInit,

    /// Called once after `engine.loadLevel()` when all entities have been
    /// spawned. The json_t *def contains the "settings" of the entity from the
    /// level json.
    settings: *const fn (self: *Entity, def: ObjectMap) void = noopSettings,

    /// Called once per frame for each entity. The default `entityUpdateBase()`
    /// moves the entity according to its physics
    update: *const fn (self: *Entity) void = entityBaseUpdate,

    /// Called once per frame for each entity. The default `entityDrawBase()`
    /// draws the `entity.anim`
    draw: *const fn (self: *Entity, viewport: Vec2) void = entityBaseDraw,

    /// Called when the entity is removed from the game through `entityKill()`
    kill: *const fn (self: *Entity) void = noopKill,

    /// Called when this entity touches another entity, according to
    /// `entity.check_against`
    touch: *const fn (self: *Entity, other: *Entity) void = noopTouch,

    /// Called when the entity collides with the game world or another entity
    /// Careful: the trace will only be set from a game world collision. It will
    /// be `null` for a collision with another entity.
    collide: *const fn (self: *Entity, normal: Vec2, trace: ?Trace) void = noopCollide,

    /// Called through `entityDamage()`. The default `entityBaseDamage()` deducts
    /// damage from the entity's health and calls `entityLill()` if it's <= 0.
    damage: *const fn (self: *Entity, other: *Entity, damage: f32) void = entityBaseDamage,

    /// Called through `entityTrigger()`
    trigger: *const fn (self: *Entity, other: *Entity) void = noopTrigger,

    /// Called through `entityMessage()`
    message: *const fn (self: *Entity, message: ?*anyopaque, data: ?*anyopaque) void = noopMessage,

    // zig fmt: off
    fn noopLoad() void {}
    fn noopInit(_: *Entity) void {  }
    fn noopKill(_: *Entity) void {  }
    fn noopSettings(_: *Entity, _: ObjectMap) void {}
    fn noopTouch(_: *Entity, _: *Entity) void { }
    fn noopCollide(_: *Entity, _: Vec2, _: ?Trace) void {}
    fn noopTrigger(_: *Entity, _: *Entity) void {}
    fn noopMessage(_: *Entity, _: ?*anyopaque, _: ?*anyopaque) void {}
    // zig fmt: on
};

inline fn vtab(ent: *Entity) EntityVtab {
    const tag = std.meta.activeTag(ent.entity);
    return engine.entity_vtab[@intFromEnum(tag)];
}

/// Functions to call the correct function on each entity according to the vtab.
pub fn entityInit(entity: *Entity) void {
    vtab(entity).init(entity);
}

pub fn entitySettings(e: *Entity, value: ObjectMap) void {
    vtab(e).settings(e, value);
}

pub fn entityUpdate(entity: *Entity) void {
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

pub fn entityResolveCollision(a: *Entity, b: *Entity) void {
    const overlap_x = if (a.pos.x < b.pos.x) a.pos.x + a.size.x - b.pos.x else b.pos.x + b.size.x - a.pos.x;
    const overlap_y = if (a.pos.y < b.pos.y) a.pos.y + a.size.y - b.pos.y else b.pos.y + b.size.y - a.pos.y;
    var a_move: f32 = undefined;
    var b_move: f32 = undefined;
    if ((a.physics & ENTITY_COLLIDES_LITE) != 0 or (b.physics & ENTITY_COLLIDES_FIXED) != 0) {
        a_move = 1;
        b_move = 0;
    } else if ((a.physics & ENTITY_COLLIDES_FIXED) != 0 or (b.physics & ENTITY_COLLIDES_LITE) != 0) {
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
            move_x = @floatCast(bottom.vel.x * engine.tick);
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

pub fn entityMove(self: *Entity, vstep: Vec2) void {
    if (((self.physics & ENTITY_PHYSICS_WORLD) != 0) and engine.collision_map != null) {
        const t = trace(engine.collision_map.?, self.pos, vstep, self.size);
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
                const t2 = trace(engine.collision_map.?, self.pos, vstep2, self.size);
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
    if (engine.gravity != 0 and t.normal.y < -self.max_ground_normal) {
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
            .index = @intCast((@as(usize, @intFromPtr(me)) - @as(usize, @intFromPtr(&engine.entities_storage[0]))) / @sizeOf(Entity)),
        };
    }
    return entityRefNone();
}

// These functions are called by the engine during scene init/update/cleanup
pub fn entitiesInit(vtabs: []const EntityVtab) void {
    engine.entity_vtab = vtabs;

    // Call load function on all entity types
    for (vtabs) |v| {
        v.load();
    }

    entitiesReset();
}

pub fn entitiesCleanup() void {
    entitiesReset();
}

pub fn entitiesReset() void {
    for (0..options.ENTITIES_MAX) |i| {
        engine.entities[i] = &engine.entities_storage[i];
    }
    engine.entities_len = 0;
}

pub fn entitiesUpdate() void {
    // Update all entities
    var i: usize = 0;
    while (i < engine.entities_len) {
        const ent = engine.entities[i];
        entityUpdate(ent);

        if (!ent.is_alive) {
            // If this entity is dead overwrite it with the last one and
            // decrease count.
            engine.entities_len -= 1;
            if (i < engine.entities_len) {
                const last = engine.entities[engine.entities_len];
                engine.entities[engine.entities_len] = engine.entities[i];
                engine.entities[i] = last;
                i -%= 1;
            }
        }
        i +%= 1;
    }

    // Sort by x or y position - insertion sort
    std.sort.insertion(*Entity, engine.entities[0..engine.entities_len], {}, cmpEntityPos);

    const len: usize = engine.entities_len;

    // Sweep touches
    engine.perf.checks = 0;
    i = 0;
    for (engine.entities[0..len]) |e1| {
        if (e1.check_against != ENTITY_GROUP_NONE or
            e1.group != ENTITY_GROUP_NONE or (e1.physics > ENTITY_COLLIDES_LITE))
        {
            const max_pos = sweepAxis(e1.pos) + sweepAxis(e1.size);
            var j: usize = i + 1;
            while (j < len and sweepAxis(engine.entities[j].pos) < max_pos) {
                const e2 = engine.entities[j];
                engine.perf.checks += 1;

                if (entityIsTouching(e1, e2)) {
                    if (contains(e1.check_against, e2.group)) {
                        entityTouch(e1, e2);
                    }
                    if (contains(e1.group, e2.check_against)) {
                        entityTouch(e2, e1);
                    }

                    if (e1.physics >= ENTITY_COLLIDES_LITE and
                        e2.physics >= ENTITY_COLLIDES_LITE and
                        (e1.physics + e2.physics) >= (ENTITY_COLLIDES_ACTIVE | ENTITY_COLLIDES_LITE) and
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

    engine.perf.entities = engine.entities_len;
}

pub fn entitiesDraw(vp: Vec2) void {
    // Sort entities by draw_order
    // FIXME: this copies the entity array - which is sorted by pos.x/y and
    // sorts it again by draw_order. It's using insertion sort, which is slow
    // for data that is not already mostly sorted.
    var ba = alloc.BumpAllocator{};
    const draw_ents = ba.allocator().alloc(*Entity, engine.entities_len) catch @panic("failed to alloc");
    @memcpy(draw_ents[0..], engine.entities[0..engine.entities_len]);

    std.sort.insertion(*Entity, draw_ents[0..engine.entities_len], {}, cmpEntity);

    for (0..engine.entities_len) |i| {
        const ent = draw_ents[i];
        entityDraw(ent, vp);
    }
}

pub fn spawnByTypeName(comptime TKind: type, tag: TKind, pos: Vec2) ?*Entity {
    if (engine.entities_len >= options.ENTITIES_MAX) return null;
    const ent = engine.entities[engine.entities_len];
    engine.entities_len += 1;
    engine.entity_unique_id += 1;
    ent.* = Entity{
        .id = engine.entity_unique_id,
        .is_alive = true,
        .on_ground = false,
        .draw_order = 0,
        .physics = ENTITY_GROUP_NONE,
        .group = ENTITY_GROUP_NONE,
        .check_against = ENTITY_GROUP_NONE,
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
            inline else => |t| @unionInit(options.ENTITY_TYPE, @tagName(t), undefined),
        },
    };

    entityInit(ent);
    return ent;
}

// Spawn entity of the given type at the given position, returns null if entity
// storage is full.
pub fn entitySpawn(kind: anytype, pos: Vec2) ?*Entity {
    if (engine.entities_len >= options.ENTITIES_MAX) return null;
    const ent = engine.entities[engine.entities_len];
    engine.entities_len += 1;
    engine.entity_unique_id += 1;
    ent.* = Entity{
        .id = engine.entity_unique_id,
        .is_alive = true,
        .on_ground = false,
        .draw_order = 0,
        .physics = ENTITY_GROUP_NONE,
        .group = ENTITY_GROUP_NONE,
        .check_against = ENTITY_GROUP_NONE,
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
    for (engine.entities[0..engine.entities_len]) |entity| {
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

    const start_pos = sweepAxis(pos) - radius;
    const end_pos = start_pos + radius * 2;

    const radius_squared = radius * radius;

    // Binary search to the last entity that is below ENTITY_MAX_SIZE of the
    // start point
    var lower_bound: usize = 0;
    var upper_bound: usize = engine.entities_len - 1;
    const search_pos: f32 = start_pos - options.ENTITY_MAX_SIZE;
    while (lower_bound <= upper_bound) {
        const current_index = (lower_bound + upper_bound) / 2;
        const current_pos = sweepAxis(engine.entities[current_index].pos);

        if (current_pos < search_pos) {
            lower_bound = current_index + 1;
        } else if (current_pos > search_pos) {
            upper_bound = current_index - 1;
        } else {
            break;
        }
    }

    // Find entities in the sweep range
    for (@max(upper_bound, 0)..engine.entities_len) |i| {
        const entity = engine.entities[i];

        // Have we reached the end of the search range?
        if (sweepAxis(entity.pos) > end_pos) {
            break;
        }

        // Is this entity in the search range and has the right type?
        if (sweepAxis(entity.pos) + sweepAxis(entity.size) >= start_pos and
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
    while (i < engine.entities_len) {
        const entity = engine.entities[i];
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

/// Updates the entity's position and velocity according to its physics. This
/// also checks for collision against the game world. If you use update() in your
/// vtab, you may still want to call this function.
pub fn entityBaseUpdate(self: *Entity) void {
    if ((self.physics & ENTITY_PHYSICS_MOVE) != ENTITY_PHYSICS_MOVE)
        return;

    // Integrate velocity
    const v = self.vel;

    self.vel.y = @floatCast(self.vel.y + engine.gravity * self.gravity * engine.tick);
    const friction = vec2(@min(@as(f32, @floatCast(self.friction.x * engine.tick)), 1), @min(@as(f32, @floatCast(self.friction.y * engine.tick)), 1));
    self.vel = Vec2.add(self.vel, Vec2.sub(Vec2.mulf(self.accel, @as(f32, @floatCast(engine.tick))), Vec2.mul(self.vel, friction)));

    const vstep = Vec2.mulf(Vec2.add(v, self.vel), @as(f32, @floatCast(engine.tick * 0.5)));
    self.on_ground = false;
    entityMove(self, vstep);
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

/// Get an entity by its reference. This will be NULL if the referred entity is
/// not valid anymore.
pub fn entityByRef(ref: EntityRef) ?*Entity {
    const ent = &engine.entities_storage[ref.index];
    if (ent.is_alive and ent.id == ref.id) {
        return ent;
    }

    return null;
}

fn cmpEntity(context: void, lhs: *Entity, rhs: *Entity) bool {
    _ = context;
    return lhs.draw_order <= rhs.draw_order;
}

inline fn sweepAxis(v: Vec2) f32 {
    return if (options.ENTITY_SWEEP_AXIS == .x) v.x else v.y;
}

fn cmpEntityPos(context: void, a: *Entity, b: *Entity) bool {
    _ = context;
    return sweepAxis(a.pos) <= sweepAxis(b.pos);
}

fn contains(g1: u8, g2: u8) bool {
    return (g1 & g2) != 0;
}
