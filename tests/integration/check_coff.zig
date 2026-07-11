const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const CoffCheckError = error{
    InvalidNumber,
    InvalidCoff,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 12) {
        try stderr.print(
            "usage: {s} <obj> <machine> <sections> <symptr> <nsyms> <section-index> <reloc-ptr> <reloc-count> <reloc-va> <reloc-symbol> <reloc-type>\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_machine = try parseNumber(u16, args[2]);
    const expected_sections = try parseNumber(u16, args[3]);
    const expected_symbol_ptr = try parseNumber(u32, args[4]);
    const expected_symbol_count = try parseNumber(u32, args[5]);
    const section_index = try parseNumber(usize, args[6]);
    const expected_reloc_ptr = try parseNumber(u32, args[7]);
    const expected_reloc_count = try parseNumber(u16, args[8]);
    const expected_reloc_va = try parseNumber(u32, args[9]);
    const expected_reloc_symbol = try parseNumber(u32, args[10]);
    const expected_reloc_type = try parseNumber(u16, args[11]);

    var failed = false;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "NumberOfSections", expected_sections, try readU16Le(bytes, 2))) or failed;
    failed = (try expectEqual(stderr, "PointerToSymbolTable", expected_symbol_ptr, try readU32Le(bytes, 8))) or failed;
    failed = (try expectEqual(stderr, "NumberOfSymbols", expected_symbol_count, try readU32Le(bytes, 12))) or failed;

    const section_offset = try checkedAdd(usize, 20, try checkedMul(usize, section_index, 40));
    failed = (try expectEqual(stderr, "PointerToRelocations", expected_reloc_ptr, try readU32Le(bytes, try checkedAdd(usize, section_offset, 24)))) or failed;
    failed = (try expectEqual(stderr, "NumberOfRelocations", expected_reloc_count, try readU16Le(bytes, try checkedAdd(usize, section_offset, 32)))) or failed;

    const reloc_offset = try toUsize(expected_reloc_ptr);
    failed = (try expectEqual(stderr, "Reloc.VirtualAddress", expected_reloc_va, try readU32Le(bytes, reloc_offset))) or failed;
    failed = (try expectEqual(stderr, "Reloc.SymbolTableIndex", expected_reloc_symbol, try readU32Le(bytes, try checkedAdd(usize, reloc_offset, 4)))) or failed;
    failed = (try expectEqual(stderr, "Reloc.Type", expected_reloc_type, try readU16Le(bytes, try checkedAdd(usize, reloc_offset, 8)))) or failed;

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
        return std.fmt.parseInt(T, text[2..], 16) catch return CoffCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return CoffCheckError.InvalidNumber;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return CoffCheckError.InvalidCoff;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return CoffCheckError.InvalidCoff;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return CoffCheckError.InvalidCoff;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return CoffCheckError.InvalidCoff;
}

fn toUsize(value: u32) !usize {
    return std.math.cast(usize, value) orelse CoffCheckError.InvalidCoff;
}
