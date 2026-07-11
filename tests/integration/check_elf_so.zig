const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const ElfSoCheckError = error{
    InvalidNumber,
    InvalidElfSo,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 20 or ((args.len - 20) % 3) != 0) {
        try stderr.print(
            "usage: {s} <so> <shoff> <shnum> <shstrndx> <first-load-filesz> <metadata-offset> <metadata-vaddr> <metadata-filesz> <dynamic-offset> <dynamic-vaddr> <dynamic-size> <dynsym-offset> <dynsym-vaddr> <dynstr-offset> <dynstr-vaddr> <dynstr-size> <hash-offset> <hash-vaddr> <export-count> [<export-name> <export-value> <export-size>]...\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_shoff = try parseNumber(u64, args[2]);
    const expected_shnum = try parseNumber(u16, args[3]);
    const expected_shstrndx = try parseNumber(u16, args[4]);
    const expected_first_load_filesz = try parseNumber(u64, args[5]);
    const expected_metadata_offset = try parseNumber(u64, args[6]);
    const expected_metadata_vaddr = try parseNumber(u64, args[7]);
    const expected_metadata_filesz = try parseNumber(u64, args[8]);
    const expected_dynamic_offset = try parseNumber(u64, args[9]);
    const expected_dynamic_vaddr = try parseNumber(u64, args[10]);
    const expected_dynamic_size = try parseNumber(u64, args[11]);
    const expected_dynsym_offset = try parseNumber(u64, args[12]);
    const expected_dynsym_vaddr = try parseNumber(u64, args[13]);
    const expected_dynstr_offset = try parseNumber(u64, args[14]);
    const expected_dynstr_vaddr = try parseNumber(u64, args[15]);
    const expected_dynstr_size = try parseNumber(u64, args[16]);
    const expected_hash_offset = try parseNumber(u64, args[17]);
    const expected_hash_vaddr = try parseNumber(u64, args[18]);
    const export_count = try parseNumber(usize, args[19]);
    if (args.len != 20 + export_count * 3) {
        try stderr.print("export count does not match export arguments\n", .{});
        try stderr.flush();
        std.process.exit(2);
    }

    var failed = false;
    failed = (try expectEqual(stderr, "Magic", @as(u32, 0x464c457f), try readU32Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "Class", @as(u8, 2), try readU8(bytes, 4))) or failed;
    failed = (try expectEqual(stderr, "Data", @as(u8, 1), try readU8(bytes, 5))) or failed;
    failed = (try expectEqual(stderr, "Type", @as(u16, 3), try readU16Le(bytes, 16))) or failed;
    failed = (try expectEqual(stderr, "Machine", @as(u16, 62), try readU16Le(bytes, 18))) or failed;
    failed = (try expectEqual(stderr, "ProgramHeaderOffset", @as(u64, 64), try readU64Le(bytes, 32))) or failed;
    failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU64Le(bytes, 40))) or failed;
    failed = (try expectEqual(stderr, "ProgramHeaderCount", @as(u16, 3), try readU16Le(bytes, 56))) or failed;
    failed = (try expectEqual(stderr, "SectionHeaderCount", expected_shnum, try readU16Le(bytes, 60))) or failed;
    failed = (try expectEqual(stderr, "SectionNameStringIndex", expected_shstrndx, try readU16Le(bytes, 62))) or failed;

    failed = (try expectEqual(stderr, "LoadType", @as(u32, 1), try readU32Le(bytes, 64))) or failed;
    failed = (try expectEqual(stderr, "LoadFlags", @as(u32, 5), try readU32Le(bytes, 68))) or failed;
    failed = (try expectEqual(stderr, "LoadOffset", @as(u64, 0), try readU64Le(bytes, 72))) or failed;
    failed = (try expectEqual(stderr, "LoadVaddr", @as(u64, 0), try readU64Le(bytes, 80))) or failed;
    failed = (try expectEqual(stderr, "LoadFilesz", expected_first_load_filesz, try readU64Le(bytes, 96))) or failed;
    failed = (try expectEqual(stderr, "MetadataType", @as(u32, 1), try readU32Le(bytes, 120))) or failed;
    failed = (try expectEqual(stderr, "MetadataFlags", @as(u32, 6), try readU32Le(bytes, 124))) or failed;
    failed = (try expectEqual(stderr, "MetadataOffset", expected_metadata_offset, try readU64Le(bytes, 128))) or failed;
    failed = (try expectEqual(stderr, "MetadataVaddr", expected_metadata_vaddr, try readU64Le(bytes, 136))) or failed;
    failed = (try expectEqual(stderr, "MetadataFilesz", expected_metadata_filesz, try readU64Le(bytes, 152))) or failed;
    failed = (try expectEqual(stderr, "DynamicType", @as(u32, 2), try readU32Le(bytes, 176))) or failed;
    failed = (try expectEqual(stderr, "DynamicFlags", @as(u32, 6), try readU32Le(bytes, 180))) or failed;
    failed = (try expectEqual(stderr, "DynamicOffset", expected_dynamic_offset, try readU64Le(bytes, 184))) or failed;
    failed = (try expectEqual(stderr, "DynamicVaddr", expected_dynamic_vaddr, try readU64Le(bytes, 192))) or failed;
    failed = (try expectEqual(stderr, "DynamicFilesz", expected_dynamic_size, try readU64Le(bytes, 208))) or failed;

    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 0, 4, expected_hash_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 1, 5, expected_dynstr_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 2, 10, expected_dynstr_size)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 3, 6, expected_dynsym_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 4, 11, 24)) or failed;
    var name_offset: u32 = 1;
    var export_index: usize = 0;
    while (export_index < export_count) : (export_index += 1) {
        const arg_base = 20 + export_index * 3;
        const expected_name = args[arg_base];
        const expected_export_value = try parseNumber(u64, args[arg_base + 1]);
        const expected_export_size = try parseNumber(u64, args[arg_base + 2]);
        const export_symbol = try checkedAdd(usize, try toUsize(expected_dynsym_offset), try checkedMul(usize, export_index + 1, 24));

        failed = (try expectEqual(stderr, "ExportNameOffset", name_offset, try readU32Le(bytes, export_symbol))) or failed;
        failed = (try expectEqual(stderr, "ExportInfo", @as(u8, 0x12), try readU8(bytes, try checkedAdd(usize, export_symbol, 4)))) or failed;
        failed = (try expectEqual(stderr, "ExportSectionIndex", @as(u16, 1), try readU16Le(bytes, try checkedAdd(usize, export_symbol, 6)))) or failed;
        failed = (try expectEqual(stderr, "ExportValue", expected_export_value, try readU64Le(bytes, try checkedAdd(usize, export_symbol, 8)))) or failed;
        failed = (try expectEqual(stderr, "ExportSize", expected_export_size, try readU64Le(bytes, try checkedAdd(usize, export_symbol, 16)))) or failed;
        failed = (try expectBytes(stderr, "ExportName", expected_name, bytes, try checkedAdd(usize, try toUsize(expected_dynstr_offset), name_offset))) or failed;
        name_offset = try checkedAdd(u32, name_offset, try checkedAdd(u32, try toU32(expected_name.len), 1));
    }
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 5, 14, name_offset)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 6, 0, 0)) or failed;

    failed = (try expectEqual(stderr, "HashBucketCount", @as(u32, 1), try readU32Le(bytes, try toUsize(expected_hash_offset)))) or failed;
    failed = (try expectEqual(stderr, "HashChainCount", try checkedAdd(u32, try toU32(export_count), 1), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 4)))) or failed;
    if (export_count > 0) {
        failed = (try expectEqual(stderr, "HashBucket0", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 8)))) or failed;
    }
    var chain_index: usize = 1;
    while (chain_index <= export_count) : (chain_index += 1) {
        const expected_chain: u32 = if (chain_index < export_count) try toU32(chain_index + 1) else 0;
        const chain_offset = try checkedAdd(usize, try toUsize(expected_hash_offset), try checkedAdd(usize, 12, try checkedMul(usize, chain_index, 4)));
        failed = (try expectEqual(stderr, "HashChain", expected_chain, try readU32Le(bytes, chain_offset))) or failed;
    }

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
        return std.fmt.parseInt(T, text[2..], 16) catch return ElfSoCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return ElfSoCheckError.InvalidNumber;
}

