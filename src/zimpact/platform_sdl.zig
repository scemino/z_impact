const std = @import("std");
const builtin = @import("builtin");
const assert = std.debug.assert;
pub const cmn = @import("common");
const types = cmn.types;
const Vec2i = types.Vec2i;
const vec2i = types.vec2i;
const ObjectMap = std.json.ObjectMap;
const Array = std.json.Array;
const Value = std.json.Value;
const Parsed = std.json.Parsed;
const alloc = cmn.alloc;
const TempAllocator = alloc.TempAllocator;
const input = cmn.inp;
pub const render = @import("render_gl.zig");
const options = cmn.opt;
const sdl = @import("sdl");
const gl = @import("gl3v3.zig");
const Button = input.Button;

pub const Desc = struct {
    update_cb: ?*const fn () void = null,
    init_cb: ?*const fn () void = null,
    cleanup_cb: ?*const fn () void = null,
    window_size: Vec2i = types.vec2i(1280, 720),
};

var desc: Desc = undefined;
var wants_to_exit = false;
var window: *sdl.SDL_Window = undefined;
var perf_freq: u64 = undefined;
var platform_output_samplerate: u32 = 44100;
var audio_callback: ?*const fn (buffer: []f32) void = null;
var gamepad: ?*sdl.SDL_GameController = null;
var audio_device: sdl.SDL_AudioDeviceID = undefined;
var bin_dir: std.fs.Dir = undefined;

const gamepad_map: [sdl.SDL_CONTROLLER_BUTTON_MAX]Button = initGamePadMap();
const axis_map: [sdl.SDL_CONTROLLER_AXIS_MAX]Button = initAxisMap();

fn initGamePadMap() [sdl.SDL_CONTROLLER_BUTTON_MAX]Button {
    var map: [sdl.SDL_CONTROLLER_BUTTON_MAX]Button = [1]Button{.INPUT_INVALID} ** sdl.SDL_CONTROLLER_BUTTON_MAX;
    map[sdl.SDL_CONTROLLER_BUTTON_A] = .INPUT_GAMEPAD_A;
    map[sdl.SDL_CONTROLLER_BUTTON_B] = .INPUT_GAMEPAD_B;
    map[sdl.SDL_CONTROLLER_BUTTON_X] = .INPUT_GAMEPAD_X;
    map[sdl.SDL_CONTROLLER_BUTTON_Y] = .INPUT_GAMEPAD_Y;
    map[sdl.SDL_CONTROLLER_BUTTON_BACK] = .INPUT_GAMEPAD_SELECT;
    map[sdl.SDL_CONTROLLER_BUTTON_GUIDE] = .INPUT_GAMEPAD_HOME;
    map[sdl.SDL_CONTROLLER_BUTTON_START] = .INPUT_GAMEPAD_START;
    map[sdl.SDL_CONTROLLER_BUTTON_LEFTSTICK] = .INPUT_GAMEPAD_L_STICK_PRESS;
    map[sdl.SDL_CONTROLLER_BUTTON_RIGHTSTICK] = .INPUT_GAMEPAD_R_STICK_PRESS;
    map[sdl.SDL_CONTROLLER_BUTTON_LEFTSHOULDER] = .INPUT_GAMEPAD_L_SHOULDER;
    map[sdl.SDL_CONTROLLER_BUTTON_RIGHTSHOULDER] = .INPUT_GAMEPAD_R_SHOULDER;
    map[sdl.SDL_CONTROLLER_BUTTON_DPAD_UP] = .INPUT_GAMEPAD_DPAD_UP;
    map[sdl.SDL_CONTROLLER_BUTTON_DPAD_DOWN] = .INPUT_GAMEPAD_DPAD_DOWN;
    map[sdl.SDL_CONTROLLER_BUTTON_DPAD_LEFT] = .INPUT_GAMEPAD_DPAD_LEFT;
    map[sdl.SDL_CONTROLLER_BUTTON_DPAD_RIGHT] = .INPUT_GAMEPAD_DPAD_RIGHT;
    return map;
}

fn initAxisMap() [sdl.SDL_CONTROLLER_AXIS_MAX]Button {
    var map: [sdl.SDL_CONTROLLER_AXIS_MAX]Button = [1]Button{.INPUT_INVALID} ** sdl.SDL_CONTROLLER_AXIS_MAX;
    map[sdl.SDL_CONTROLLER_AXIS_LEFTX] = .INPUT_GAMEPAD_L_STICK_LEFT;
    map[sdl.SDL_CONTROLLER_AXIS_LEFTY] = .INPUT_GAMEPAD_L_STICK_UP;
    map[sdl.SDL_CONTROLLER_AXIS_RIGHTX] = .INPUT_GAMEPAD_R_STICK_LEFT;
    map[sdl.SDL_CONTROLLER_AXIS_RIGHTY] = .INPUT_GAMEPAD_R_STICK_UP;
    map[sdl.SDL_CONTROLLER_AXIS_TRIGGERLEFT] = .INPUT_GAMEPAD_L_TRIGGER;
    map[sdl.SDL_CONTROLLER_AXIS_TRIGGERRIGHT] = .INPUT_GAMEPAD_R_TRIGGER;
    return map;
}

