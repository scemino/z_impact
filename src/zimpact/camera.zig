const std = @import("std");
const types = @import("types.zig");
const entity = @import("entity.zig");
const render = @import("render.zig");
const engine = @import("engine.zig");
const utils = @import("utils.zig");
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const EntityRef = entity.EntityRef;
const fromVec2i = types.fromVec2i;

/// A camera allows you to follow entities and move smoothly to a new position.
/// You can also specify a deadzone and lookahead to adapt move the viewport
/// closer to the action. Using a camera is totally optional; you could instead
/// manipulate the `engine.viewport` directly if you wish.
/// Cameras can be instantiated from just a `Camera`, i.e.:
/// ```zig
/// var cam: Camera;
/// cam.follow(some_entity, true);
/// ```
/// To actually move the camera, you have to call `cam.update()`. This is
/// typically done once per frame.
/// If the `engine.collision_map` is set, the camera will ensure the screen stays
/// within the bounds of this map.
pub const Camera = struct {
    /// A factor of how fast the camera is moving. Values between 0.5..10
    /// are usually sensible.
    speed: f32 = 0,

    /// A fixed offset of the screen center from the target entity.
    offset: Vec2 = vec2(0, 0),

    /// Whether to automatically move the bottom of the deadzone up to the
    /// target entity when the target is on_ground
    snap_to_platform: bool = false,

    /// The minimum velocity (in pixels per second) for a camera movement. If
    /// this is set too low and the camera is close to the target it will move
    /// very slowly which results in a single pixel movement every few moments,
    /// which can look weird. 5 looks good, imho.
    min_vel: f32 = 0,

    /// The size of the deadzone: the size of the area around the target within
    /// which the camera will not move. The camera will move only when the target
    /// is about to leave the deadzone.
    deadzone: Vec2 = vec2(0, 0),

    /// The amount of pixels the camera should be ahead the target. Whether the
    /// "ahead" means left/right (or above/below), is determined by the edge of
    /// the deadzone that the entity touched last.
    look_ahead: Vec2 = vec2(0, 0),

    /// Internal state
    deadzone_pos: Vec2 = vec2(0, 0),
    look_ahead_target: Vec2 = vec2(0, 0),
    follow_entity: EntityRef = undefined,
    pos: Vec2 = vec2(0, 0),
    vel: Vec2 = vec2(0, 0),

    pub fn viewportTarget(cam: *Camera) Vec2 {
        const screen_size = fromVec2i(render.renderSize());
        const screen_center = screen_size.mulf(0.5);
        var viewport_target = cam.pos.sub(screen_center).add(cam.offset);

        if (engine.collision_map) |map| {
            const bounds = fromVec2i(map.size.muli(map.tile_size));
            viewport_target.x = utils.clamp(viewport_target.x, 0, bounds.x - screen_size.x);
            viewport_target.y = utils.clamp(viewport_target.y, 0, bounds.y - screen_size.y);
        }
        return viewport_target;
    }

    /// Advance the camera towards its target
    pub fn update(cam: *Camera) void {
        if (entity.entityByRef(cam.follow_entity)) |entity_follow| {
            const size = vec2(@min(entity_follow.size.x, cam.deadzone.x), @min(entity_follow.size.y, cam.deadzone.y));

            if (entity_follow.pos.x < cam.deadzone_pos.x) {
                cam.deadzone_pos.x = entity_follow.pos.x;
                cam.look_ahead_target.x = -cam.look_ahead.x;
            } else if (entity_follow.pos.x + size.x > cam.deadzone_pos.x + cam.deadzone.x) {
                cam.deadzone_pos.x = entity_follow.pos.x + size.x - cam.deadzone.x;
                cam.look_ahead_target.x = cam.look_ahead.x;
            }

            if (entity_follow.pos.y < cam.deadzone_pos.y) {
                cam.deadzone_pos.y = entity_follow.pos.y;
                cam.look_ahead_target.y = -cam.look_ahead.y;
            } else if (entity_follow.pos.y + size.y > cam.deadzone_pos.y + cam.deadzone.y) {
                cam.deadzone_pos.y = entity_follow.pos.y + size.y - cam.deadzone.y;
                cam.look_ahead_target.y = cam.look_ahead.y;
            }

            if (cam.snap_to_platform and entity_follow.on_ground) {
                cam.deadzone_pos.y = entity_follow.pos.y + entity_follow.size.y - cam.deadzone.y;
            }
            const deadzone_target = cam.deadzone_pos.add(cam.deadzone.mulf(0.5));
            cam.pos = deadzone_target.add(cam.look_ahead_target);
        }

        const diff = viewportTarget(cam).sub(engine.viewport);
        cam.vel = diff.mulf(cam.speed);

        if ((@abs(cam.vel.x) + @abs(cam.vel.y)) > cam.min_vel) {
            engine.viewport = engine.viewport.add(cam.vel.mulf(@as(f32, @floatCast(engine.tick))));
        }
    }

    /// Set the camera to pos (no movement)
    pub fn set(cam: *Camera, pos: Vec2) void {
        cam.pos = pos;
        engine.viewport = viewportTarget(cam);
    }

    /// Set the target to pos
    pub fn move(cam: *Camera, pos: Vec2) void {
        cam.pos = pos;
    }

    /// Follow an entity. Set snap to true when you want to jump to it. The camera
    /// will follow this target for as long as it's alive (or until following
    /// another entity / unfollow)
    pub fn follow(cam: *Camera, f: EntityRef, snap: bool) void {
        cam.follow_entity = f;
        if (snap) {
            cam.update();
            engine.viewport = viewportTarget(cam);
        }
    }

    /// Stop following the entity
    pub fn unfollow(cam: *Camera) void {
        cam.follow = entity.entityRefNone();
    }
};
