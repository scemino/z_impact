const std = @import("std");
const assert = std.debug.assert;
const Allocator = std.mem.Allocator;

const ALLOC_SIZE = 32 * 1024 * 1024;
var hunk: [ALLOC_SIZE]u8 = [1]u8{0} ** ALLOC_SIZE;
var bump_len: usize = 0;
var temp_len: usize = 0;

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
        assert(bump_len + temp_len + len < ALLOC_SIZE);
        bump_len += len;
        @memset(hunk[bump_len..], 0);
        return hunk[bump_len..].ptr;
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

pub fn bumpAlloc(size: usize) ![]u8 {
    var bump_alloc = BumpAllocator{};
    return bump_alloc.allocator().alloc(u8, size);
}