fn init() void {
    perf_freq = sdl.SDL_GetPerformanceFrequency();

    if (builtin.os.tag == .emscripten) {
        bin_dir = std.fs.cwd();
    } else {
        // get the binary directory where the executable is located, it will be used to load assets from this directory
        var ba = alloc.BumpAllocator{};
        const exe_path = std.fs.selfExePathAlloc(ba.allocator()) catch @panic("failed to get exe path");
        defer ba.allocator().free(exe_path);
        bin_dir = std.fs.cwd().openDir(std.fs.path.dirname(exe_path).?, .{}) catch @panic("failed open bin dir");
    }
}

/// Return the current time in seconds since program start
pub fn now() f64 {
    const perf_counter = sdl.SDL_GetPerformanceCounter();
    return @as(f64, @floatFromInt(perf_counter)) / @as(f64, @floatFromInt(perf_freq));
}

/// Return the current size of the window or render area in real pixels
pub fn screenSize() Vec2i {
    var width: c_int = undefined;
    var height: c_int = undefined;
    sdl.SDL_GL_GetDrawableSize(window, &width, &height);
    return vec2i(width, height);
}

/// Returns the samplerate of the audio output
pub fn samplerate() u32 {
    return platform_output_samplerate;
}

/// Load a file into temp memory. Must be freed via `ta.allocator.free()`
pub fn loadAsset(name: []const u8, allocator: std.mem.Allocator) []u8 {
    var file = bin_dir.openFile(name, .{}) catch @panic("failed to load asset");
    defer file.close();

    const reader = file.reader();
    const file_size: usize = @intCast((file.stat() catch @panic("failed to load asset")).size);
    const buf = allocator.alloc(u8, file_size) catch @panic("failed to load asset");
    _ = reader.readAll(buf) catch @panic("failed to load asset");

    return buf;
}

/// Load a json file into temp memory. Must be freed via `ta.allocator.free()`
pub fn loadAssetJson(name: []const u8, allocator: std.mem.Allocator) Parsed(Value) {
    var temp_alloc = TempAllocator{};
    const buf = loadAsset(name, temp_alloc.allocator());
    defer temp_alloc.allocator().free(buf);

    const parsed = std.json.parseFromSlice(Value, allocator, buf, .{}) catch @panic("error when parsing map");
    return parsed;
}

/// Sets the audio mix callback; done by the engine
pub fn setAudioMixCb(cb: *const fn (buffer: []f32) void) void {
    audio_callback = cb;
    sdl.SDL_PauseAudioDevice(audio_device, 0);
}

/// Set the fullscreen mode
pub fn setFullscreen(fullscreen: bool) void {
    if (fullscreen) {
        const display = sdl.SDL_GetWindowDisplayIndex(window);

        var mode: sdl.SDL_DisplayMode = undefined;
        _ = sdl.SDL_GetDesktopDisplayMode(display, &mode);
        _ = sdl.SDL_SetWindowDisplayMode(window, &mode);
        _ = sdl.SDL_SetWindowFullscreen(window, sdl.SDL_WINDOW_FULLSCREEN);
        _ = sdl.SDL_ShowCursor(sdl.SDL_DISABLE);
    } else {
        _ = sdl.SDL_SetWindowFullscreen(window, 0);
        _ = sdl.SDL_ShowCursor(sdl.SDL_ENABLE);
    }
}

/// Whether the program is in fullscreen mode
pub fn getFullscreen() bool {
    return (sdl.SDL_GetWindowFlags(window) & sdl.SDL_WINDOW_FULLSCREEN) == sdl.SDL_WINDOW_FULLSCREEN;
}

fn platformAudioCallback(_: ?*anyopaque, stream: [*c]u8, l: c_int) callconv(.C) void {
    const len = @as(usize, @intCast(l));
    if (audio_callback) |cb| {
        const samples: []f32 = @as([*]f32, @alignCast(@ptrCast(stream)))[0..@divTrunc(len, @sizeOf(f32))];
        cb(samples);
    } else {
        @memset(stream[0..len], 0);
    }
}

export fn app_init() void {
    desc.init_cb.?();
}

export fn app_update() void {
    desc.update_cb.?();
}

export fn app_cleanup() void {
    bin_dir.close();
    desc.cleanup_cb.?();
}

