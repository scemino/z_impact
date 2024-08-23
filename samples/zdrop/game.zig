const zi = @import("zimpact");
const EntityBase = zi.EntityBase;
pub const coin = @import("entities/coin.zig");
pub const player = @import("entities/player.zig");
pub const Engine = zi.Engine(UEntity);
pub const Entity = Engine.Entity;

pub const EntityKind = enum {
    coin,
    player,
};

pub const EntityVtab = zi.Engine(UEntity).EntityVtab;

pub const UEntity = union(EntityKind) {
    coin: void,
    player: void,
};
