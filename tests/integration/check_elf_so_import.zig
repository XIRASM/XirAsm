const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const CheckError = error{
    InvalidNumber,
    InvalidElfSoImport,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 34) {
        try stderr.print(
            "usage: {s} <so> <file-size> <shoff> <first-load-filesz> <plt-offset> <plt-vaddr> <plt-size> <metadata-offset> <metadata-vaddr> <metadata-size> <dynsym-offset> <dynsym-vaddr> <dynstr-offset> <dynstr-vaddr> <dynstr-size> <hash-offset> <hash-vaddr> <rela-offset> <rela-vaddr> <rela-size> <dynamic-offset> <dynamic-vaddr> <dynamic-size> <slot-offset> <slot-vaddr> <plt-entry-offset> <plt-entry-vaddr> <gotplt-offset> <gotplt-vaddr> <jmprel-offset> <jmprel-vaddr> <jmprel-size> <symbol-name>\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_file_size = try parseNumber(u64, args[2]);
    const expected_shoff = try parseNumber(u64, args[3]);
    const expected_first_load_filesz = try parseNumber(u64, args[4]);
    const expected_plt_offset = try parseNumber(u64, args[5]);
    const expected_plt_vaddr = try parseNumber(u64, args[6]);
    const expected_plt_size = try parseNumber(u64, args[7]);
    const expected_metadata_offset = try parseNumber(u64, args[8]);
    const expected_metadata_vaddr = try parseNumber(u64, args[9]);
    const expected_metadata_size = try parseNumber(u64, args[10]);
    const expected_dynsym_offset = try parseNumber(u64, args[11]);
    const expected_dynsym_vaddr = try parseNumber(u64, args[12]);
    const expected_dynstr_offset = try parseNumber(u64, args[13]);
    const expected_dynstr_vaddr = try parseNumber(u64, args[14]);
    const expected_dynstr_size = try parseNumber(u64, args[15]);
    const expected_hash_offset = try parseNumber(u64, args[16]);
    const expected_hash_vaddr = try parseNumber(u64, args[17]);
    const expected_rela_offset = try parseNumber(u64, args[18]);
    const expected_rela_vaddr = try parseNumber(u64, args[19]);
    const expected_rela_size = try parseNumber(u64, args[20]);
    const expected_dynamic_offset = try parseNumber(u64, args[21]);
    const expected_dynamic_vaddr = try parseNumber(u64, args[22]);
    const expected_dynamic_size = try parseNumber(u64, args[23]);
    const expected_slot_offset = try parseNumber(u64, args[24]);
    const expected_slot_vaddr = try parseNumber(u64, args[25]);
    const expected_plt_entry_offset = try parseNumber(u64, args[26]);
    const expected_plt_entry_vaddr = try parseNumber(u64, args[27]);
    const expected_gotplt_offset = try parseNumber(u64, args[28]);
    const expected_gotplt_vaddr = try parseNumber(u64, args[29]);
    const expected_jmprel_offset = try parseNumber(u64, args[30]);
    const expected_jmprel_vaddr = try parseNumber(u64, args[31]);
    const expected_jmprel_size = try parseNumber(u64, args[32]);
    const expected_symbol = args[33];

    var failed = false;
    failed = (try expectEqual(stderr, "FileSize", expected_file_size, bytes.len)) or failed;
    failed = (try expectEqual(stderr, "RelaPltSizeAlias", expected_rela_size, expected_jmprel_size)) or failed;
    failed = (try expectEqual(stderr, "Magic", @as(u32, 0x464c457f), try readU32Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "Type", @as(u16, 3), try readU16Le(bytes, 16))) or failed;
    failed = (try expectEqual(stderr, "Machine", @as(u16, 62), try readU16Le(bytes, 18))) or failed;
    failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU64Le(bytes, 40))) or failed;
    failed = (try expectEqual(stderr, "ProgramHeaderCount", @as(u16, 4), try readU16Le(bytes, 56))) or failed;
    failed = (try expectEqual(stderr, "SectionHeaderCount", @as(u16, 10), try readU16Le(bytes, 60))) or failed;
    failed = (try expectEqual(stderr, "SectionNameStringIndex", @as(u16, 9), try readU16Le(bytes, 62))) or failed;

    failed = (try expectEqual(stderr, "LoadType", @as(u32, 1), try readU32Le(bytes, 64))) or failed;
    failed = (try expectEqual(stderr, "LoadFlags", @as(u32, 5), try readU32Le(bytes, 68))) or failed;
    failed = (try expectEqual(stderr, "LoadOffset", @as(u64, 0), try readU64Le(bytes, 72))) or failed;
    failed = (try expectEqual(stderr, "LoadVaddr", @as(u64, 0), try readU64Le(bytes, 80))) or failed;
    failed = (try expectEqual(stderr, "LoadFilesz", expected_first_load_filesz, try readU64Le(bytes, 96))) or failed;
    failed = (try expectEqual(stderr, "PltType", @as(u32, 1), try readU32Le(bytes, 120))) or failed;
    failed = (try expectEqual(stderr, "PltFlags", @as(u32, 5), try readU32Le(bytes, 124))) or failed;
    failed = (try expectEqual(stderr, "PltOffset", expected_plt_offset, try readU64Le(bytes, 128))) or failed;
    failed = (try expectEqual(stderr, "PltVaddr", expected_plt_vaddr, try readU64Le(bytes, 136))) or failed;
    failed = (try expectEqual(stderr, "PltFilesz", expected_plt_size, try readU64Le(bytes, 152))) or failed;
    failed = (try expectEqual(stderr, "MetadataType", @as(u32, 1), try readU32Le(bytes, 176))) or failed;
    failed = (try expectEqual(stderr, "MetadataFlags", @as(u32, 6), try readU32Le(bytes, 180))) or failed;
    failed = (try expectEqual(stderr, "MetadataOffset", expected_metadata_offset, try readU64Le(bytes, 184))) or failed;
    failed = (try expectEqual(stderr, "MetadataVaddr", expected_metadata_vaddr, try readU64Le(bytes, 192))) or failed;
    failed = (try expectEqual(stderr, "MetadataFilesz", expected_metadata_size, try readU64Le(bytes, 208))) or failed;
    failed = (try expectEqual(stderr, "DynamicType", @as(u32, 2), try readU32Le(bytes, 232))) or failed;
    failed = (try expectEqual(stderr, "DynamicFlags", @as(u32, 6), try readU32Le(bytes, 236))) or failed;
    failed = (try expectEqual(stderr, "DynamicOffset", expected_dynamic_offset, try readU64Le(bytes, 240))) or failed;
    failed = (try expectEqual(stderr, "DynamicVaddr", expected_dynamic_vaddr, try readU64Le(bytes, 248))) or failed;
    failed = (try expectEqual(stderr, "DynamicFilesz", expected_dynamic_size, try readU64Le(bytes, 264))) or failed;

    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 0, 4, expected_hash_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 1, 5, expected_dynstr_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 2, 10, expected_dynstr_size)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 3, 6, expected_dynsym_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 4, 11, 24)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 5, 3, expected_gotplt_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 6, 2, expected_jmprel_size)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 7, 20, 7)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 8, 23, expected_jmprel_vaddr)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 9, 1, 45)) or failed;
    failed = (try expectDynamic(stderr, bytes, expected_dynamic_offset, 10, 0, 0)) or failed;

    failed = (try expectEqual(stderr, "GotPltDynamic", expected_dynamic_vaddr, try readU64Le(bytes, try toUsize(expected_gotplt_offset)))) or failed;
    failed = (try expectEqual(stderr, "GotPltResolver0", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, try toUsize(expected_gotplt_offset), 8)))) or failed;
    failed = (try expectEqual(stderr, "GotPltResolver1", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, try toUsize(expected_gotplt_offset), 16)))) or failed;
    failed = (try expectEqual(stderr, "GotPltSlotInitialValue", expected_plt_entry_vaddr + 6, try readU64Le(bytes, try toUsize(expected_slot_offset)))) or failed;
    failed = (try expectEqual(stderr, "PltEntryJmpOpcode", @as(u16, 0x25ff), try readU16Le(bytes, try toUsize(expected_plt_entry_offset)))) or failed;
    failed = (try expectEqual(stderr, "PltEntryPushOpcode", @as(u8, 0x68), try readU8(bytes, try checkedAdd(usize, try toUsize(expected_plt_entry_offset), 6)))) or failed;
    failed = (try expectEqual(stderr, "PltEntryIndex", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_plt_entry_offset), 7)))) or failed;
    failed = (try expectEqual(stderr, "PltEntryJmpBackOpcode", @as(u8, 0xe9), try readU8(bytes, try checkedAdd(usize, try toUsize(expected_plt_entry_offset), 11)))) or failed;
    failed = (try expectEqual(stderr, "ImportSymbolNameOffset", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_dynsym_offset), 24)))) or failed;
    failed = (try expectEqual(stderr, "ImportSymbolInfo", @as(u8, 0x12), try readU8(bytes, try checkedAdd(usize, try toUsize(expected_dynsym_offset), 28)))) or failed;
    failed = (try expectEqual(stderr, "ImportSymbolSection", @as(u16, 0), try readU16Le(bytes, try checkedAdd(usize, try toUsize(expected_dynsym_offset), 30)))) or failed;
    failed = (try expectBytes(stderr, "ImportSymbolName", expected_symbol, bytes, try checkedAdd(usize, try toUsize(expected_dynstr_offset), 1))) or failed;
    failed = (try expectBytes(stderr, "ExportSymbolName", "exported_call_puts", bytes, try checkedAdd(usize, try toUsize(expected_dynstr_offset), 6))) or failed;
    failed = (try expectBytes(stderr, "NeededLibrary", "libc.so.6", bytes, try checkedAdd(usize, try toUsize(expected_dynstr_offset), 45))) or failed;

    failed = (try expectEqual(stderr, "HashBucketCount", @as(u32, 1), try readU32Le(bytes, try toUsize(expected_hash_offset)))) or failed;
    failed = (try expectEqual(stderr, "HashChainCount", @as(u32, 3), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 4)))) or failed;
    failed = (try expectEqual(stderr, "HashBucket0", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 8)))) or failed;
    failed = (try expectEqual(stderr, "HashChain0", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 12)))) or failed;
    failed = (try expectEqual(stderr, "HashChain1", @as(u32, 2), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 16)))) or failed;
    failed = (try expectEqual(stderr, "HashChain2", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, try toUsize(expected_hash_offset), 20)))) or failed;

    failed = (try expectEqual(stderr, "RelaOffset", expected_slot_vaddr, try readU64Le(bytes, try toUsize(expected_rela_offset)))) or failed;
    failed = (try expectEqual(stderr, "RelaInfo", @as(u64, 0x100000007), try readU64Le(bytes, try checkedAdd(usize, try toUsize(expected_rela_offset), 8)))) or failed;
    failed = (try expectEqual(stderr, "RelaAddend", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, try toUsize(expected_rela_offset), 16)))) or failed;
    failed = (try expectEqual(stderr, "JmpRelOffsetAlias", expected_rela_offset, expected_jmprel_offset)) or failed;
    failed = (try expectEqual(stderr, "JmpRelVaddrAlias", expected_rela_vaddr, expected_jmprel_vaddr)) or failed;

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
        return std.fmt.parseInt(T, text[2..], 16) catch return CheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return CheckError.InvalidNumber;
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
    if (end > bytes.len) return CheckError.InvalidElfSoImport;
    if (std.mem.eql(u8, expected, bytes[offset..end])) return false;
    try stderr.print("{s} mismatch\n", .{name});
    return true;
}

fn readU8(bytes: []const u8, offset: usize) !u8 {
    const end = try checkedAdd(usize, offset, 1);
    if (end > bytes.len) return CheckError.InvalidElfSoImport;
    return bytes[offset];
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return CheckError.InvalidElfSoImport;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return CheckError.InvalidElfSoImport;
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
    return std.math.add(T, lhs, rhs) catch return CheckError.InvalidElfSoImport;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return CheckError.InvalidElfSoImport;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse CheckError.InvalidElfSoImport;
}
