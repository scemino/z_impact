const std = @import("std");
const types = @import("types");
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const assert = std.debug.assert;

const INPUT_ACTION_MAX = 32;
const INPUT_DEADZONE_CAPTURE = 0.5;

pub const Button = enum(u8) {
    INPUT_INVALID = 0,
    INPUT_KEY_A = 4,
    INPUT_KEY_B = 5,
    INPUT_KEY_C = 6,
    INPUT_KEY_D = 7,
    INPUT_KEY_E = 8,
    INPUT_KEY_F = 9,
    INPUT_KEY_G = 10,
    INPUT_KEY_H = 11,
    INPUT_KEY_I = 12,
    INPUT_KEY_J = 13,
    INPUT_KEY_K = 14,
    INPUT_KEY_L = 15,
    INPUT_KEY_M = 16,
    INPUT_KEY_N = 17,
    INPUT_KEY_O = 18,
    INPUT_KEY_P = 19,
    INPUT_KEY_Q = 20,
    INPUT_KEY_R = 21,
    INPUT_KEY_S = 22,
    INPUT_KEY_T = 23,
    INPUT_KEY_U = 24,
    INPUT_KEY_V = 25,
    INPUT_KEY_W = 26,
    INPUT_KEY_X = 27,
    INPUT_KEY_Y = 28,
    INPUT_KEY_Z = 29,
    INPUT_KEY_1 = 30,
    INPUT_KEY_2 = 31,
    INPUT_KEY_3 = 32,
    INPUT_KEY_4 = 33,
    INPUT_KEY_5 = 34,
    INPUT_KEY_6 = 35,
    INPUT_KEY_7 = 36,
    INPUT_KEY_8 = 37,
    INPUT_KEY_9 = 38,
    INPUT_KEY_0 = 39,
    INPUT_KEY_RETURN = 40,
    INPUT_KEY_ESCAPE = 41,
    INPUT_KEY_BACKSPACE = 42,
    INPUT_KEY_TAB = 43,
    INPUT_KEY_SPACE = 44,
    INPUT_KEY_MINUS = 45,
    INPUT_KEY_EQUALS = 46,
    INPUT_KEY_LEFTBRACKET = 47,
    INPUT_KEY_RIGHTBRACKET = 48,
    INPUT_KEY_BACKSLASH = 49,
    INPUT_KEY_HASH = 50,
    INPUT_KEY_SEMICOLON = 51,
    INPUT_KEY_APOSTROPHE = 52,
    INPUT_KEY_TILDE = 53,
    INPUT_KEY_COMMA = 54,
    INPUT_KEY_PERIOD = 55,
    INPUT_KEY_SLASH = 56,
    INPUT_KEY_CAPSLOCK = 57,
    INPUT_KEY_F1 = 58,
    INPUT_KEY_F2 = 59,
    INPUT_KEY_F3 = 60,
    INPUT_KEY_F4 = 61,
    INPUT_KEY_F5 = 62,
    INPUT_KEY_F6 = 63,
    INPUT_KEY_F7 = 64,
    INPUT_KEY_F8 = 65,
    INPUT_KEY_F9 = 66,
    INPUT_KEY_F10 = 67,
    INPUT_KEY_F11 = 68,
    INPUT_KEY_F12 = 69,
    INPUT_KEY_PRINTSCREEN = 70,
    INPUT_KEY_SCROLLLOCK = 71,
    INPUT_KEY_PAUSE = 72,
    INPUT_KEY_INSERT = 73,
    INPUT_KEY_HOME = 74,
    INPUT_KEY_PAGEUP = 75,
    INPUT_KEY_DELETE = 76,
    INPUT_KEY_END = 77,
    INPUT_KEY_PAGEDOWN = 78,
    INPUT_KEY_RIGHT = 79,
    INPUT_KEY_LEFT = 80,
    INPUT_KEY_DOWN = 81,
    INPUT_KEY_UP = 82,
    INPUT_KEY_NUMLOCK = 83,
    INPUT_KEY_KP_DIVIDE = 84,
    INPUT_KEY_KP_MULTIPLY = 85,
    INPUT_KEY_KP_MINUS = 86,
    INPUT_KEY_KP_PLUS = 87,
    INPUT_KEY_KP_ENTER = 88,
    INPUT_KEY_KP_1 = 89,
    INPUT_KEY_KP_2 = 90,
    INPUT_KEY_KP_3 = 91,
    INPUT_KEY_KP_4 = 92,
    INPUT_KEY_KP_5 = 93,
    INPUT_KEY_KP_6 = 94,
    INPUT_KEY_KP_7 = 95,
    INPUT_KEY_KP_8 = 96,
    INPUT_KEY_KP_9 = 97,
    INPUT_KEY_KP_0 = 98,
    INPUT_KEY_KP_PERIOD = 99,
    INPUT_KEY_L_CTRL = 100,
    INPUT_KEY_L_SHIFT = 101,
    INPUT_KEY_L_ALT = 102,
    INPUT_KEY_L_GUI = 103,
    INPUT_KEY_R_CTRL = 104,
    INPUT_KEY_R_SHIFT = 105,
    INPUT_KEY_R_ALT = 106,
    INPUT_KEY_MAX = 107,
    INPUT_GAMEPAD_A = 108,
    INPUT_GAMEPAD_Y = 109,
    INPUT_GAMEPAD_B = 110,
    INPUT_GAMEPAD_X = 111,
    INPUT_GAMEPAD_L_SHOULDER = 112,
    INPUT_GAMEPAD_R_SHOULDER = 113,
    INPUT_GAMEPAD_L_TRIGGER = 114,
    INPUT_GAMEPAD_R_TRIGGER = 115,
    INPUT_GAMEPAD_SELECT = 116,
    INPUT_GAMEPAD_START = 117,
    INPUT_GAMEPAD_L_STICK_PRESS = 118,
    INPUT_GAMEPAD_R_STICK_PRESS = 119,
    INPUT_GAMEPAD_DPAD_UP = 120,
    INPUT_GAMEPAD_DPAD_DOWN = 121,
    INPUT_GAMEPAD_DPAD_LEFT = 122,
    INPUT_GAMEPAD_DPAD_RIGHT = 123,
    INPUT_GAMEPAD_HOME = 124,
    INPUT_GAMEPAD_L_STICK_UP = 125,
    INPUT_GAMEPAD_L_STICK_DOWN = 126,
    INPUT_GAMEPAD_L_STICK_LEFT = 127,
    INPUT_GAMEPAD_L_STICK_RIGHT = 128,
    INPUT_GAMEPAD_R_STICK_UP = 129,
    INPUT_GAMEPAD_R_STICK_DOWN = 130,
    INPUT_GAMEPAD_R_STICK_LEFT = 131,
    INPUT_GAMEPAD_R_STICK_RIGHT = 132,
    INPUT_MOUSE_LEFT = 134,
    INPUT_MOUSE_MIDDLE = 135,
    INPUT_MOUSE_RIGHT = 136,
    INPUT_MOUSE_WHEEL_UP = 137,
    INPUT_MOUSE_WHEEL_DOWN = 138,
};
const INPUT_BUTTON_MAX: usize = 139;
const INPUT_ACTION_NONE: u8 = 255;
const INPUT_BUTTON_NONE: u8 = 0;
const INPUT_DEADZONE: f32 = 0.1;

