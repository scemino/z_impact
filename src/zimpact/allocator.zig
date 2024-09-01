const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;
const options = @import("options.zig").options;

var hunk: [options.ALLOC_SIZE]u8 = [1]u8{0} ** options.ALLOC_SIZE;
var bump_len: usize = 0;
var temp_len: usize = 0;

var temp_objects: [options.ALLOC_TEMP_OBJECTS_MAX]usize = [1]usize{0} ** options.ALLOC_TEMP_OBJECTS_MAX;
var temp_objects_len: usize = 0;

/// We statically reserve a single "hunk" of memory at program start. Memory
/// (for our own allocators) can not ever outgrow this hunk. Theres two ways to
/// allocate bytes from this hunk:
///
///   1. A bump allocator that just grows linearly and may be reset to a previous
/// level. This returns bytes from the front of the hunk and is meant for all
/// data the game needs while it's running.
///
/// Z impact mostly manages this bump level for you. First everything that is
/// bump-allocated _before_ `engine.setScene()` is called will only be freed when.
/// the program ends.
/// Then, when a scene is loaded the bump position is recorded. When the current
/// scene ends (i.e. `engine.setScene()` is called again), the bump allocator is
/// reset to that position. Conceptually the scene is wrapped in an alloc_pool().
/// Thirdly, each frame is wrapped in an alloc_pool().
///
/// This all means that you can't use any memory that you allocated in one scene
/// in another scene and also that you can't use any memory that you allocated in
/// one frame in the next frame.
///
///   2. A temp allocator. This allocates bytes from the end of the hunk. Temp
/// allocated bytes must be explicitly freed again. As opposed to the bump
/// allocater, the temp allocator can be freed out of order.
///
/// The temp allocator is meant for very short lived objects, to assist data
/// loading. E.g. pixel data from an image file might be temp allocated, handed
/// over to the render (which may pass it on to the GPU or permanently put it in
/// the bump memory) and then immediately free() it again.
///
/// Temp allocations are not allowed to persist. At the end of each frame, the
/// engine checks if the temp allocator is empty - and if not: kills the program.
///
/// There's no way to handle an allocation failure. We just kill the program
/// with an error. This is fine if you know all your game data (i.e. levels) in
/// advance. Games that allow loading user defined levels may need a separate
/// allocation strategy...
pub const BumpMark = struct { index: usize = 0 };

pub const BumpAllocator = struct {
    pub fn allocator(self: *BumpAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = log2_ptr_align;
        _ = ret_addr;
        const size = ((len + 7) >> 3) << 3; // align to 8 bytes
        assert(bump_len + temp_len + len < options.ALLOC_SIZE);
        @memset(hunk[bump_len .. bump_len + size], 0);
        bump_len += size;
        return hunk[bump_len - size .. bump_len].ptr;
    }

    fn free(ctx: *anyopaque, old_mem: []u8, log2_old_align_u8: u8, ret_addr: usize) void {
        _ = ctx;
        _ = old_mem;
        _ = log2_old_align_u8;
        _ = ret_addr;
    }

    fn resize(ctx: *anyopaque, old_mem: []u8, log2_old_align_u8: u8, new_size: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = old_mem;
        _ = log2_old_align_u8;
        _ = new_size;
        _ = ret_addr;
        return false;
    }
};

pub const TempAllocator = struct {
    pub fn allocator(self: *TempAllocator) Allocator {
        return .{
            .ptr = self,
            .vtable = &.{
                .alloc = alloc,
                .resize = resize,
                .free = free,
            },
        };
    }

    fn alloc(ctx: *anyopaque, len: usize, log2_ptr_align: u8, ret_addr: usize) ?[*]u8 {
        _ = ctx;
        _ = log2_ptr_align;
        _ = ret_addr;
        const size = ((len + 7) >> 3) << 3; // allign to 8 bytes
        temp_len += size;
        temp_objects[temp_objects_len] = temp_len;
        temp_objects_len += 1;
        return hunk[options.ALLOC_SIZE - temp_len ..].ptr;
    }

    fn free(ctx: *anyopaque, old_mem: []u8, log2_old_align_u8: u8, ret_addr: usize) void {
        _ = ctx;
        _ = log2_old_align_u8;
        _ = ret_addr;
        const offset: usize = options.ALLOC_SIZE + @intFromPtr(&hunk[0]) - @intFromPtr(&old_mem[0]);
        assert(offset < options.ALLOC_SIZE);

        var found = false;
        var remaining_max: usize = 0;
        var i: usize = 0;
        while (i < temp_objects_len) {
            if (temp_objects[i] == offset) {
                temp_objects_len -= 1;
                temp_objects[i] = temp_objects[temp_objects_len];
                i -%= 1;
                found = true;
            } else if (temp_objects[i] > remaining_max) {
                remaining_max = temp_objects[i];
            }
            i +%= 1;
        }
        assert(found);
        temp_len = remaining_max;
    }

    fn resize(ctx: *anyopaque, old_mem: []u8, log2_old_align_u8: u8, new_size: usize, ret_addr: usize) bool {
        _ = ctx;
        _ = old_mem;
        _ = log2_old_align_u8;
        _ = new_size;
        _ = ret_addr;
        return false;
    }
};

/// Check if temp is empty, or die()
pub fn tempAllocCheck() void {
    if (temp_len != 0) {
        std.log.err("Temp memory not free: {} object(s)", .{temp_objects_len});
        assert(false);
    }
}

/// Allocate `size` bytes in bump memory
pub fn bumpAlloc(comptime T: type, size: usize) ![]T {
    var bump_alloc = BumpAllocator{};
    return bump_alloc.allocator().alloc(T, size);
}

/// Return the current position of the bump allocator
pub fn bumpMark() BumpMark {
    return .{ .index = bump_len };
}

/// Reset the bump allocator to the given position
pub fn bumpReset(mark: BumpMark) void {
    bump_len = mark.index;
}

/// Move bytes from temp to bump memory. This is essentially a shorthand for
/// `bumpAlloc(); @memcpy(); ta.allocator().free();` without the requirement to fit both
/// (temp and bump) into the hunk at the same time.
pub fn bumpFromTemp(comptime T: type, temp: []T, offset: usize, size: usize) []T {
    var ta = TempAllocator{};
    ta.allocator().free(temp);
    assert(bump_len + temp_len + size < options.ALLOC_SIZE); //, "Failed to allocate %d bytes in hunk mem", size);
    var fa = std.heap.FixedBufferAllocator.init(hunk[bump_len .. bump_len + size]);
    bump_len += size;
    return fa.allocator().dupe(T, temp[offset .. offset + size]) catch @panic("failed to bump from temp");
}
