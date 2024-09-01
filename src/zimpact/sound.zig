const std = @import("std");
const assert = std.debug.assert;
const options = @import("options.zig").options;
const platform = @import("platform.zig");
const qoa = @import("qoa.zig");
const alloc = @import("allocator.zig");
const TempAllocator = alloc.TempAllocator;
const BumpAllocator = alloc.BumpAllocator;

const QOA_SLICE_LEN = 20;
const QOA_SLICES_PER_FRAME = 256;
const QOA_FRAME_LEN = (QOA_SLICES_PER_FRAME * QOA_SLICE_LEN);
const QOA_LMS_LEN = 4;
const max_channels = 8;

pub const SoundMark = struct {
    index: u32 = 0,
};

const SoundSourceType = enum {
    pcm,
    qoa,
};

const SoundSourceQoa = struct {
    desc: qoa.FrameHeader,
    data_len: usize,
    data: []u8,
    pcm_buffer_start: u32,
    pcm_buffer: []i16,
};

pub const SoundSource = struct {
    channels: u32,
    len: u32,
    samplerate: u32,
    source: union(SoundSourceType) {
        pcm: []i16,
        qoa: SoundSourceQoa,
    },
};

pub const Sound = struct {
    id: u16,
    index: u16,
};

const SoundNode = struct {
    source: *SoundSource,
    id: u16,
    is_playing: bool,
    is_halted: bool,
    is_looping: bool,
    pan: f32,
    volume: f32,
    pitch: f32,
    sample_pos: f32,
};

// sound system ----------------------------------------------------------------

var global_volume: f32 = 1;
var inv_out_samplerate: f32 = undefined;
var sources: [options.SOUND_MAX_SOURCES]SoundSource = undefined;
var sources_len: usize = 0;
var source_paths: [options.SOUND_MAX_SOURCES][]const u8 = undefined;
var sound_nodes: [options.SOUND_MAX_NODES]SoundNode = undefined;
var nodes_len: usize = 0;
var sound_unique_id: u16 = 0;

/// Called by the platform
pub fn init(samplerate: u32) void {
    inv_out_samplerate = 1.0 / @as(f32, @floatFromInt(samplerate));
}

/// Called by the platform
pub fn cleanup() void {
    // Stop all nodes
    for (&sound_nodes) |*sound_node| {
        sound_node.is_playing = false;
    }
}

/// Load a sound sorce from a QOA file. Calling this function multiple times with
/// the same path will return the same, cached sound source,
pub fn source(path: []const u8) *SoundSource {
    for (0..sources_len) |i| {
        if (std.mem.eql(u8, path, source_paths[i])) {
            return &sources[i];
        }
    }

    var ba = BumpAllocator{};
    var ta = TempAllocator{};
    const data = platform.loadAsset(path, ta.allocator());

    var fbs = std.io.fixedBufferStream(data);
    var reader = fbs.reader();
    const header = qoa.Header.decode(reader) catch @panic("failed to decode audio");
    const frame_header = qoa.FrameHeader.decode(reader) catch @panic("failed to decode audio");

    assert(frame_header.channels <= 2);
    var src = &sources[sources_len];
    src.channels = frame_header.channels;
    src.len = header.samples;
    src.samplerate = frame_header.sample_rate;

    const total_samples = header.samples * frame_header.channels;

    // Is this source short enough to completely uncompress it on load?
    if (total_samples <= options.SOUND_MAX_UNCOMPRESSED_SAMPLES) {
        defer ta.allocator().free(data);
        const audio = qoa.decode(ba.allocator(), data) catch @panic("failed to decode audio");
        src.source = .{ .pcm = audio.samples };
        src.len = @intCast(audio.samples.len / frame_header.channels);
    }

    // Longer sources will be decompressed on demand; we just decode the first
    // frame here.
    else {
        const qoa_data_size = data.len - fbs.pos;

        // Transfer data to bump mem
        const bump_data = alloc.bumpFromTemp(u8, data, fbs.pos, qoa_data_size);
        fbs = std.io.fixedBufferStream(bump_data);
        reader = fbs.reader();

        src.source = .{
            .qoa = .{
                .desc = frame_header,
                .data = bump_data,
                .data_len = qoa_data_size,
                .pcm_buffer_start = 0,
                .pcm_buffer = alloc.bumpAlloc(i16, @as(usize, frame_header.channels) * QOA_FRAME_LEN) catch @panic("failed to alloc pcm buffer"),
            },
        };

        var lms = std.mem.zeroes([max_channels]qoa.LMS);
        _ = qoa.decodeFrame(reader, frame_header, &lms, src.source.qoa.pcm_buffer) catch @panic("failed to decode audio frame");
        // error_if(frame_size == 0, "QOA decode error for file %s", path);
    }

    source_paths[sources_len] = ba.allocator().dupe(u8, path) catch @panic("failed to decode audio");
    sources_len += 1;

    return src;
}

