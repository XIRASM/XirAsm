const std = @import("std");
const generated_core = @import("generated_core.zig");
const types = @import("types.zig");

pub const instructions = generated_core.instructions;

pub fn instructionByMnemonic(mnemonic: []const u8) types.EncodeError!?*const types.InstructionSpec {
    return instructionByMnemonicForXLen(mnemonic, 64);
}

pub fn instructionByMnemonicForXLen(mnemonic: []const u8, xlen: u8) types.EncodeError!?*const types.InstructionSpec {
    var normalized_buf: [96]u8 = undefined;
    const normalized = try normalizeMnemonic(&normalized_buf, mnemonic);
    for (&instructions) |*spec| {
        if (std.mem.eql(u8, normalized, spec.name) and xlen >= spec.min_xlen and xlen <= spec.max_xlen) return spec;
    }
    return null;
}

pub fn instructionByMnemonicAnyXLen(mnemonic: []const u8) types.EncodeError!?*const types.InstructionSpec {
    var normalized_buf: [96]u8 = undefined;
    const normalized = try normalizeMnemonic(&normalized_buf, mnemonic);
    for (&instructions) |*spec| {
        if (std.mem.eql(u8, normalized, spec.name)) return spec;
    }
    return null;
}

pub fn normalizeMnemonic(buffer: []u8, mnemonic: []const u8) types.EncodeError![]const u8 {
    const trimmed = std.mem.trim(u8, mnemonic, " \t\r\n");
    if (trimmed.len > buffer.len) return error.MnemonicTooLong;
    for (trimmed, 0..) |ch, index| {
        buffer[index] = switch (ch) {
            '.', '-' => '_',
            else => std.ascii.toLower(ch),
        };
    }
    return buffer[0..trimmed.len];
}