var expected_button: [INPUT_BUTTON_MAX]u8 = [1]u8{0} ** INPUT_BUTTON_MAX;
var actions_state: [INPUT_BUTTON_MAX]f32 = [1]f32{0} ** INPUT_BUTTON_MAX;
var actions_pressed: [INPUT_BUTTON_MAX]bool = [1]bool{false} ** INPUT_BUTTON_MAX;
var actions_released: [INPUT_BUTTON_MAX]bool = [1]bool{false} ** INPUT_BUTTON_MAX;
var bindings: [INPUT_BUTTON_MAX]u8 = [1]u8{0} ** INPUT_BUTTON_MAX;
var mouse_x: i32 = 0;
var mouse_y: i32 = 0;

/// Returns the current state for an action. For discrete buttons and keyboard
/// keys, this is either 0 or 1. For analog input, it is anywhere between
/// 0..1.
pub fn statef(action: u8) f32 {
    assert(action < INPUT_ACTION_MAX); // "Invalid input action %d", action;
    return actions_state[action];
}

/// Returns the current state for an action. For discrete buttons and keyboard
/// keys, this is either false or true.
pub fn stateb(action: u8) bool {
    return statef(action) > 0;
}

/// Whether a button for that action was just pressed down before this frame
pub fn pressed(action: u8) bool {
    return actions_pressed[action];
}

