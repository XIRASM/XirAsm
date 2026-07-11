const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const CoffWeakCheckError = error{
    InvalidNumber,
    InvalidCoff,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 9) {
        try stderr.print(
            "usage: {s} <obj> <machine> <symptr> <nsyms> <weak-index> <fallback-index> <weak-name-u64> <sym-type>\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_machine = try parseNumber(u16, args[2]);
    const expected_symbol_ptr = try parseNumber(u32, args[3]);
    const expected_symbol_count = try parseNumber(u32, args[4]);
    const weak_index = try parseNumber(usize, args[5]);
    const expected_fallback_index = try parseNumber(u32, args[6]);
    const expected_weak_name = try parseNumber(u64, args[7]);
    const expected_sym_type = try parseNumber(u16, args[8]);

    const symbol_count = try toUsize(expected_symbol_count);
    const aux_index = try checkedAdd(usize, weak_index, 1);
    if (aux_index >= symbol_count) return CoffWeakCheckError.InvalidCoff;

    const symbol_table_offset = try toUsize(expected_symbol_ptr);
    const weak_offset = try checkedAdd(
        usize,
        symbol_table_offset,
        try checkedMul(usize, weak_index, 18),
    );
    const aux_offset = try checkedAdd(usize, weak_offset, 18);
    const string_table_offset = try checkedAdd(
        usize,
        symbol_table_offset,
        try checkedMul(usize, symbol_count, 18),
    );

    var failed = false;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "PointerToSymbolTable", expected_symbol_ptr, try readU32Le(bytes, 8))) or failed;
    failed = (try expectEqual(stderr, "NumberOfSymbols", expected_symbol_count, try readU32Le(bytes, 12))) or failed;
    failed = (try expectEqual(stderr, "Weak.Name", expected_weak_name, try readU64Le(bytes, weak_offset))) or failed;
    failed = (try expectEqual(stderr, "Weak.Value", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, weak_offset, 8)))) or failed;
    failed = (try expectEqual(stderr, "Weak.SectionNumber", @as(u16, 0), try readU16Le(bytes, try checkedAdd(usize, weak_offset, 12)))) or failed;
    failed = (try expectEqual(stderr, "Weak.Type", expected_sym_type, try readU16Le(bytes, try checkedAdd(usize, weak_offset, 14)))) or failed;
    failed = (try expectEqual(stderr, "Weak.StorageClass", @as(u8, 105), try readU8(bytes, try checkedAdd(usize, weak_offset, 16)))) or failed;
    failed = (try expectEqual(stderr, "Weak.NumberOfAuxSymbols", @as(u8, 1), try readU8(bytes, try checkedAdd(usize, weak_offset, 17)))) or failed;
    failed = (try expectEqual(stderr, "WeakAux.TagIndex", expected_fallback_index, try readU32Le(bytes, aux_offset))) or failed;
    failed = (try expectEqual(stderr, "WeakAux.Characteristics", @as(u32, 3), try readU32Le(bytes, try checkedAdd(usize, aux_offset, 4)))) or failed;
    failed = (try expectEqual(stderr, "WeakAux.Reserved0", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, aux_offset, 8)))) or failed;
    failed = (try expectEqual(stderr, "WeakAux.Reserved1", @as(u16, 0), try readU16Le(bytes, try checkedAdd(usize, aux_offset, 16)))) or failed;
    failed = (try expectEqual(stderr, "StringTable.Size", @as(u32, 4), try readU32Le(bytes, string_table_offset))) or failed;

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn parseNumber(comptime T: type, text: []const u8) !T {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        return std.fmt.parseInt(T, text[2..], 16) catch return CoffWeakCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return CoffWeakCheckError.InvalidNumber;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn readU8(bytes: []const u8, offset: usize) !u8 {
    if (offset >= bytes.len) return CoffWeakCheckError.InvalidCoff;
    return bytes[offset];
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return CoffWeakCheckError.InvalidCoff;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return CoffWeakCheckError.InvalidCoff;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn readU64Le(bytes: []const u8, offset: usize) !u64 {
    const end = try checkedAdd(usize, offset, 8);
    if (end > bytes.len) return CoffWeakCheckError.InvalidCoff;
    return @as(u64, bytes[offset]) |
        (@as(u64, bytes[offset + 1]) << 8) |
        (@as(u64, bytes[offset + 2]) << 16) |
        (@as(u64, bytes[offset + 3]) << 24) |
        (@as(u64, bytes[offset + 4]) << 32) |
        (@as(u64, bytes[offset + 5]) << 40) |
        (@as(u64, bytes[offset + 6]) << 48) |
        (@as(u64, bytes[offset + 7]) << 56);
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return CoffWeakCheckError.InvalidCoff;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return CoffWeakCheckError.InvalidCoff;
}

fn toUsize(value: u32) !usize {
    return std.math.cast(usize, value) orelse CoffWeakCheckError.InvalidCoff;
}
