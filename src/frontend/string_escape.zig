//! Escape decoding for text that XIRASM reads out of quotes.
//!
//! Two features read quoted text and have to agree on what an escape means:
//! source string and bytes literals, and the `quoted` capture of
//! `match.tokens`. They used to differ -- literals decoded nothing while the
//! capture dropped the backslash of every escape it did not know -- which made
//! the same characters mean different bytes depending on where they were
//! written. Both now call `decodeEscape`.
//!
//! The set is deliberately small and portable: `\n`, `\r`, `\t`, `\0`, `\\`,
//! whichever quote opened the literal, and `\uXXXX` for a BMP code point. Every
//! other `\X` is *not* an escape: it stays two characters, the backslash and `X`.
//! Keeping the backslash is what makes the rule safe to adopt -- text that
//! treats the backslash as an ordinary character keeps its bytes (`"slash \ ok"`
//! still ends `\ ok`), and escape forms this build does not decode pass through
//! as written instead of losing the backslash.
//!
//! `\uXXXX` is here because generated platform text uses it: the Windows API
//! tables spell control characters that way, and without it those constants
//! carried the six characters `\u0000` instead of the byte they name.

const std = @import("std");

/// One decoded escape: the bytes it stands for, and how much of the source it
/// covered, including the backslash.
pub const Decoded = struct {
    bytes: [4]u8,
    len: u3,
    consumed: usize,
};

/// Decode the escape at the start of `text`, which must begin with a backslash.
/// Returns null when `\` and what follows are not an escape, so the caller can
/// keep both characters as written.
pub fn decodeEscape(quote: u8, text: []const u8) ?Decoded {
    if (text.len < 2 or text[0] != '\\') return null;

    const letter = text[1];
    if (letter == quote) return .{ .bytes = .{ quote, 0, 0, 0 }, .len = 1, .consumed = 2 };
    switch (letter) {
        'n' => return .{ .bytes = .{ '\n', 0, 0, 0 }, .len = 1, .consumed = 2 },
        'r' => return .{ .bytes = .{ '\r', 0, 0, 0 }, .len = 1, .consumed = 2 },
        't' => return .{ .bytes = .{ '\t', 0, 0, 0 }, .len = 1, .consumed = 2 },
        '0' => return .{ .bytes = .{ 0, 0, 0, 0 }, .len = 1, .consumed = 2 },
        '\\' => return .{ .bytes = .{ '\\', 0, 0, 0 }, .len = 1, .consumed = 2 },
        'u' => {},
        else => return null,
    }

    if (text.len < 6) return null;
    const code_point = std.fmt.parseInt(u21, text[2..6], 16) catch return null;
    // A lone surrogate is not a code point and would not be valid UTF-8, so it
    // is left as the characters the source wrote.
    if (code_point >= 0xD800 and code_point <= 0xDFFF) return null;

    var bytes: [4]u8 = .{ 0, 0, 0, 0 };
    const len = std.unicode.utf8Encode(code_point, &bytes) catch return null;
    return .{ .bytes = bytes, .len = @intCast(len), .consumed = 6 };
}

test "known escapes decode and unknown escapes keep the backslash" {
    const expectByte = struct {
        fn check(quote: u8, letter: u8, expected: ?u8) !void {
            const text = [_]u8{ '\\', letter };
            const decoded = decodeEscape(quote, &text);
            if (expected) |byte| {
                try std.testing.expectEqual(@as(u3, 1), decoded.?.len);
                try std.testing.expectEqual(byte, decoded.?.bytes[0]);
                try std.testing.expectEqual(@as(usize, 2), decoded.?.consumed);
            } else {
                try std.testing.expectEqual(@as(?Decoded, null), decoded);
            }
        }
    }.check;

    try expectByte('"', 'n', '\n');
    try expectByte('"', 'r', '\r');
    try expectByte('"', 't', '\t');
    try expectByte('"', '0', 0);
    try expectByte('"', '\\', '\\');
    try expectByte('"', '"', '"');
    try expectByte('\'', '\'', '\'');
    // Only the literal's own quote is an escape; the other one stays literal.
    try expectByte('"', '\'', null);
    try expectByte('\'', '"', null);
    // Unknown letters are not escapes.
    try expectByte('"', ' ', null);
    try expectByte('"', 'q', null);
}

test "unicode escapes decode to utf-8 and malformed ones stay literal" {
    const expectText = struct {
        fn check(source: []const u8, expected: []const u8) !void {
            const decoded = decodeEscape('"', source) orelse return error.NotAnEscape;
            try std.testing.expectEqualSlices(u8, expected, decoded.bytes[0..decoded.len]);
            try std.testing.expectEqual(source.len, decoded.consumed);
        }
    }.check;

    try expectText("\\u0041", "A");
    try expectText("\\u0000", "\x00");
    try expectText("\\u001e", "\x1e");
    try expectText("\\u00e9", "\xc3\xa9");
    try expectText("\\u20ac", "\xe2\x82\xac");

    // Malformed or unrepresentable escapes are not escapes at all.
    try std.testing.expectEqual(@as(?Decoded, null), decodeEscape('"', "\\u41"));
    try std.testing.expectEqual(@as(?Decoded, null), decodeEscape('"', "\\uzzzz"));
    try std.testing.expectEqual(@as(?Decoded, null), decodeEscape('"', "\\ud800"));
    try std.testing.expectEqual(@as(?Decoded, null), decodeEscape('"', "\\u"));
    try std.testing.expectEqual(@as(?Decoded, null), decodeEscape('"', "\\"));
}
