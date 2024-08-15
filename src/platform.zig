const std = @import("std");
const assert = std.debug.assert;
const sokol = @import("sokol");
const stm = sokol.time;
const sapp = sokol.app;
const saudio = sokol.audio;
const types = @import("types.zig");
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const ObjectMap = std.json.ObjectMap;
const Array = std.json.Array;
const Value = std.json.Value;
const Parsed = std.json.Parsed;
const TempAllocator = @import("allocator.zig").TempAllocator;
const input = @import("input.zig");
const Button = input.Button;

var platform_output_samplerate: u32 = 44100;
var audio_callback: ?*const fn (buffer: []f32) void = null;

const keyboard_map: [349]Button = keyboard_map_init();

fn keyboard_map_init() [349]Button {
    var btns: [349]Button = undefined;
    btns[@intCast(@intFromEnum(sapp.Keycode.SPACE))] = .INPUT_KEY_SPACE;
    btns[@intCast(@intFromEnum(sapp.Keycode.APOSTROPHE))] = .INPUT_KEY_APOSTROPHE;
    btns[@intCast(@intFromEnum(sapp.Keycode.COMMA))] = .INPUT_KEY_COMMA;
    btns[@intCast(@intFromEnum(sapp.Keycode.MINUS))] = .INPUT_KEY_MINUS;
    btns[@intCast(@intFromEnum(sapp.Keycode.PERIOD))] = .INPUT_KEY_PERIOD;
    btns[@intCast(@intFromEnum(sapp.Keycode.SLASH))] = .INPUT_KEY_SLASH;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_0))] = .INPUT_KEY_0;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_1))] = .INPUT_KEY_1;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_2))] = .INPUT_KEY_2;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_3))] = .INPUT_KEY_3;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_4))] = .INPUT_KEY_4;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_5))] = .INPUT_KEY_5;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_6))] = .INPUT_KEY_6;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_7))] = .INPUT_KEY_7;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_8))] = .INPUT_KEY_8;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_9))] = .INPUT_KEY_9;
    btns[@intCast(@intFromEnum(sapp.Keycode.SEMICOLON))] = .INPUT_KEY_SEMICOLON;
    btns[@intCast(@intFromEnum(sapp.Keycode.EQUAL))] = .INPUT_KEY_EQUALS;
    btns[@intCast(@intFromEnum(sapp.Keycode.A))] = .INPUT_KEY_A;
    btns[@intCast(@intFromEnum(sapp.Keycode.B))] = .INPUT_KEY_B;
    btns[@intCast(@intFromEnum(sapp.Keycode.C))] = .INPUT_KEY_C;
    btns[@intCast(@intFromEnum(sapp.Keycode.D))] = .INPUT_KEY_D;
    btns[@intCast(@intFromEnum(sapp.Keycode.E))] = .INPUT_KEY_E;
    btns[@intCast(@intFromEnum(sapp.Keycode.F))] = .INPUT_KEY_F;
    btns[@intCast(@intFromEnum(sapp.Keycode.G))] = .INPUT_KEY_G;
    btns[@intCast(@intFromEnum(sapp.Keycode.H))] = .INPUT_KEY_H;
    btns[@intCast(@intFromEnum(sapp.Keycode.I))] = .INPUT_KEY_I;
    btns[@intCast(@intFromEnum(sapp.Keycode.J))] = .INPUT_KEY_J;
    btns[@intCast(@intFromEnum(sapp.Keycode.K))] = .INPUT_KEY_K;
    btns[@intCast(@intFromEnum(sapp.Keycode.L))] = .INPUT_KEY_L;
    btns[@intCast(@intFromEnum(sapp.Keycode.M))] = .INPUT_KEY_M;
    btns[@intCast(@intFromEnum(sapp.Keycode.N))] = .INPUT_KEY_N;
    btns[@intCast(@intFromEnum(sapp.Keycode.O))] = .INPUT_KEY_O;
    btns[@intCast(@intFromEnum(sapp.Keycode.P))] = .INPUT_KEY_P;
    btns[@intCast(@intFromEnum(sapp.Keycode.Q))] = .INPUT_KEY_Q;
    btns[@intCast(@intFromEnum(sapp.Keycode.R))] = .INPUT_KEY_R;
    btns[@intCast(@intFromEnum(sapp.Keycode.S))] = .INPUT_KEY_S;
    btns[@intCast(@intFromEnum(sapp.Keycode.T))] = .INPUT_KEY_T;
    btns[@intCast(@intFromEnum(sapp.Keycode.U))] = .INPUT_KEY_U;
    btns[@intCast(@intFromEnum(sapp.Keycode.V))] = .INPUT_KEY_V;
    btns[@intCast(@intFromEnum(sapp.Keycode.W))] = .INPUT_KEY_W;
    btns[@intCast(@intFromEnum(sapp.Keycode.X))] = .INPUT_KEY_X;
    btns[@intCast(@intFromEnum(sapp.Keycode.Y))] = .INPUT_KEY_Y;
    btns[@intCast(@intFromEnum(sapp.Keycode.Z))] = .INPUT_KEY_Z;
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT_BRACKET))] = .INPUT_KEY_LEFTBRACKET;
    btns[@intCast(@intFromEnum(sapp.Keycode.BACKSLASH))] = .INPUT_KEY_BACKSLASH;
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT_BRACKET))] = .INPUT_KEY_RIGHTBRACKET;
    btns[@intCast(@intFromEnum(sapp.Keycode.GRAVE_ACCENT))] = .INPUT_KEY_TILDE;
    btns[@intCast(@intFromEnum(sapp.Keycode.WORLD_1))] = .INPUT_INVALID; // not implemented
    btns[@intCast(@intFromEnum(sapp.Keycode.WORLD_2))] = .INPUT_INVALID; // not implemented
    btns[@intCast(@intFromEnum(sapp.Keycode.ESCAPE))] = .INPUT_KEY_ESCAPE;
    btns[@intCast(@intFromEnum(sapp.Keycode.ENTER))] = .INPUT_KEY_RETURN;
    btns[@intCast(@intFromEnum(sapp.Keycode.TAB))] = .INPUT_KEY_TAB;
    btns[@intCast(@intFromEnum(sapp.Keycode.BACKSPACE))] = .INPUT_KEY_BACKSPACE;
    btns[@intCast(@intFromEnum(sapp.Keycode.INSERT))] = .INPUT_KEY_INSERT;
    btns[@intCast(@intFromEnum(sapp.Keycode.DELETE))] = .INPUT_KEY_DELETE;
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT))] = .INPUT_KEY_RIGHT;
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT))] = .INPUT_KEY_LEFT;
    btns[@intCast(@intFromEnum(sapp.Keycode.DOWN))] = .INPUT_KEY_DOWN;
    btns[@intCast(@intFromEnum(sapp.Keycode.UP))] = .INPUT_KEY_UP;
    btns[@intCast(@intFromEnum(sapp.Keycode.PAGE_UP))] = .INPUT_KEY_PAGEUP;
    btns[@intCast(@intFromEnum(sapp.Keycode.PAGE_DOWN))] = .INPUT_KEY_PAGEDOWN;
    btns[@intCast(@intFromEnum(sapp.Keycode.HOME))] = .INPUT_KEY_HOME;
    btns[@intCast(@intFromEnum(sapp.Keycode.END))] = .INPUT_KEY_END;
    btns[@intCast(@intFromEnum(sapp.Keycode.CAPS_LOCK))] = .INPUT_KEY_CAPSLOCK;
    btns[@intCast(@intFromEnum(sapp.Keycode.SCROLL_LOCK))] = .INPUT_KEY_SCROLLLOCK;
    btns[@intCast(@intFromEnum(sapp.Keycode.NUM_LOCK))] = .INPUT_KEY_NUMLOCK;
    btns[@intCast(@intFromEnum(sapp.Keycode.PRINT_SCREEN))] = .INPUT_KEY_PRINTSCREEN;
    btns[@intCast(@intFromEnum(sapp.Keycode.PAUSE))] = .INPUT_KEY_PAUSE;
    btns[@intCast(@intFromEnum(sapp.Keycode.F1))] = .INPUT_KEY_F1;
    btns[@intCast(@intFromEnum(sapp.Keycode.F2))] = .INPUT_KEY_F2;
    btns[@intCast(@intFromEnum(sapp.Keycode.F3))] = .INPUT_KEY_F3;
    btns[@intCast(@intFromEnum(sapp.Keycode.F4))] = .INPUT_KEY_F4;
    btns[@intCast(@intFromEnum(sapp.Keycode.F5))] = .INPUT_KEY_F5;
    btns[@intCast(@intFromEnum(sapp.Keycode.F6))] = .INPUT_KEY_F6;
    btns[@intCast(@intFromEnum(sapp.Keycode.F7))] = .INPUT_KEY_F7;
    btns[@intCast(@intFromEnum(sapp.Keycode.F8))] = .INPUT_KEY_F8;
    btns[@intCast(@intFromEnum(sapp.Keycode.F9))] = .INPUT_KEY_F9;
    btns[@intCast(@intFromEnum(sapp.Keycode.F10))] = .INPUT_KEY_F10;
    btns[@intCast(@intFromEnum(sapp.Keycode.F11))] = .INPUT_KEY_F11;
    btns[@intCast(@intFromEnum(sapp.Keycode.F12))] = .INPUT_KEY_F12;
    btns[@intCast(@intFromEnum(sapp.Keycode.F13))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F14))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F15))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F16))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F17))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F18))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F19))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F20))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F21))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F22))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F23))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F24))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.F25))] = .INPUT_INVALID; // not implement
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_0))] = .INPUT_KEY_KP_0;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_1))] = .INPUT_KEY_KP_1;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_2))] = .INPUT_KEY_KP_2;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_3))] = .INPUT_KEY_KP_3;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_4))] = .INPUT_KEY_KP_4;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_5))] = .INPUT_KEY_KP_5;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_6))] = .INPUT_KEY_KP_6;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_7))] = .INPUT_KEY_KP_7;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_8))] = .INPUT_KEY_KP_8;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_9))] = .INPUT_KEY_KP_9;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_DECIMAL))] = .INPUT_KEY_KP_PERIOD;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_DIVIDE))] = .INPUT_KEY_KP_DIVIDE;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_MULTIPLY))] = .INPUT_KEY_KP_MULTIPLY;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_SUBTRACT))] = .INPUT_KEY_KP_MINUS;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_ADD))] = .INPUT_KEY_KP_PLUS;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_ENTER))] = .INPUT_KEY_KP_ENTER;
    btns[@intCast(@intFromEnum(sapp.Keycode.KP_EQUAL))] = .INPUT_INVALID; // not implemented
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT_SHIFT))] = .INPUT_KEY_L_SHIFT;
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT_CONTROL))] = .INPUT_KEY_L_CTRL;
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT_ALT))] = .INPUT_KEY_L_ALT;
    btns[@intCast(@intFromEnum(sapp.Keycode.LEFT_SUPER))] = .INPUT_INVALID; // not implemented
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT_SHIFT))] = .INPUT_KEY_R_SHIFT;
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT_CONTROL))] = .INPUT_KEY_R_CTRL;
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT_ALT))] = .INPUT_KEY_R_ALT;
    btns[@intCast(@intFromEnum(sapp.Keycode.RIGHT_SUPER))] = .INPUT_INVALID; // not implemented
    btns[@intCast(@intFromEnum(sapp.Keycode.MENU))] = .INPUT_INVALID; // not implemented
    return btns;
}