/// Whether a button for that action was just released bofere this frame
pub fn released(action: u8) bool {
    return actions_released[action];
}

/// The current mouse position in real pixels
pub fn mousePos() Vec2 {
    return vec2(mouse_x, mouse_y);
}

/// Called by the platform
pub fn setMousePos(x: i32, y: i32) void {
    mouse_x = x;
    mouse_y = y;
}

/// Called by the platform
pub fn clear() void {
    actions_pressed = [1]bool{false} ** INPUT_BUTTON_MAX;
    actions_released = [1]bool{false} ** INPUT_BUTTON_MAX;
}

/// Called by the platform
pub fn setButtonState(button: Button, s: f32) void {
    var state = s;
    const action = bindings[@intCast(@intFromEnum(button))];
    if (action == INPUT_ACTION_NONE) {
        return;
    }

    const expected = expected_button[action];
    if (expected == 0 or expected == @as(u8, @intCast(@intFromEnum(button)))) {
        state = if (state > INPUT_DEADZONE) state else 0;

        if (state != 0 and actions_state[action] == 0) {
            actions_pressed[action] = true;
            expected_button[action] = @intFromEnum(button);
        } else if (state == 0 and actions_state[action] > 0) {
            actions_released[action] = true;
            expected_button[action] = INPUT_BUTTON_NONE;
        }
        actions_state[action] = state;
    }

    if (capture_callback) |cb| {
        if (state > INPUT_DEADZONE_CAPTURE) {
            cb(capture_user, button, 0);
        }
    }
}

/// Bind a key/button to an action. Multiple buttons can be bound to the same
/// action, but one key/button can only be bound to one action. Action is just
/// a uint8_t identifier, usually from an enum in your game.
pub fn bind(button: Button, action: u8) void {
    // error_if(button < 0 || button >= INPUT_BUTTON_MAX, "Invalid input button %d", button);
    // error_if(action < 0 || action >= INPUT_ACTION_MAX, "Invalid input action %d", action);

    actions_state[action] = 0;
    bindings[@intCast(@intFromEnum(button))] = action;
}

/// Unbind a key/button
pub fn unbind(button: Button) void {
    bindings[button] = INPUT_ACTION_NONE;
}

/// Unbind all keys/buttons
pub fn unbindAll() void {
    for (0..INPUT_BUTTON_MAX) |i| {
        unbind(@enumFromInt(i));
    }
}

// Set up a capture callback that will receive ALL key and button presses. For
// non-text input, ascii_char will be 0. Call input_capture(NULL, NULL) to
// uninstall a callback.
const CaptureCallback = *fn (user: ?*anyopaque, button: Button, ascii_char: u32) void;
var capture_callback: ?CaptureCallback = null;
var capture_user: ?*anyopaque = null;

pub fn capture(cb: CaptureCallback, user: ?*anyopaque) void {
    capture_callback = cb;
    capture_user = user;
    clear();
}

pub fn textInput(ascii_char: u32) void {
    if (capture_callback) |cb| {
        cb(capture_user, .INPUT_INVALID, ascii_char);
    }
}
