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