pub fn init() void {
    saudio.setup(.{
        .sample_rate = @intCast(platform_output_samplerate),
        .buffer_frames = 1024,
        .num_channels = 2,
        .stream_cb = platform_audio_callback,
    });

    // Might be different from requested rate
    platform_output_samplerate = @intCast(saudio.sampleRate());
}

pub fn now() f64 {
    return stm.sec(stm.now());
}

pub fn screenSize() Vec2i {
    return vec2i(sapp.width(), sapp.height());
}

pub fn samplerate() u32 {
    return platform_output_samplerate;
}

pub fn loadAsset(name: []const u8, allocator: std.mem.Allocator) []u8 {
    var file = std.fs.cwd().openFile(name, .{}) catch @panic("failed to load asset");
    defer file.close();

    const reader = file.reader();
    const file_size = (file.stat() catch @panic("failed to load asset")).size;
    const buf = allocator.alloc(u8, file_size) catch @panic("failed to load asset");
    _ = reader.readAll(buf) catch @panic("failed to load asset");

    return buf;
}

pub fn loadAssetJson(name: []const u8, allocator: std.mem.Allocator) Parsed(Value) {
    var temp_alloc = TempAllocator{};
    const buf = loadAsset(name, temp_alloc.allocator());
    defer temp_alloc.allocator().free(buf);

    const parsed = std.json.parseFromSlice(Value, allocator, buf, .{}) catch @panic("error when parsing map");
    return parsed;
}

