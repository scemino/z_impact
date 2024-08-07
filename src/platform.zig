const sokol = @import("sokol");
const stm = sokol.time;
const sapp = sokol.app;
const types = @import("types");
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;

pub fn now() f64 {
    return stm.sec(stm.now());
}

pub fn screenSize() Vec2i {
    return vec2i(sapp.width(), sapp.height());
}
