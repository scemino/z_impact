const EntityBase = @import("entity.zig").EntityBase;
pub const coin = @import("entities/coin.zig");
pub const player = @import("entities/player.zig");

pub const EntityKind = enum {
    coin,
    player,
};

const UEntity = union {
    blob: struct {},
    player: struct {},
};

pub const Entity = struct {
    base: EntityBase,
    kind: EntityKind,
    entity: UEntity,
};
