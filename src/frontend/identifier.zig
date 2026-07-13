const std = @import("std");

pub fn isStart(byte: u8) bool {
    return std.ascii.isAlphabetic(byte) or byte == '_' or byte == '.';
}

pub fn isContinue(byte: u8) bool {
    return isStart(byte) or std.ascii.isDigit(byte) or byte == '$';
}

pub fn isName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!isStart(text[0])) return false;
    for (text[1..]) |byte| {
        if (!isContinue(byte)) return false;
    }
    return true;
}

pub fn looksLikeAssignment(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    const equals_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse return false;
    if (equals_index == 0) return false;
    if (equals_index + 1 < trimmed.len and trimmed[equals_index + 1] == '=') return false;
    if (trimmed[equals_index - 1] == '!' or
        trimmed[equals_index - 1] == '<' or
        trimmed[equals_index - 1] == '>' or
        trimmed[equals_index - 1] == '=')
    {
        return false;
    }

    return isName(std.mem.trim(u8, trimmed[0..equals_index], " \t"));
}

test "assignment recognition excludes comparison operators" {
    try std.testing.expect(looksLikeAssignment("value = 1"));
    try std.testing.expect(!looksLikeAssignment("value == 1"));
    try std.testing.expect(!looksLikeAssignment("value != 1"));
    try std.testing.expect(!looksLikeAssignment("value <= 1"));
    try std.testing.expect(!looksLikeAssignment("value >= 1"));
}
