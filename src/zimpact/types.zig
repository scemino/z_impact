const std = @import("std");

pub const Vec2 = struct {
    x: f32,
    y: f32,

    pub fn initAngle(a: f32) Vec2 {
        return .{ .x = std.math.cos(a), .y = std.math.sin(a) };
    }

    pub fn add(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x + b.x, .y = a.y + b.y };
    }

    pub fn sub(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x - b.x, .y = a.y - b.y };
    }

    pub fn mul(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x * b.x, .y = a.y * b.y };
    }

    pub fn div(a: Vec2, b: Vec2) Vec2 {
        return .{ .x = a.x / b.x, .y = a.y / b.y };
    }

    pub fn mulf(a: Vec2, f: f32) Vec2 {
        return .{ .x = a.x * f, .y = a.y * f };
    }

    pub fn toAngle(a: Vec2) f32 {
        return std.math.atan2(a.y, a.x);
    }

    pub fn divf(a: Vec2, f: f32) Vec2 {
        return vec2(a.x / f, a.y / f);
    }

    pub fn dot(a: Vec2, b: Vec2) f32 {
        return a.x * b.x + a.y * b.y;
    }

    pub fn abs(a: Vec2) Vec2 {
        return vec2(@abs(a.x), @abs(a.y));
    }

    pub fn len(a: Vec2) f32 {
        return @sqrt(a.x * a.x + a.y * a.y);
    }

    pub fn dist(a: Vec2, b: Vec2) f32 {
        return a.sub(b).len();
    }

    pub fn angle(a: Vec2, b: Vec2) f32 {
        const d = b.sub(a);
        return std.math.atan2(d.y, d.x);
    }

    pub fn transform(v: Vec2, m: Mat3) Vec2 {
        return vec2(m.a * v.x + m.b * v.y + m.tx, m.c * v.x + m.d * v.y + m.ty);
    }

    pub fn cross(a: Vec2, b: Vec2) f32 {
        return a.x * b.y - a.y * b.x;
    }
};

pub const Vec2i = struct {
    x: i32,
    y: i32,

    pub fn divi(a: Vec2i, f: i32) Vec2i {
        return vec2i(@divFloor(a.x, f), @divFloor(a.y, f));
    }

    pub fn muli(a: Vec2i, f: i32) Vec2i {
        return vec2i(a.x * f, a.y * f);
    }
};

pub fn fromAngle(a: f32) Vec2 {
    return vec2(std.math.cos(a), std.math.sin(a));
}

pub fn vec2(x: f32, y: f32) Vec2 {
    return .{ .x = x, .y = y };
}

pub fn vec2i(x: i32, y: i32) Vec2i {
    return .{ .x = x, .y = y };
}

pub fn fromVec2i(v: Vec2i) Vec2 {
    return .{ .x = @floatFromInt(v.x), .y = @floatFromInt(v.y) };
}

pub fn fromVec2(v: Vec2) Vec2i {
    return .{ .x = @intFromFloat(v.x), .y = @intFromFloat(v.y) };
}

pub const Mat3 = struct {
    a: f32,
    b: f32,
    c: f32,
    d: f32,
    tx: f32,
    ty: f32,

    pub fn translate(m: *Mat3, t: Vec2) void {
        m.tx += m.a * t.x + m.c * t.y;
        m.ty += m.b * t.x + m.d * t.y;
    }

    pub fn scale(m: *Mat3, r: Vec2) void {
        m.a *= r.x;
        m.b *= r.x;
        m.c *= r.y;
        m.d *= r.y;
    }

    pub fn rotate(m: *Mat3, r: f32) void {
        const sn = std.math.sin(r);
        const cs = std.math.cos(r);
        const a = m.a;
        const b = m.b;
        const c = m.c;
        const d = m.d;

        m.a = a * cs + c * sn;
        m.b = b * cs + d * sn;
        m.c = c * cs - a * sn;
        m.d = d * cs - b * sn;
    }
};

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

    pub inline fn setR(self: *Rgba, value: u8) void {
        self.components[0] = value;
    }

    pub inline fn setG(self: *Rgba, value: u8) void {
        self.components[1] = value;
    }

    pub inline fn setB(self: *Rgba, value: u8) void {
        self.components[2] = value;
    }

    pub inline fn setA(self: *Rgba, value: u8) void {
        self.components[3] = value;
    }

    pub inline fn toInt(self: Rgba) u32 {
        return std.mem.readInt(u32, self.components, .little);
    }
};

pub fn white() Rgba {
    return .{ .components = .{ 255, 255, 255, 255 } };
}

pub fn rgba(r: u8, g: u8, b: u8, a: u8) Rgba {
    return .{ .components = .{ r, g, b, a } };
}
