const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,
};

pub const Vec2i = struct {
    x: i32,
    y: i32,
};

pub fn vec2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

pub fn vec2i(x: i32, y: i32) Vec2i {
    return .{ .x = x, .y = y };
}

pub fn fromVec2i(v: Vec2i) Vec2 {
    return .{ .x = @floatFromInt(v.x), .y = @floatFromInt(v.y) };
}

pub const Mat3 = struct { a: f32, b: f32, c: f32, d: f32, tx: f32, ty: f32 };

pub const Rgba = struct {
    components: [4]u8,

    pub inline fn r(self: Rgba) u8 {
        return self.components[0];
    }

    pub inline fn g(self: Rgba) u8 {
        return self.components[1];
    }

    pub inline fn b(self: Rgba) u8 {
        return self.components[2];
    }

    pub inline fn a(self: Rgba) u8 {
        return self.components[3];
    }

    pub inline fn setR(self: Rgba, value: u8) void {
        self.components[0] = value;
    }

    pub inline fn setG(self: Rgba, value: u8) void {
        self.components[1] = value;
    }

    pub inline fn setB(self: Rgba, value: u8) void {
        self.components[2] = value;
    }

    pub inline fn setA(self: Rgba, value: u8) void {
        self.components[3] = value;
    }

    pub inline fn toInt(self: Rgba) u32 {
        return std.mem.readInt(u32, self.components, .little);
    }
};

pub fn white() Rgba {
    return .{ .components = .{ 255, 255, 255, 255 } };
}
