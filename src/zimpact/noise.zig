const std = @import("std");
const alloc = @import("allocator.zig");
const utils = @import("utils.zig");
const vec2 = @import("types.zig").vec2;
const Vec2 = @import("types.zig").Vec2;

/// A 2D perlin noise generator. This generates "random" numbers with natural
/// looking gradients for points that are close together.
/// See https://en.wikipedia.org/wiki/Perlin_noise
/// FIXME: should this even be part of Z impact?
pub const Noise = struct {
    size_bits: u4,
    g: []Vec2,
    p: []u16,

    /// Get the noise value in the range of -1..1
    pub fn gen(n: Noise, pos: Vec2) f32 {
        const size = @as(u16, 1) << n.size_bits;
        const mask: usize = size - 1;

        const p = n.p;
        const g = n.g;

        // Compute what gradients to use
        const qx0: usize = @as(usize, @intFromFloat(pos.x)) & mask;
        const qx1: usize = (qx0 + 1) & mask;
        const tx0 = pos.x - @as(f32, @floatFromInt(qx0));
        const tx1 = tx0 - 1;

        const qy0: usize = @as(usize, @intFromFloat(pos.y)) & mask;
        const qy1: usize = (qy0 + 1) & mask;
        const ty0 = pos.y - @as(f32, @floatFromInt(qy0));
        const ty1 = ty0 - 1;

        // Permutate values to get pseudo randomly chosen gradients
        const q00: usize = p[(qy0 + p[qx0]) & mask];
        const q01: usize = p[(qy0 + p[qx1]) & mask];

        const q10: usize = p[(qy1 + p[qx0]) & mask];
        const q11: usize = p[(qy1 + p[qx1]) & mask];

        // Compute the dotproduct between the vectors and the gradients
        const v00 = g[q00].x * tx0 + g[q00].y * ty0;
        const v01 = g[q01].x * tx1 + g[q01].y * ty0;

        const v10 = g[q10].x * tx0 + g[q10].y * ty1;
        const v11 = g[q11].x * tx1 + g[q11].y * ty1;

        // Modulate with the weight function
        const wx = (3 - 2 * tx0) * tx0 * tx0;
        const v0 = v00 - wx * (v00 - v01);
        const v1 = v10 - wx * (v10 - v11);

        const wy = (3 - 2 * ty0) * ty0 * ty0;
        const v = v0 - wy * (v0 - v1);

        return v;
    }
};

/// Bump allocate and create a noise generator with a size of 1 << size_bits
pub fn noise(size_bits: u4) *Noise {
    var ba = alloc.BumpAllocator{};
    var n = ba.allocator().create(Noise) catch @panic("failed to create noise");
    n.size_bits = size_bits;

    const size: usize = @as(u16, 1) << size_bits;
    n.g = alloc.bumpAlloc(Vec2, size) catch @panic("failed to create noise");
    n.p = alloc.bumpAlloc(u16, size) catch @panic("failed to create noise");

    for (0..size) |i| {
        n.g[i] = vec2(utils.randFloat(-1, 1), utils.randFloat(-1, 1));
        n.p[i] = @intCast(i);
    }

    utils.shuffle(u16, n.p);
    return n;
}
