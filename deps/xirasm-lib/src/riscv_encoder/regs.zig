const std = @import("std");
const types = @import("types.zig");

pub const Register = u5;

const AbiRegister = struct {
    name: []const u8,
    index: Register,
};

const abi_registers = [_]AbiRegister{
    .{ .name = "zero", .index = 0 },
    .{ .name = "ra", .index = 1 },
    .{ .name = "sp", .index = 2 },
    .{ .name = "gp", .index = 3 },
    .{ .name = "tp", .index = 4 },
    .{ .name = "t0", .index = 5 },
    .{ .name = "t1", .index = 6 },
    .{ .name = "t2", .index = 7 },
    .{ .name = "s0", .index = 8 },
    .{ .name = "fp", .index = 8 },
    .{ .name = "s1", .index = 9 },
    .{ .name = "a0", .index = 10 },
    .{ .name = "a1", .index = 11 },
    .{ .name = "a2", .index = 12 },
    .{ .name = "a3", .index = 13 },
    .{ .name = "a4", .index = 14 },
    .{ .name = "a5", .index = 15 },
    .{ .name = "a6", .index = 16 },
    .{ .name = "a7", .index = 17 },
    .{ .name = "s2", .index = 18 },
    .{ .name = "s3", .index = 19 },
    .{ .name = "s4", .index = 20 },
    .{ .name = "s5", .index = 21 },
    .{ .name = "s6", .index = 22 },
    .{ .name = "s7", .index = 23 },
    .{ .name = "s8", .index = 24 },
    .{ .name = "s9", .index = 25 },
    .{ .name = "s10", .index = 26 },
    .{ .name = "s11", .index = 27 },
    .{ .name = "t3", .index = 28 },
    .{ .name = "t4", .index = 29 },
    .{ .name = "t5", .index = 30 },
    .{ .name = "t6", .index = 31 },
};

const float_abi_registers = [_]AbiRegister{
    .{ .name = "ft0", .index = 0 },
    .{ .name = "ft1", .index = 1 },
    .{ .name = "ft2", .index = 2 },
    .{ .name = "ft3", .index = 3 },
    .{ .name = "ft4", .index = 4 },
    .{ .name = "ft5", .index = 5 },
    .{ .name = "ft6", .index = 6 },
    .{ .name = "ft7", .index = 7 },
    .{ .name = "fs0", .index = 8 },
    .{ .name = "fs1", .index = 9 },
    .{ .name = "fa0", .index = 10 },
    .{ .name = "fa1", .index = 11 },
    .{ .name = "fa2", .index = 12 },
    .{ .name = "fa3", .index = 13 },
    .{ .name = "fa4", .index = 14 },
    .{ .name = "fa5", .index = 15 },
    .{ .name = "fa6", .index = 16 },
    .{ .name = "fa7", .index = 17 },
    .{ .name = "fs2", .index = 18 },
    .{ .name = "fs3", .index = 19 },
    .{ .name = "fs4", .index = 20 },
    .{ .name = "fs5", .index = 21 },
    .{ .name = "fs6", .index = 22 },
    .{ .name = "fs7", .index = 23 },
    .{ .name = "fs8", .index = 24 },
    .{ .name = "fs9", .index = 25 },
    .{ .name = "fs10", .index = 26 },
    .{ .name = "fs11", .index = 27 },
    .{ .name = "ft8", .index = 28 },
    .{ .name = "ft9", .index = 29 },
    .{ .name = "ft10", .index = 30 },
    .{ .name = "ft11", .index = 31 },
};

pub fn parseRegister(text: []const u8) types.EncodeError!Register {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    for (abi_registers) |entry| {
        if (std.ascii.eqlIgnoreCase(trimmed, entry.name)) return entry.index;
    }
    for (float_abi_registers) |entry| {
        if (std.ascii.eqlIgnoreCase(trimmed, entry.name)) return entry.index;
    }
    if (trimmed.len >= 2 and registerPrefix(trimmed[0])) {
        const value = std.fmt.parseUnsigned(u8, trimmed[1..], 10) catch return error.RegisterOutOfRange;
        if (value >= 32) return error.RegisterOutOfRange;
        return @intCast(value);
    }
    return error.RegisterOutOfRange;
}

fn registerPrefix(value: u8) bool {
    return value == 'x' or value == 'X' or value == 'f' or value == 'F' or value == 'v' or value == 'V';
}
