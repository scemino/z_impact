const root = @import("root");

pub const RENDER_SCALE_NONE = 0;
pub const RENDER_SCALE_DISCRETE = 1;
pub const RENDER_SCALE_EXACT = 2;

pub const RENDER_RESIZE_NONE = 0;
pub const RENDER_RESIZE_WIDTH = 1;
pub const RENDER_RESIZE_HEIGHT = 2;
pub const RENDER_RESIZE_ANY = 3;

pub const SweepAxis = enum { x, y };

pub const Options = struct {
    /// The total size of the hunk
    ALLOC_SIZE: usize = 32 * 1024 * 1024,

    /// The max number of temp objects to be allocated at a time
    ALLOC_TEMP_OBJECTS_MAX: usize = 8,

    /// The maximum difference in seconds from one frame to the next. If the
    /// difference  is larger than this, the game will slow down instead of having
    /// imprecise large time steps.
    ENGINE_MAX_TICK: f32 = 0.1,

    /// The maximum number of background maps
    ENGINE_MAX_BACKGROUND_MAPS: usize = 4,

    /// The maximum amount of entities that are in your game at once. Beyond that,
    /// entity_spawn() will return NULL.
    ENTITIES_MAX: usize = 1024,

    /// The maximum size any of your entities is expected to have. This only affects
    /// the accuracy of entities_by_proximity() and entities_by_location().
    /// FIXME: this is bad; we should have to specify this.
    ENTITY_MAX_SIZE: f32 = 64.0,

    /// The minimum velocity of an entities (that has restitution > 0) for it to
    /// bounce. If this would be 0.0, entities would bounce indefinitely with ever
    /// smaller velocities.
    ENTITY_MIN_BOUNCE_VELOCITY: f32 = 10,

    /// The axis (x or y) on which we want to do the broad phase collision detection
    /// sweep & prune. For mosly horizontal games it should be x, for vertical ones y
    ENTITY_SWEEP_AXIS: SweepAxis = .x,

    /// The axis (x or y) on which we want to do the broad phase collision detection
    /// sweep & prune. For mosly horizontal games it should be x, for vertical ones y
    // TODO: ENTITY_SWEEP_AXIS: SweepAxis = .x,

    /// The maximum number of images we expect to have loaded at one time
    IMAGE_MAX_SOURCES: usize = 1024,

    /// The maximum number of discrete actions
    INPUT_ACTION_MAX: usize = 32,

    /// The deadzone in the normalized 0..1 range in which button presses are
    /// ignored. This only takes effect for "analog" input, such as sticks on a game
    /// controller.
    INPUT_DEADZONE: f32 = 0.1,

    /// The deadzone for input_capture()
    INPUT_DEADZONE_CAPTURE: f32 = 0.5,

    /// The resize mode determines how the logical size changes to adapt to the
    /// available window size.
    /// RENDER_RESIZE_NONE    - don't resize
    /// RENDER_RESIZE_WIDTH   - resize only width; keep height fixed at RENDER_HEIGHT
    /// RENDER_RESIZE_HEIGHT  - resize only height; keep width fixed at RENDER_WIDTH
    /// RENDER_RESIZE_ANY     - resize width and height to fill the window
    RENDER_RESIZE_MODE: u8 = RENDER_RESIZE_ANY,

    /// The scale mode determines if and how the logical size will be scaled up when
    /// the window is larger than the render size. Note that the desired aspect ratio
    /// will be maintained (depending on RESIZE_MODE).
    /// RENDER_RESIZE_NONE    - no scaling
    /// RENDER_SCALE_DISCRETE - scale in integer steps for perfect pixel scaling
    /// RENDER_SCALE_EXACT    - scale exactly to the window size
    RENDER_SCALE_MODE: u8 = RENDER_SCALE_DISCRETE,

    /// The maximum number of textures to be loaded at a time
    RENDER_TEXTURES_MAX: usize = 1024,

    // The maximum number of sources to be loaded at a time. This only affects
    // memory usage, but not performance.
    SOUND_MAX_SOURCES: usize = 128,

    // The maximum number of active nodes that can be mixed at time
    SOUND_MAX_NODES: usize = 32,

    // The maximum number of samples for which a sound source is decompressed
    // completely at load time. Everything above this limit will be loaded into
    // memory in compressed form and only decompressed on demand.
    SOUND_MAX_UNCOMPRESSED_SAMPLES: usize = (64 * 1024),

    ENTITY_TYPE: type = undefined,
};

pub const options: Options = if (@hasDecl(root, "zi_options")) root.zi_options else .{};
