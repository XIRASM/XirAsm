const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);
    if (args.len < 8) return error.InvalidArgs;

    const bytes = try readFile(allocator, init.io, args[1]);

    const machine = try parseNumber(u16, args[2]);
    const section_count = try parseNumber(u16, args[3]);
    const symbol_pointer = try parseNumber(u32, args[4]);
    const symbol_count = try parseNumber(u32, args[5]);
    const characteristics = try parseNumber(u16, args[6]);
    const string_size = try parseNumber(u32, args[7]);

    try expectEqual(machine, try readU16Le(bytes, 0), "Machine");
    try expectEqual(section_count, try readU16Le(bytes, 2), "NumberOfSections");
    try expectEqual(@as(u32, 0), try readU32Le(bytes, 4), "TimeDateStamp");
    try expectEqual(symbol_pointer, try readU32Le(bytes, 8), "PointerToSymbolTable");
    try expectEqual(symbol_count, try readU32Le(bytes, 12), "NumberOfSymbols");
    try expectEqual(@as(u16, 0), try readU16Le(bytes, 16), "SizeOfOptionalHeader");
    try expectEqual(characteristics, try readU16Le(bytes, 18), "Characteristics");

    var arg_index: usize = 8;
    for (0..section_count) |index| {
        if (arg_index + 4 > args.len) return error.InvalidArgs;
        const row = try checkedAdd(20, try checkedMul(40, index));
        try expectName(bytes, row, args[arg_index], "section name");
        arg_index += 1;
        try expectEqual(try parseNumber(u32, args[arg_index]), try readU32Le(bytes, row + 16), "SizeOfRawData");
        arg_index += 1;
        try expectEqual(try parseNumber(u32, args[arg_index]), try readU32Le(bytes, row + 20), "PointerToRawData");
        arg_index += 1;
        try expectEqual(@as(u32, 0), try readU32Le(bytes, row + 24), "PointerToRelocations");
        try expectEqual(@as(u16, 0), try readU16Le(bytes, row + 32), "NumberOfRelocations");
        try expectEqual(try parseNumber(u32, args[arg_index]), try readU32Le(bytes, row + 36), "Characteristics");
        arg_index += 1;
    }

    for (0..symbol_count) |index| {
        if (arg_index + 5 > args.len) return error.InvalidArgs;
        const entry = try checkedAdd(symbol_pointer, try checkedMul(18, index));
        const symbol_name = try readSymbolName(bytes, entry, symbol_pointer, symbol_count);
        try expectString(args[arg_index], symbol_name, "symbol name");
        arg_index += 1;
        try expectEqual(try parseNumber(u32, args[arg_index]), try readU32Le(bytes, entry + 8), "Symbol.Value");
        arg_index += 1;
        try expectEqual(try parseNumber(u16, args[arg_index]), try readU16Le(bytes, entry + 12), "Symbol.SectionNumber");
        arg_index += 1;
        try expectEqual(try parseNumber(u16, args[arg_index]), try readU16Le(bytes, entry + 14), "Symbol.Type");
        arg_index += 1;
        const storage_class = bytes[try toUsize(entry + 16)];
        try expectEqual(try parseNumber(u8, args[arg_index]), storage_class, "Symbol.StorageClass");
        arg_index += 1;
        try expectEqual(@as(u8, 0), bytes[try toUsize(entry + 17)], "Symbol.NumberOfAuxSymbols");
    }

    const string_table = try checkedAdd(symbol_pointer, try checkedMul(18, symbol_count));
    try expectEqual(string_size, try readU32Le(bytes, string_table), "StringTable.Size");
    while (arg_index < args.len) {
        if (arg_index + 2 > args.len) return error.InvalidArgs;
        const offset = try parseNumber(u64, args[arg_index]);
        arg_index += 1;
        try expectHexBytes(bytes, offset, args[arg_index]);
        arg_index += 1;
    }
    if (arg_index != args.len) return error.InvalidArgs;
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn parseNumber(comptime T: type, text: []const u8) !T {
    const base: u8 = if (std.mem.startsWith(u8, text, "0x")) 16 else 10;
    const start: usize = if (base == 16) 2 else 0;
    return std.fmt.parseInt(T, text[start..], base);
}

fn expectName(bytes: []const u8, offset: u64, expected: []const u8, label: []const u8) !void {
    const start = try toUsize(offset);
    const end = try checkedAdd(start, 8);
    if (end > bytes.len) return error.InvalidOffset;
    const actual = std.mem.sliceTo(bytes[start..end], 0);
    try expectString(expected, actual, label);
}

fn readSymbolName(bytes: []const u8, entry: u64, symbol_pointer: u32, symbol_count: u32) ![]const u8 {
    const zeroes = try readU32Le(bytes, entry);
    if (zeroes == 0) {
        const string_offset = try readU32Le(bytes, entry + 4);
        const string_table = try checkedAdd(symbol_pointer, try checkedMul(18, symbol_count));
        const name_start = try checkedAdd(string_table, string_offset);
        const start = try toUsize(name_start);
        if (start >= bytes.len) return error.InvalidOffset;
        return std.mem.sliceTo(bytes[start..], 0);
    }
    const start = try toUsize(entry);
    const end = try checkedAdd(start, 8);
    if (end > bytes.len) return error.InvalidOffset;
    return std.mem.sliceTo(bytes[start..end], 0);
}

fn expectHexBytes(bytes: []const u8, offset: u64, expected_hex: []const u8) !void {
    if (expected_hex.len % 2 != 0) return error.InvalidArgs;
    const start = try toUsize(offset);
    const expected_len = expected_hex.len / 2;
    const end = try checkedAdd(start, expected_len);
    if (end > bytes.len) return error.InvalidOffset;
    for (bytes[start..end], 0..) |actual, index| {
        const high = try hexNibble(expected_hex[index * 2]);
        const low = try hexNibble(expected_hex[index * 2 + 1]);
        const expected: u8 = (high << 4) | low;
        try expectEqual(expected, actual, "raw bytes");
    }
}

fn hexNibble(byte: u8) !u8 {
    if (byte >= '0' and byte <= '9') return byte - '0';
    if (byte >= 'a' and byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' and byte <= 'F') return byte - 'A' + 10;
    return error.InvalidArgs;
}

fn expectString(expected: []const u8, actual: []const u8, _: []const u8) !void {
    if (!std.mem.eql(u8, expected, actual)) {
        return error.CheckFailed;
    }
}

fn expectEqual(expected: anytype, actual: @TypeOf(expected), _: []const u8) !void {
    if (expected != actual) {
        return error.CheckFailed;
    }
}

fn readU16Le(bytes: []const u8, offset: u64) !u16 {
    const start = try toUsize(offset);
    const end = try checkedAdd(start, 2);
    if (end > bytes.len) return error.InvalidOffset;
    return std.mem.readInt(u16, bytes[start..end][0..2], .little);
}

fn readU32Le(bytes: []const u8, offset: u64) !u32 {
    const start = try toUsize(offset);
    const end = try checkedAdd(start, 4);
    if (end > bytes.len) return error.InvalidOffset;
    return std.mem.readInt(u32, bytes[start..end][0..4], .little);
}

fn checkedAdd(a: anytype, b: anytype) !@TypeOf(a + b) {
    return std.math.add(@TypeOf(a + b), a, b) catch error.InvalidOffset;
}

fn checkedMul(a: anytype, b: anytype) !@TypeOf(a * b) {
    return std.math.mul(@TypeOf(a * b), a, b) catch error.InvalidOffset;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse error.InvalidOffset;
}
