const EntityBase = @import("entity.zig").EntityBase;
pub const blob = @import("entities/blob.zig");
pub const player = @import("entities/player.zig");

pub const EntityKind = enum {
    blob,
    player,
};

const UEntity = union {
    blob: struct {
        in_jump: bool = false,
        seen_player: bool = false,
        jump_timer: f32 = 0.0,
    },
    player: struct {
        high_jump_time: f32,
        idle_time: f32,
        flip: bool,
        can_jump: bool,
        is_idle: bool,
    },
};

pub const Entity = struct {
    base: EntityBase,
    kind: EntityKind,
    entity: UEntity,
};
