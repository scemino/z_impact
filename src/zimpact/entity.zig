const std = @import("std");
const Vec2 = @import("types.zig").Vec2;
const Anim = @import("anim.zig").Anim;
const Trace = @import("trace.zig").Trace;
const vec2 = @import("types.zig").vec2;
const Engine = @import("engine.zig").Engine;
const ObjectMap = std.json.ObjectMap;

/// Entity refs can be used to safely keep track of entities. Refs can be
/// resolved to an actual entity_t with entity_by_ref(). Refs will resolve to
/// NULL, if the referenced entity is no longer valid (i.e. dead). This prevents
/// errors with direct entity_t* which will always point to a valid entity
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

/// Entities can be members of one or more groups (through ent->group). This can
/// be used in conjunction with ent->check_against to indicate for which pairs
/// of entities you want to get notified by entity_touch(). Groups can be or-ed
/// together.
/// E.g. with the following two entities
///   ent_a->group = ENTITY_GROUP_ITEM | ENTITY_GROUP_BREAKABLE;
///   ent_b->check_against = ENTITY_GROUP_BREAKABLE;
/// The function
///   entity_touch(ent_b, ent_a)
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

pub const EntityBase = struct {
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
};

/// The EntityVtab struct must implemented by all your entity types. It holds
/// the functions to call for each entity type. All of these are optional. In
/// the simplest case you just have a global:
/// entity_vtab_t entity_vtab_mytype = {};
pub fn EntityVtab(comptime TEngine: type, comptime Entity: type) type {
    return struct {
        const engine = TEngine;

        /// Called once at program start, just before main_init(). Use this to
        /// load assets and animations for your entity types.
        load: *const fn () void = noopLoad,

        /// Called once for each entity, when the entity is created through
        /// entity_spawn(). Use this to set all properties (size, offset, animation)
        /// of your entity.
        init: *const fn (self: *Entity) void = noopInit,

        /// Called once after engine_load_level() when all entities have been
        /// spawned. The json_t *def contains the "settings" of the entity from the
        /// level json.
        settings: *const fn (self: *Entity, def: ObjectMap) void = noopSettings,

        /// Called once per frame for each entity. The default entity_update_base()
        /// moves the entity according to its physics
        update: *const fn (self: *Entity) void = engine.entityBaseUpdate,

        /// Called once per frame for each entity. The default entity_draw_base()
        /// draws the entity->anim
        draw: *const fn (self: *Entity, viewport: Vec2) void = engine.entityBaseDraw,

        /// Called when the entity is removed from the game through entity_kill()
        kill: *const fn (self: *Entity) void = noopKill,

        /// Called when this entity touches another entity, according to
        /// entity->check_against
        touch: *const fn (self: *Entity, other: *Entity) void = noopTouch,

        /// Called when the entity collides with the game world or another entity
        /// Careful: the trace will only be set from a game world collision. It will
        /// be NULL for a collision with another entity.
        collide: *const fn (self: *Entity, normal: Vec2, trace: ?Trace) void = noopCollide,

        /// Called through entity_damage(). The default entity_base_damage() deducts
        /// damage from the entity's health and calls entity_kill() if it's <= 0.
        damage: *const fn (self: *Entity, other: *Entity, damage: f32) void = engine.entityBaseDamage,

        /// Called through entity_trigger()
        trigger: *const fn (self: *Entity, other: *Entity) void = noopTrigger,

        /// Called through entity_message()
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
}