fn findGamepad() ?*sdl.SDL_GameController {
    for (0..@intCast(sdl.SDL_NumJoysticks())) |i| {
        if (sdl.SDL_IsGameController(@intCast(i)) != 0) {
            return sdl.SDL_GameControllerOpen(@intCast(i));
        }
    }

    return null;
}

fn pumpEvents() void {
    var ev: sdl.SDL_Event = undefined;
    while (sdl.SDL_PollEvent(&ev) != 0) {
        // Detect ALT+Enter press to toggle fullscreen
        if (ev.type == sdl.SDL_KEYDOWN and
            ev.key.keysym.scancode == sdl.SDL_SCANCODE_RETURN and
            (ev.key.keysym.mod & (sdl.KMOD_LALT | sdl.KMOD_RALT) != 0))
        {
            setFullscreen(!getFullscreen());
        }

        // Input Keyboard
        else if (ev.type == sdl.SDL_KEYDOWN or ev.type == sdl.SDL_KEYUP) {
            const code = ev.key.keysym.scancode;
            const state: f32 = if (ev.type == sdl.SDL_KEYDOWN) 1.0 else 0.0;
            if (code >= sdl.SDL_SCANCODE_LCTRL and code <= sdl.SDL_SCANCODE_RALT) {
                const code_internal: Button = @enumFromInt(code - sdl.SDL_SCANCODE_LCTRL + @intFromEnum(input.Button.INPUT_KEY_L_CTRL));
                input.setButtonState(code_internal, state);
            } else if (code > 0 and code < @intFromEnum(input.Button.INPUT_KEY_MAX)) {
                input.setButtonState(@enumFromInt(code), state);
            }
        } else if (ev.type == sdl.SDL_TEXTINPUT) {
            input.textInput(ev.text.text[0]);
        }

        // Gamepads connect/disconnect
        else if (ev.type == sdl.SDL_CONTROLLERDEVICEADDED) {
            gamepad = sdl.SDL_GameControllerOpen(ev.cdevice.which);
        } else if (ev.type == sdl.SDL_CONTROLLERDEVICEREMOVED) {
            if (gamepad != null and ev.cdevice.which == sdl.SDL_JoystickInstanceID(sdl.SDL_GameControllerGetJoystick(gamepad))) {
                sdl.SDL_GameControllerClose(gamepad);
                gamepad = findGamepad();
            }
        }

        // Input Gamepad Buttons
        else if (ev.type == sdl.SDL_CONTROLLERBUTTONDOWN or
            ev.type == sdl.SDL_CONTROLLERBUTTONUP)
        {
            if (ev.cbutton.button < sdl.SDL_CONTROLLER_BUTTON_MAX) {
                const button = gamepad_map[ev.cbutton.button];
                if (button != .INPUT_INVALID) {
                    const state: f32 = if (ev.type == sdl.SDL_CONTROLLERBUTTONDOWN) 1.0 else 0.0;
                    input.setButtonState(button, state);
                }
            }
        }

        // Input Gamepad Axis
        else if (ev.type == sdl.SDL_CONTROLLERAXISMOTION) {
            const state: f32 = @as(f32, @floatFromInt(ev.caxis.value)) / 32767.0;

            if (ev.caxis.axis < sdl.SDL_CONTROLLER_AXIS_MAX) {
                const code = axis_map[ev.caxis.axis];
                if (code == input.Button.INPUT_GAMEPAD_L_TRIGGER or
                    code == input.Button.INPUT_GAMEPAD_R_TRIGGER)
                {
                    input.setButtonState(code, state);
                } else if (state > 0) {
                    input.setButtonState(code, 0.0);
                    input.setButtonState(@enumFromInt(@intFromEnum(code) + 1), state);
                } else {
                    input.setButtonState(code, -state);
                    input.setButtonState(@enumFromInt(@intFromEnum(code) + 1), 0.0);
                }
            }
        }

        // Mouse buttons
        else if (ev.type == sdl.SDL_MOUSEBUTTONDOWN or
            ev.type == sdl.SDL_MOUSEBUTTONUP)
        {
            const button: Button = switch (ev.button.button) {
                sdl.SDL_BUTTON_LEFT => .INPUT_MOUSE_LEFT,
                sdl.SDL_BUTTON_MIDDLE => .INPUT_MOUSE_MIDDLE,
                sdl.SDL_BUTTON_RIGHT => .INPUT_MOUSE_RIGHT,
                else => .INPUT_INVALID,
            };
            if (button != .INPUT_INVALID) {
                const state: f32 = if (ev.type == sdl.SDL_MOUSEBUTTONDOWN) 1.0 else 0.0;
                input.setButtonState(button, state);
            }
        }

        // Mouse wheel
        else if (ev.type == sdl.SDL_MOUSEWHEEL) {
            const button: Button = if (ev.wheel.y > 0) .INPUT_MOUSE_WHEEL_UP else .INPUT_MOUSE_WHEEL_DOWN;
            input.setButtonState(button, 1.0);
            input.setButtonState(button, 0.0);
        }

        // Mouse move
        else if (ev.type == sdl.SDL_MOUSEMOTION) {
            input.setMousePos(ev.motion.x, ev.motion.y);
        }

        // Window Events
        else if (ev.type == sdl.SDL_QUIT) {
            wants_to_exit = true;
        } else if (ev.type == sdl.SDL_WINDOWEVENT and
            (ev.window.event == sdl.SDL_WINDOWEVENT_SIZE_CHANGED or ev.window.event == sdl.SDL_WINDOWEVENT_RESIZED))
        {
            render.resize(screenSize());
        }
    }
}