fn expectDynamic(stderr: *Io.Writer, bytes: []const u8, dynamic_offset: u64, index: usize, expected_tag: u64, expected_value: u64) !bool {
    const entry_offset = try checkedAdd(usize, try toUsize(dynamic_offset), try checkedMul(usize, index, 16));
    var failed = false;
    failed = (try expectEqual(stderr, "DynamicTag", expected_tag, try readU64Le(bytes, entry_offset))) or failed;
    failed = (try expectEqual(stderr, "DynamicValue", expected_value, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 8)))) or failed;
    return failed;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn expectBytes(stderr: *Io.Writer, name: []const u8, expected: []const u8, bytes: []const u8, offset: usize) !bool {
    const end = try checkedAdd(usize, offset, expected.len);
    if (end > bytes.len) return ElfSoCheckError.InvalidElfSo;
    if (std.mem.eql(u8, expected, bytes[offset..end])) return false;
    try stderr.print("{s} mismatch\n", .{name});
    return true;
}

fn readU8(bytes: []const u8, offset: usize) !u8 {
    const end = try checkedAdd(usize, offset, 1);
    if (end > bytes.len) return ElfSoCheckError.InvalidElfSo;
    return bytes[offset];
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return ElfSoCheckError.InvalidElfSo;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return ElfSoCheckError.InvalidElfSo;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn readU64Le(bytes: []const u8, offset: usize) !u64 {
    const low = try readU32Le(bytes, offset);
    const high = try readU32Le(bytes, try checkedAdd(usize, offset, 4));
    return @as(u64, low) | (@as(u64, high) << 32);
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return ElfSoCheckError.InvalidElfSo;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return ElfSoCheckError.InvalidElfSo;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse ElfSoCheckError.InvalidElfSo;
}

fn toU32(value: anytype) !u32 {
    return std.math.cast(u32, value) orelse ElfSoCheckError.InvalidElfSo;
}
