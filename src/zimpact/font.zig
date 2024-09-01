const std = @import("std");
const types = @import("types.zig");
const Vec2 = types.Vec2;
const vec2 = types.vec2;
const Rgba = types.Rgba;
const Image = @import("image.zig").Image;
const alloc = @import("allocator.zig");
const platform = @import("platform.zig");

const FontGlyph = struct {
    pos: Vec2,
    size: Vec2,
    offset: Vec2,
    advance: i32,
};

/// Fonts are a wrapper around `image()` that makes it easier to draw text on the
/// screen. The font image contains all glyphs and is accompanied by a json
/// file that specifies the position, size and advance width of each glyph.
/// Use the font_tool.html to create the image and json.
pub const Font = struct {
    /// The line height when drawing multi-line text. By default, this is the
    /// image height * 1.25. Increase this to have more line spacing.
    line_height: i32,

    /// Extra spacing between each letter on a single line. Default 0
    letter_spacing: i32,

    /// A tint color for this font. Default rgba_white()
    color: Rgba,

    /// Internal state
    first_char: i32,
    last_char: i32,
    image: *Image,
    glyphs: []FontGlyph,

    /// Draw some text. \n starts a new line. pos is the "anchor" position of the
    /// text, where y is always the top of the character (not the baseline) and x
    /// is either the left, right or center position according to align.
    pub fn draw(self: Font, p: Vec2, text: []const u8, alignment: FontAlign) void {
        var c: usize = 0;
        var pos = p;

        while (c < text.len and text[c] != 0) {
            while (text[c] == '\n') {
                pos.y += @floatFromInt(self.line_height);
                c += 1;
            }
            c += fontDrawLine(self, pos, text[c..], alignment);
        }
    }

    /// Return the line width for the given text
    fn fontLineWidth(self: Font, text: []const u8) usize {
        var width: usize = 0;
        var c: usize = 0;
        while (c < text.len and text[c] != 0 and text[c] != '\n') {
            if (text[c] >= self.first_char and text[c] <= self.last_char) {
                width += @as(usize, @intCast(self.glyphs[@intCast(text[c] - self.first_char)].advance)) + @as(usize, @intCast(self.letter_spacing));
            }
            c += 1;
        }
        return @max(0, width - @as(usize, @intCast(self.letter_spacing)));
    }

    fn fontDrawLine(self: Font, p: Vec2, text: []const u8, alignment: FontAlign) usize {
        var pos = p;
        if (alignment == .FONT_ALIGN_CENTER or alignment == .FONT_ALIGN_RIGHT) {
            const width = self.fontLineWidth(text);
            pos.x -= if (alignment == .FONT_ALIGN_CENTER) @as(f32, @floatFromInt(width)) / 2.0 else @as(f32, @floatFromInt(width));
        }

        var char_count: usize = 0;
        var c: usize = 0;
        while (c < text.len and text[c] != 0 and text[c] != '\n') {
            if (text[c] >= self.first_char and text[c] <= self.last_char) {
                const g = &self.glyphs[@intCast(text[c] - self.first_char)];
                self.image.drawEx(g.pos, g.size, pos.add(g.offset), g.size, self.color);
                pos.x += @as(f32, @floatFromInt(g.advance)) + @as(f32, @floatFromInt(self.letter_spacing));
            }
            c += 1;
            char_count += 1;
        }

        return char_count;
    }
};

const FontAlign = enum {
    FONT_ALIGN_LEFT,
    FONT_ALIGN_CENTER,
    FONT_ALIGN_RIGHT,
};

/// Create a font with the given path to the image and path to the width_map.json
pub fn font(path: []const u8, definition_path: []const u8) *Font {
    var ba = alloc.BumpAllocator{};
    var fnt = ba.allocator().create(Font) catch @panic("failed to alloc font");
    fnt.image = Image.init(path) catch @panic("failed to alloc font image");
    fnt.letter_spacing = 0;
    fnt.color = types.white();

    const def = platform.loadAssetJson(definition_path, ba.allocator());
    defer def.deinit();
    const obj = def.value.object;

    const metrics = obj.get("metrics").?.array;

    fnt.first_char = @truncate(obj.get("first_char").?.integer);
    fnt.last_char = @truncate(obj.get("last_char").?.integer);
    fnt.line_height = @truncate(obj.get("height").?.integer);

    const expected_chars: usize = @intCast(fnt.last_char - fnt.first_char);

    std.debug.assert(metrics.items.len / 7 == expected_chars); // fnt metrics has incorrect length (expected expected_chars have metrics.len / 7

    fnt.glyphs = ba.allocator().alloc(FontGlyph, expected_chars) catch @panic("failed to alloc font glyphs");
    var i: usize = 0;
    var a: usize = 0;
    while (i < expected_chars) {
        fnt.glyphs[i] = .{
            .pos = .{ .x = @floatFromInt(metrics.items[a + 0].integer), .y = @floatFromInt(metrics.items[a + 1].integer) },
            .size = .{ .x = @floatFromInt(metrics.items[a + 2].integer), .y = @floatFromInt(metrics.items[a + 3].integer) },
            .offset = .{ .x = @floatFromInt(metrics.items[a + 4].integer), .y = @floatFromInt(metrics.items[a + 5].integer) },
            .advance = @truncate(metrics.items[a + 6].integer),
        };
        i += 1;
        a += 7;
    }

    return fnt;
}
