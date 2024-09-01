// namespaces
pub const alloc = @import("allocator.zig");
pub const cam = @import("camera.zig");
pub const engine = @import("engine.zig");
pub const entity = @import("entity.zig");
pub const fnt = @import("font.zig");
pub const img = @import("image.zig");
pub const input = @import("input.zig");
pub const map = @import("map.zig");
pub const noise = @import("noise.zig");
pub const options = @import("options.zig");
pub const platform = @import("platform.zig");
pub const render = @import("render.zig");
pub const scene = @import("scene.zig");
pub const sound = @import("sound.zig");
pub const trace = @import("trace.zig");
pub const types = @import("types.zig");
pub const utils = @import("utils.zig");

// functions
pub const anim = @import("anim.zig").anim;
pub const animDef = @import("anim.zig").animDef;
pub const font = fnt.font;
pub const image = img.image;
pub const fromVec2i = types.fromVec2i;
pub const white = types.white;
pub const rgba = types.rgba;
pub const vec2 = types.vec2;
pub const vec2i = types.vec2i;

// types
pub const Anim = @import("anim.zig").Anim;
pub const AnimDef = @import("anim.zig").AnimDef;
pub const Camera = cam.Camera;
pub const Engine = engine.Engine;
pub const Entity = entity.Entity;
pub const EntityVtab = entity.EntityVtab;
pub const EntityRef = entity.EntityRef;
pub const EntityList = entity.EntityList;
pub const Font = fnt.Font;
pub const Image = img.Image;
pub const Map = map.Map;
pub const Noise = noise.Noise;
pub const Scene = scene.Scene;
pub const Trace = trace.Trace;
pub const Vec2 = types.Vec2;
pub const Vec2i = types.Vec2i;