/// Play a sound source. The node used to play it will be automatically disposed
/// once it has played through.
pub fn play(src: *SoundSource) void {
    const snd = sound(src);
    if (snd) |s| {
        unpause(s);
        dispose(s);
    }
}

/// Play a sound source with the given volume and pitch. The node used to play it
/// will be automatically disposed once it has played through.
pub fn playEx(src: *SoundSource, v: f32, p: f32, pi: f32) void {
    const s = sound(src);
    setVolume(s, v);
    setPan(s, p);
    setPitch(s, pi);
    unpause(s);
    dispose(s);
}

/// Return the current volume of this node
pub fn volume(snd: Sound) f32 {
    if (getNode(snd)) |node| {
        return node.volume;
    }
    return 0;
}

/// Set the current volume of this node
pub fn setVolume(snd: Sound, value: f32) void {
    if (getNode(snd)) |node| {
        node.volume = std.math.clamp(value, 0, 16);
    }
}

// Return the current pan of the node (-1 = left, 0 = center, 1 = right)
pub fn pan(snd: Sound) f32 {
    if (getNode(snd)) |node| {
        return node.pan;
    }
    return 0;
}

/// Set the current pan of a the node
pub fn setPan(snd: Sound, value: f32) void {
    if (getNode(snd)) |node| {
        node.pan = std.math.clamp(value, -1, 1);
    }
}

/// Return the current pitch (playback speed) of this node. Default 1.
pub fn pitch(snd: Sound) f32 {
    if (getNode(snd)) |node| {
        return node.pitch;
    }
    return 0;
}

/// Set the current pitch (playback speed) of this node
pub fn setPitch(snd: Sound, value: f32) void {
    if (getNode(snd)) |node| {
        node.pitch = std.math.clamp(value, -1, 1);
    }
}

/// Put all playing nodes in a halt state; usefull for e.g. a pause screen
pub fn halt() void {
    for (&sound_nodes) |*node| {
        if (node.is_playing) {
            node.is_playing = false;
            node.is_halted = true;
        }
    }
}

/// Resume playing all halted sounds
pub fn @"resume"() void {
    for (&sound_nodes) |*node| {
        if (node.is_halted) {
            node.is_playing = true;
            node.is_halted = false;
        }
    }
}

/// Return the global volume for all sounds
pub fn globalVolume() f32 {
    return global_volume;
}

/// Set the global volume for all nodes
pub fn setGlobalVolume(vol: f32) void {
    global_volume = std.math.clamp(vol, 0, 1);
}

/// Called by the engine to manage sound memory
pub fn mark() SoundMark {
    return .{ .index = @intCast(sources_len) };
}

