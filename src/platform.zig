const std = @import("std");
const sokol = @import("sokol");
const stm = sokol.time;
const sapp = sokol.app;
const types = @import("types");
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const ObjectMap = std.json.ObjectMap;
const Array = std.json.Array;
const Value = std.json.Value;
const TempAllocator = @import("allocator.zig").TempAllocator;

pub fn now() f64 {
    return stm.sec(stm.now());
}

pub fn screenSize() Vec2i {
    return vec2i(sapp.width(), sapp.height());
}

pub fn loadAssetJson(name: []const u8) Value {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    var file = std.fs.cwd().openFile(name, .{}) catch @panic("failed to load asset");
    defer file.close();

    const reader = file.reader();
    const file_size = (file.stat() catch @panic("failed to load asset")).size;
    var temp_alloc = TempAllocator{};
    const buf = temp_alloc.allocator().alloc(u8, file_size) catch @panic("failed to load asset");
    _ = reader.readAll(buf) catch @panic("failed to load asset");

    const parsed = std.json.parseFromSlice(Value, gpa.allocator(), buf, .{}) catch @panic("error when parsing map");
    return parsed.value;
}