fn setFullscreen(fullscreen: bool) void {
    if (fullscreen == sapp.isFullscreen()) {
        return;
    }

    sapp.toggleFullscreen();
    sapp.showMouse(!fullscreen);
}

pub export fn platform_handle_event(ev: [*c]const sapp.Event) void {
    // Detect ALT+Enter press to toggle fullscreen
    if (ev.*.type == .KEY_DOWN and
        ev.*.key_code == .ENTER and
        ((ev.*.modifiers & sapp.modifier_alt) != 0))
    {
        setFullscreen(!sapp.isFullscreen());
    }

    // Input Keyboard
    else if (ev.*.type == sapp.EventType.KEY_DOWN or ev.*.type == sapp.EventType.KEY_UP) {
        const state: f32 = if (ev.*.type == sapp.EventType.KEY_DOWN) 1.0 else 0.0;
        const code: Button = keyboard_map[@intCast(@intFromEnum(ev.*.key_code))];
        input.setButtonState(code, state);
    } else if (ev.*.type == sapp.EventType.CHAR) {
        // TODO: input_textinput(ev.char_code);
    }

    // Input Gamepad Axis
    // TODO: not implemented by sokol_app itself

    // Mouse buttons
    // else if (
    // 	ev.type == SAPP_EVENTTYPE_MOUSE_DOWN or
    // 	ev.type == SAPP_EVENTTYPE_MOUSE_UP
    // ) {
    // 	button_t button = INPUT_BUTTON_NONE;
    // 	switch (ev.mouse_button) {
    // 		case SAPP_MOUSEBUTTON_LEFT: button = INPUT_MOUSE_LEFT; break;
    // 		case SAPP_MOUSEBUTTON_MIDDLE: button = INPUT_MOUSE_MIDDLE; break;
    // 		case SAPP_MOUSEBUTTON_RIGHT: button = INPUT_MOUSE_RIGHT; break;
    // 		default: break;
    // 	}
    // 	if (button != INPUT_BUTTON_NONE) {
    // 		float state = ev.type == SAPP_EVENTTYPE_MOUSE_DOWN ? 1.0 : 0.0;
    // 		input_set_button_state(button, state);
    // 	}
    // }

    // // Mouse wheel
    // else if (ev.type == SAPP_EVENTTYPE_MOUSE_SCROLL) {
    // 	button_t button = ev.scroll_y > 0
    // 		? INPUT_MOUSE_WHEEL_UP
    // 		: INPUT_MOUSE_WHEEL_DOWN;
    // 	input_set_button_state(button, 1.0);
    // 	input_set_button_state(button, 0.0);
    // }

    // // Mouse move
    // else if (ev.type == SAPP_EVENTTYPE_MOUSE_MOVE) {
    // 	input_set_mouse_pos(ev.mouse_x, ev.mouse_y);
    // }

    // // Window Events
    // if (ev.type == SAPP_EVENTTYPE_RESIZED) {
    // 	engine_resize(vec2i(ev.window_width, ev.window_height));
    // }
}

fn platform_audio_callback(buffer: [*c]f32, num_frames: i32, num_channels: i32) callconv(.C) void {
    if (audio_callback) |cb| {
        cb(buffer[0..@intCast(num_frames * num_channels)]);
    } else {
        @memset(buffer[0..@intCast(num_frames * num_channels)], 0);
    }
}

pub fn setAudioMixCb(cb: *const fn (buffer: []f32) void) void {
    audio_callback = cb;
}