/// Called by the engine to manage sound memory
pub fn reset(mrk: SoundMark) void {
    // Reset all nodes whose sources are invalidated
    for (&sound_nodes) |*node| {
        const src: usize = @intFromPtr(node.source);
        if ((src != 0) and ((src - @intFromPtr(&sources[0])) >= (mrk.index * @sizeOf(SoundSource)))) {
            node.id = 0;
            node.is_playing = false;
            node.is_halted = false;
            node.is_looping = false;
        }
    }
    sources_len = mrk.index;
}

/// Return the duration of a sound source
pub fn sourceDuration(src: *SoundSource) f32 {
    return src.len / src.samplerate;
}

/// Obtain a free node for the given source. This will "reserve" the source. It
/// can not be re-used until it is disposed via sound_dispose(). The node will be
/// in a paused state and must be explicitly unpaused. Returns an invalid node
/// with id = 0 when no free node is available.
pub fn sound(src: *SoundSource) ?Sound {
    var snd = Sound{ .id = 0, .index = 0 };
    var node: ?*SoundNode = null;

    // Get any node that is not currently playing
    for (&sound_nodes, 0..) |*sound_node, i| {
        if (!sound_node.is_playing and !sound_node.is_halted and sound_node.id == 0) {
            node = sound_node;
            snd.index = @intCast(i);
            break;
        }
    }

    // Fallback to any node that is not reserved; this will cut off
    // unreserved playing nodes
    if (node == null) {
        for (&sound_nodes, 0..) |*sound_node, i| {
            if (sound_node.id == 0) {
                node = sound_node;
                snd.index = @intCast(i);
                break;
            }
        }
    }

    if (node) |n| {
        sound_unique_id += 1;
        if (sound_unique_id == 0) {
            sound_unique_id = 1;
        }

        n.id = sound_unique_id;
        n.is_playing = false;
        n.is_halted = false;
        n.is_looping = false;
        n.source = src;
        n.volume = 1;
        n.pan = 0;
        n.sample_pos = 0;
        n.pitch = 1;

        snd.id = sound_unique_id;
        return snd;
    }

    // Still nothing?
    return null;
}

inline fn getNode(snd: Sound) ?*SoundNode {
    if (snd.index < options.SOUND_MAX_NODES and sound_nodes[snd.index].id == snd.id)
        return &sound_nodes[snd.index];
    return null;
}

/// Pauses a node
pub fn pause(snd: Sound) void {
    if (getNode(snd)) |node| {
        node.is_playing = false;
        node.is_halted = false;
    }
}

/// Pauses a node and rewind it to the start
pub fn stop(snd: Sound) void {
    if (getNode(snd)) |node| {
        node.sample_pos = 0;
        node.is_playing = false;
        node.is_halted = false;
    }
}

/// Unpauses a paused node
pub fn unpause(snd: Sound) void {
    if (getNode(snd)) |node| {
        node.is_playing = true;
        node.is_halted = false;
    }
}

/// Return the duration in seconds of the underlying sound source. This does not
/// take the node's current pitch into account
pub fn duration(snd: Sound) f32 {
    if (getNode(snd)) |node| {
        return sourceDuration(node.source);
    }
    return 0;
}

// Return the current position of this node in seconds. This does not take the
// node's current pitch into account
pub fn time(snd: Sound) f32 {
    if (getNode(snd)) |node| {
        return node.sample_pos / node.source.samplerate;
    }
    return 0;
}

/// Set the current position of this node in seconds. This does not take the
/// node's current pitch into account
pub fn setTime(snd: Sound, value: f32) void {
    if (getNode(snd)) |node| {
        node.sample_pos = std.math.clamp(value / @as(f32, @floatFromInt(node.source.samplerate)), 0, @as(f32, @floatFromInt(node.source.len)));
    }
}

/// Dispose this node. The node is invalid afterwards, but will still play to the
/// end if it's not paused.
fn dispose(snd: Sound) void {
    if (getNode(snd)) |node| {
        node.is_looping = false;
        node.id = 0;
    }
}

/// Return whether this node loops
pub fn loop(snd: Sound) bool {
    if (getNode(snd)) |node| {
        return node.is_playing;
    }
    return false;
}

