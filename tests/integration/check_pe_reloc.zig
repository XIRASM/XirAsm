const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const PeRelocCheckError = error{
    InvalidNumber,
    InvalidPe,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 6) {
        try stderr.print("usage: {s} <pe> <bits> <reloc-rva> <reloc-size> <reloc-hex>\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const bits = try parseNumber(u16, args[2]);
    const expected_reloc_rva = try parseNumber(u32, args[3]);
    const expected_reloc_size = try parseNumber(u32, args[4]);
    const expected_reloc = try parseHex(allocator, args[5]);

    var failed = false;

    const pe_offset = try readU32Le(bytes, 0x3c);
    const pe = try toUsize(pe_offset);
    const expected_machine: u16 = if (bits == 64) 0x8664 else if (bits == 32) 0x014c else return PeRelocCheckError.InvalidPe;
    const expected_opt_magic: u16 = if (bits == 64) 0x020b else 0x010b;

    failed = (try expectEqual(stderr, "MzMagic", @as(u16, 0x5a4d), try readU16Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "PeSignature", @as(u32, 0x00004550), try readU32Le(bytes, pe))) or failed;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, try checkedAdd(usize, pe, 4)))) or failed;

    const section_count = try readU16Le(bytes, try checkedAdd(usize, pe, 6));
    const optional_size = try readU16Le(bytes, try checkedAdd(usize, pe, 20));
    const optional = try checkedAdd(usize, pe, 24);
    failed = (try expectEqual(stderr, "OptionalMagic", expected_opt_magic, try readU16Le(bytes, optional))) or failed;

    const data_dir_offset = try checkedAdd(usize, optional, if (bits == 64) 112 else 96);
    const reloc_dir_offset = try checkedAdd(usize, data_dir_offset, 5 * 8);
    const actual_reloc_rva = try readU32Le(bytes, reloc_dir_offset);
    const actual_reloc_size = try readU32Le(bytes, try checkedAdd(usize, reloc_dir_offset, 4));
    failed = (try expectEqual(stderr, "BaseRelocDataDirectoryRva", expected_reloc_rva, actual_reloc_rva)) or failed;
    failed = (try expectEqual(stderr, "BaseRelocDataDirectorySize", expected_reloc_size, actual_reloc_size)) or failed;

    const section_table = try checkedAdd(usize, optional, optional_size);
    const reloc_offset = try rvaToOffset(bytes, section_table, section_count, actual_reloc_rva);
    const reloc_end = try checkedAdd(usize, reloc_offset, try toUsize(actual_reloc_size));
    if (reloc_end > bytes.len) return PeRelocCheckError.InvalidPe;
    failed = (try expectBytes(stderr, "BaseRelocBytes", expected_reloc, bytes[reloc_offset..reloc_end])) or failed;

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
        return std.fmt.parseInt(T, text[2..], 16) catch return PeRelocCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return PeRelocCheckError.InvalidNumber;
}

fn parseHex(allocator: Allocator, text: []const u8) ![]u8 {
    if ((text.len % 2) != 0) return PeRelocCheckError.InvalidNumber;

    const bytes = try allocator.alloc(u8, text.len / 2);
    var index: usize = 0;
    while (index < bytes.len) : (index += 1) {
        const text_offset = index * 2;
        bytes[index] = std.fmt.parseInt(u8, text[text_offset .. text_offset + 2], 16) catch return PeRelocCheckError.InvalidNumber;
    }
    return bytes;
}

fn rvaToOffset(bytes: []const u8, section_table: usize, section_count: u16, rva: u32) !usize {
    const section_total = try toUsize(section_count);
    var section_index: usize = 0;
    while (section_index < section_total) : (section_index += 1) {
        const row = try checkedAdd(usize, section_table, try checkedMul(usize, section_index, 40));
        const virtual_size = try readU32Le(bytes, try checkedAdd(usize, row, 8));
        const virtual_address = try readU32Le(bytes, try checkedAdd(usize, row, 12));
        const raw_size = try readU32Le(bytes, try checkedAdd(usize, row, 16));
        const raw_pointer = try readU32Le(bytes, try checkedAdd(usize, row, 20));
        const extent = @max(virtual_size, raw_size);
        if (rva >= virtual_address) {
            const delta = rva - virtual_address;
            if (delta < extent) {
                if (delta >= raw_size) return PeRelocCheckError.InvalidPe;
                return checkedAdd(usize, try toUsize(raw_pointer), try toUsize(delta));
            }
        }
    }
    return PeRelocCheckError.InvalidPe;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn expectBytes(stderr: *Io.Writer, name: []const u8, expected: []const u8, actual: []const u8) !bool {
    if (std.mem.eql(u8, expected, actual)) return false;
    try stderr.print("{s} mismatch: expected {d} bytes, actual {d} bytes\n", .{ name, expected.len, actual.len });
    return true;
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return PeRelocCheckError.InvalidPe;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return PeRelocCheckError.InvalidPe;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return PeRelocCheckError.InvalidPe;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return PeRelocCheckError.InvalidPe;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse PeRelocCheckError.InvalidPe;
}
