const std = @import("std");

/// Safe version of the clamp
pub fn clamp(clamped_val: anytype, bound_1: anytype, bound_2: anytype) @TypeOf(clamped_val, bound_1, bound_2) {
    const upper_bound = @max(bound_1, bound_2);
    const lower_bound = @min(bound_1, bound_2);
    return @min(upper_bound, @max(clamped_val, lower_bound));
}

/// Scales v from the input range to the output range. This is useful for all
/// kinds of transitions. E.g. to move an image in from the right side of the
/// screen to the center over 2 second, starting at the 3 second:
/// x = scale(time, 3, 5, screen_size.x, screen_size.x/2)
pub fn scale(val: anytype, in_min: anytype, in_max: anytype, out_min: anytype, out_max: anytype) @TypeOf(val, in_min, in_max) {
    const _in_min = in_min;
    const _out_min = out_min;
    return _out_min + ((out_max) - _out_min) * (((val) - _in_min) / ((in_max) - _in_min));
}

var r: std.rand.DefaultPrng = std.rand.DefaultPrng.init(0);
var rand: std.Random = r.random();

/// Seed the random number generator to a particular state
pub fn randSeed(seed: u64) void {
    r = std.rand.DefaultPrng.init(seed);
    rand = r.random();
}

/// A random `u64`
pub fn randU64() u64 {
    return rand.int(u64);
}

/// A random float between min and max
pub fn randFloat(min: f32, max: f32) f32 {
    return min + rand.float(f32) * (max - min);
}

/// A random int between min and max (inclusive)
pub fn randInt(min: i32, max: i32) i32 {
    return rand.intRangeAtMost(i32, min, max);
}

pub inline fn shuffle(comptime T: type, buf: []T) void {
    return rand.shuffle(T, buf);
}

pub fn jsonFloat(value: ?std.json.Value) f32 {
    if (value) |v| {
        return switch (v) {
            .integer => |i| @as(f32, @floatFromInt(i)),
            .float => |f| @as(f32, @floatCast(f)),
            else => 0.0,
        };
    }
    return 0.0;
}
