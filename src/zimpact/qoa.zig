const std = @import("std");

const Qoa = @This();

const header_size = 8;
const frame_header_size = 8;
const min_filesize = 16;
const max_channels = 8;
const max_sample_rate = 16777215;
const max_slice_len = 20;
const lms_len = 4;
const quant_table = [17]i32{ 7, 7, 7, 5, 5, 3, 3, 1, 0, 0, 2, 2, 4, 4, 6, 6, 6 };
const scalefactor_table = [16]i32{ 1, 7, 21, 45, 84, 138, 211, 304, 421, 562, 731, 928, 1157, 1419, 1715, 2048 };
const reciprocal_table = [16]i32{ 65536, 9363, 3121, 1457, 781, 475, 311, 216, 156, 117, 90, 71, 57, 47, 39, 32 };
const dequant_table = [16][8]i32{
    .{ 1, -1, 3, -3, 5, -5, 7, -7 },
    .{ 5, -5, 18, -18, 32, -32, 49, -49 },
    .{ 16, -16, 53, -53, 95, -95, 147, -147 },
    .{ 34, -34, 113, -113, 203, -203, 315, -315 },
    .{ 63, -63, 210, -210, 378, -378, 588, -588 },
    .{ 104, -104, 345, -345, 621, -621, 966, -966 },
    .{ 158, -158, 528, -528, 950, -950, 1477, -1477 },
    .{ 228, -228, 760, -760, 1368, -1368, 2128, -2128 },
    .{ 316, -316, 1053, -1053, 1895, -1895, 2947, -2947 },
    .{ 422, -422, 1405, -1405, 2529, -2529, 3934, -3934 },
    .{ 548, -548, 1828, -1828, 3290, -3290, 5117, -5117 },
    .{ 696, -696, 2320, -2320, 4176, -4176, 6496, -6496 },
    .{ 868, -868, 2893, -2893, 5207, -5207, 8099, -8099 },
    .{ 1064, -1064, 3548, -3548, 6386, -6386, 9933, -9933 },
    .{ 1286, -1286, 4288, -4288, 7718, -7718, 12005, -12005 },
    .{ 1536, -1536, 5120, -5120, 9216, -9216, 14336, -14336 },
};

channels: u8,
sample_rate: u24,
samples: []i16,

pub const DecodeError = error{
    OutOfMemory,
    EndOfStream,
    InvalidData,
};

pub fn decode(allocator: std.mem.Allocator, bytes: []const u8) DecodeError!Qoa {
    if (bytes.len < min_filesize) {
        return error.InvalidData;
    }

    var fbs = std.io.fixedBufferStream(bytes);
    return Qoa.decodeStream(allocator, fbs.reader());
}

pub fn decodeStream(allocator: std.mem.Allocator, reader: anytype) (DecodeError || @TypeOf(reader).Error)!Qoa {
    const header = try Header.decode(reader);
    var frame_header = try FrameHeader.decode(reader);

    const total_samples = header.samples * frame_header.channels;
    var samples = try allocator.alloc(i16, total_samples);
    errdefer allocator.free(samples);

    var lms = std.mem.zeroes([max_channels]LMS);
    var decoded_samples: usize = 0;
    while (true) {
        decoded_samples += try decodeFrame(
            reader,
            frame_header,
            &lms,
            samples[decoded_samples * frame_header.channels ..],
        );

        if (decoded_samples >= header.samples) break;
        frame_header = try FrameHeader.decode(reader);
    }

    return .{
        .channels = frame_header.channels,
        .sample_rate = frame_header.sample_rate,
        .samples = samples,
    };
}

pub const FrameHeader = struct {
    channels: u8,
    sample_rate: u24,
    samples: u16,
    size: u16,

    pub fn decode(reader: anytype) !FrameHeader {
        const channels = try reader.readInt(u8, .big);
        const sample_rate = try reader.readInt(u24, .big);
        const samples = try reader.readInt(u16, .big);
        const size = try reader.readInt(u16, .big);

        const data_size = size - frame_header_size - lms_len * 4 * channels;
        const num_slices = data_size / 8;
        const max_total_samples = num_slices * max_slice_len;

        if (channels == 0 or
            channels > max_channels or
            samples * channels > max_total_samples)
        {
            return error.InvalidData;
        }

        return .{
            .channels = channels,
            .sample_rate = sample_rate,
            .samples = samples,
            .size = size,
        };
    }
};

pub fn decodeFrame(reader: anytype, header: FrameHeader, lms: *[max_channels]LMS, sample_data: []i16) !u16 {
    for (0..header.channels) |ch| {
        try lms[ch].decode(reader);
    }

    var sample_index: u16 = 0;
    while (sample_index < header.samples) : (sample_index += max_slice_len) {
        for (0..header.channels) |c| {
            var slice = try reader.readInt(u64, .big);
            const scalefactor = (slice >> 60) & 0xf;
            const slice_start = sample_index * header.channels + c;
            const slice_end = @min(sample_index + max_slice_len, header.samples) * header.channels + c;

            var si = slice_start;
            while (si < slice_end) : (si += header.channels) {
                const predicted = lms[c].predict();
                const quantized = (slice >> 57) & 0x7;
                const dequantized = dequant_table[@intCast(scalefactor)][@intCast(quantized)];
                const reconstructed: i16 = @intCast(std.math.clamp(predicted + dequantized, std.math.minInt(i16), std.math.maxInt(i16)));

                sample_data[si] = reconstructed;
                slice <<= 3;

                lms[c].update(reconstructed, dequantized);
            }
        }
    }

    return sample_index;
}

pub const Header = struct {
    pub const magic = 0x716f6166; // qoaf

    samples: u32,

    pub fn decode(reader: anytype) !Header {
        if (try reader.readInt(u32, .big) != magic) {
            return error.InvalidData;
        }

        return .{
            .samples = try reader.readInt(u32, .big),
        };
    }

    pub fn encode(header: Header, writer: anytype) !void {
        try writer.writeIntBig(u32, magic);
        try writer.writeIntBig(u32, header.samples);
    }
};

pub const LMS = struct {
    history: [lms_len]i32 = .{ 0, 0, 0, 0 },
    weights: [lms_len]i32 = .{ 0, 0, 0, 0 },

    fn decode(lms: *LMS, reader: anytype) !void {
        for (&lms.history) |*h| {
            h.* = try reader.readInt(i16, .big);
        }
        for (&lms.weights) |*w| {
            w.* = try reader.readInt(i16, .big);
        }
    }

    fn predict(lms: LMS) i32 {
        var prediction: i32 = 0;
        for (lms.weights, lms.history) |w, h| {
            prediction += w * h;
        }
        return prediction >> 13;
    }

    fn update(lms: *LMS, sample: i16, residual: i32) void {
        const delta = residual >> 4;
        for (0..lms_len) |i| {
            lms.weights[i] += if (lms.history[i] < 0) -delta else delta;
        }

        for (0..lms_len - 1) |i| {
            lms.history[i] = lms.history[i + 1];
        }
        lms.history[lms_len - 1] = sample;
    }
};

test "decode" {
    const test_file = @embedFile("../assets/childhood.qoa");
    const result = try decode(std.testing.allocator, test_file);
    defer std.testing.allocator.free(result.samples);
    try std.fs.cwd().writeFile("zig-out/raw_audio.pcm", std.mem.sliceAsBytes(result.samples));
}
