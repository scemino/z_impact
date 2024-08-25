const zi = @import("zimpact");
pub const coin = @import("entities/coin.zig");
pub const player = @import("entities/player.zig");

pub const EntityKind = enum {
    coin,
    player,
};

pub const UEntity = union(EntityKind) {
    coin: void,
    player: void,
};
