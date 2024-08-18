const zi = @import("zimpact");
const EntityBase = zi.EntityBase;
pub const coin = @import("entities/coin.zig");
pub const player = @import("entities/player.zig");

pub const EntityKind = enum {
    coin,
    player,
};

pub const Entity = struct {
    base: EntityBase,
    kind: EntityKind,
    entity: void,
};