/// Set whether to loop this node
pub fn setLoop(snd: Sound, value: bool) void {
    if (getNode(snd)) |node| {
        node.is_looping = value;
    }
}

fn qoaMaxFrameSize(frame_header: qoa.FrameHeader) usize {
    return (8 + QOA_LMS_LEN * 4 * @as(usize, frame_header.channels) + 8 * QOA_SLICES_PER_FRAME * @as(usize, frame_header.channels));
}

/// Periodically called by the platform to mix playing nodes into output buffer
pub fn mixStereo(dest_samples: []f32) void {
    @memset(dest_samples, 0);

    // Samples are stored as int16_t; we have to multiply each sample with
    // the global sound_volume anyway, so do the normalization from int16_t to
    // float (-1..1) at the same time.
    const volume_normalize = global_volume / 32768.0;

    for (&sound_nodes) |*node| {
        if (node.is_playing and node.volume > 0) {
            const src = node.source;
            const vol_left = volume_normalize * node.volume * std.math.clamp(1.0 - node.pan, 0, 1);
            const vol_right = volume_normalize * node.volume * std.math.clamp(1.0 + node.pan, 0, 1);

            // Calculate the pitch by considering the output samplerate. Quality
            // wise, this is not the best way to "resample" the source. FIXME
            const node_pitch: f32 = node.pitch * @as(f32, @floatFromInt(src.samplerate)) * inv_out_samplerate;

            var src_qoa: *SoundSourceQoa = undefined;
            var src_samples: []i16 = undefined;

            switch (src.source) {
                .pcm => {
                    src_samples = src.source.pcm;
                },
                .qoa => {
                    src_qoa = &src.source.qoa;
                    src_samples = src.source.qoa.pcm_buffer;
                },
            }

            const c: u5 = if (src.channels == 2) 1 else 0;

            var di: usize = 0;
            while (di < dest_samples.len) : (di += 2) {
                var source_index: usize = @intFromFloat(node.sample_pos);

                // If this is a compressed source we may have to decode a
                // different frame for this source index. This will overwrite
                // the source' internal pcm frame buffer.
                // FIXME: this creates unnecessary decodes when many nodes play
                // the same source?
                if (src.source == .qoa) {
                    if ((source_index < src_qoa.pcm_buffer_start) or
                        (source_index >= (src_qoa.pcm_buffer_start + QOA_FRAME_LEN)))
                    {
                        const frame_index = source_index / QOA_FRAME_LEN;
                        const frame_data_start = qoaMaxFrameSize(src_qoa.desc) * frame_index;
                        const frame_data = src_qoa.data[frame_data_start..];
                        var fbs = std.io.fixedBufferStream(frame_data);
                        var lms = std.mem.zeroes([max_channels]qoa.LMS);
                        _ = qoa.decodeFrame(fbs.reader(), src_qoa.desc, &lms, src_samples) catch {
                            // it will happen at the end of the sound
                        };
                        src_qoa.pcm_buffer_start = @intCast(frame_index * QOA_FRAME_LEN);
                    }
                    source_index -= src_qoa.pcm_buffer_start;
                }

                dest_samples[di + 0] += @as(f32, @floatFromInt(src_samples[(source_index << c) + 0])) * vol_left;
                dest_samples[di + 1] += @as(f32, @floatFromInt(src_samples[(source_index << c) + c])) * vol_right;

                node.sample_pos += node_pitch;
                if (node.sample_pos >= @as(f32, @floatFromInt(src.len)) or node.sample_pos < 0) {
                    if (node.is_looping) {
                        node.sample_pos =
                            @mod(node.sample_pos, @as(f32, @floatFromInt(src.len))) +
                            if (node.sample_pos < 0) @as(f32, @floatFromInt(src.len)) else 0.0;
                    } else {
                        node.is_playing = false;
                        break;
                    }
                }
            }
        }
    }
}