pub fn run(d: Desc) void {
    desc = d;

    init();
    if (sdl.SDL_Init(sdl.SDL_INIT_VIDEO | sdl.SDL_INIT_EVENTS | sdl.SDL_INIT_AUDIO | sdl.SDL_INIT_JOYSTICK | sdl.SDL_INIT_GAMECONTROLLER) < 0)
        sdlPanic();
    defer sdl.SDL_Quit();

    var ba = alloc.BumpAllocator{};

    // Load gamecontrollerdb.txt if present.
    // FIXME: Should this load from userdata instead?

    const bin_dir_path = bin_dir.realpathAlloc(ba.allocator(), ".") catch @panic("failed to get bin dir path");
    const gcdb_path = std.fs.path.joinZ(ba.allocator(), &[_][]const u8{ bin_dir_path, "gamecontrollerdb.txt" }) catch @panic("failed concat bin dir path");
    defer ba.allocator().free(gcdb_path);

    const gcdb_res = sdl.SDL_GameControllerAddMappingsFromFile(gcdb_path);
    if (gcdb_res < 0) {
        std.log.err("Failed to load gamecontrollerdb.txt", .{});
    } else {
        std.log.info("load gamecontrollerdb.txt", .{});
    }

    gamepad = findGamepad();
    if (gamepad != null) {
        sdl.SDL_GameControllerClose(gamepad);
    }

    var obtained_spec: sdl.SDL_AudioSpec = undefined;
    audio_device = sdl.SDL_OpenAudioDevice(null, 0, &.{
        .freq = @intCast(platform_output_samplerate),
        .format = sdl.AUDIO_F32SYS,
        .channels = 2,
        .samples = 1024,
        .callback = platformAudioCallback,
        .padding = 0,
        .silence = 0,
        .size = 0,
        .userdata = null,
    }, &obtained_spec, 0);
    defer sdl.SDL_CloseAudioDevice(audio_device);

    // Obtained samplerate might be different from requested
    platform_output_samplerate = @intCast(obtained_spec.freq);

    window = sdl.SDL_CreateWindow(
        options.options.WINDOW_TITLE,
        sdl.SDL_WINDOWPOS_CENTERED,
        sdl.SDL_WINDOWPOS_CENTERED,
        options.options.WINDOW_SIZE.x,
        options.options.WINDOW_SIZE.y,
        sdl.SDL_WINDOW_SHOWN | sdl.SDL_WINDOW_OPENGL | sdl.SDL_WINDOW_RESIZABLE | sdl.SDL_WINDOW_ALLOW_HIGHDPI,
    ) orelse sdlPanic();
    defer _ = sdl.SDL_DestroyWindow(window);

    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_PROFILE_MASK, sdl.SDL_GL_CONTEXT_PROFILE_CORE);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MAJOR_VERSION, 3);
    _ = sdl.SDL_GL_SetAttribute(sdl.SDL_GL_CONTEXT_MINOR_VERSION, 1);

    // init OpenGL
    gl.load(window, getProcAddressWrapper) catch @panic("failed to load OpenGL functions");
    const platform_gl = sdl.SDL_GL_CreateContext(window);
    defer sdl.SDL_GL_DeleteContext(platform_gl);

    _ = sdl.SDL_GL_SetSwapInterval(1);

    // Create Vertex Array Object
    var vao: gl.GLuint = undefined;
    gl.genVertexArrays(1, &vao);
    gl.bindVertexArray(vao);
    defer gl.deleteVertexArrays(1, &vao);

    desc.init_cb.?();

    while (!wants_to_exit) {
        pumpEvents();
        desc.update_cb.?();
        sdl.SDL_GL_SwapWindow(window);
    }

    desc.cleanup_cb.?();
}

fn getProcAddressWrapper(_: *sdl.SDL_Window, symbolName: [:0]const u8) ?*align(4) const anyopaque {
    return @alignCast(sdl.SDL_GL_GetProcAddress(symbolName));
}

fn sdlPanic() noreturn {
    const str = @as(?[*:0]const u8, sdl.SDL_GetError()) orelse "unknown error";
    @panic(std.mem.sliceTo(str, 0));
}
