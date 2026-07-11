const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const ElfCheckError = error{
    InvalidNumber,
    InvalidElf,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 19 or (args.len - 13) % 6 != 0) {
        try stderr.print(
            "usage: {s} <elf> <class> <machine> <ehsize> <phentsize> <phoff> <phnum> <entry> <shoff> <shentsize> <shnum> <shstrndx> <ph-offset> <ph-vaddr> <ph-filesz> <ph-memsz> <ph-flags> <ph-align> [...]\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_class = try parseNumber(u8, args[2]);
    const expected_machine = try parseNumber(u16, args[3]);
    const expected_ehsize = try parseNumber(u16, args[4]);
    const expected_phentsize = try parseNumber(u16, args[5]);
    const expected_phoff = try parseNumber(u64, args[6]);
    const expected_phnum = try parseNumber(u16, args[7]);
    const expected_entry = try parseNumber(u64, args[8]);
    const expected_shoff = try parseNumber(u64, args[9]);
    const expected_shentsize = try parseNumber(u16, args[10]);
    const expected_shnum = try parseNumber(u16, args[11]);
    const expected_shstrndx = try parseNumber(u16, args[12]);
    const expected_segment_count = (args.len - 13) / 6;
    if (expected_segment_count != expected_phnum) return ElfCheckError.InvalidNumber;

    var failed = false;
    failed = (try expectEqual(stderr, "Magic", @as(u32, 0x464c457f), try readU32Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "Class", expected_class, try readU8(bytes, 4))) or failed;
    failed = (try expectEqual(stderr, "Data", @as(u8, 1), try readU8(bytes, 5))) or failed;
    failed = (try expectEqual(stderr, "IdentVersion", @as(u8, 1), try readU8(bytes, 6))) or failed;
    failed = (try expectEqual(stderr, "OsAbi", @as(u8, 0), try readU8(bytes, 7))) or failed;
    failed = (try expectEqual(stderr, "AbiVersion", @as(u8, 0), try readU8(bytes, 8))) or failed;
    try expectPaddingZero(stderr, bytes, &failed, 9, 16);
    failed = (try expectEqual(stderr, "Type", @as(u16, 2), try readU16Le(bytes, 16))) or failed;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, 18))) or failed;
    failed = (try expectEqual(stderr, "Version", @as(u32, 1), try readU32Le(bytes, 20))) or failed;

    if (expected_class == 2) {
        failed = (try expectEqual(stderr, "Entry", expected_entry, try readU64Le(bytes, 24))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderOffset", expected_phoff, try readU64Le(bytes, 32))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU64Le(bytes, 40))) or failed;
        failed = (try expectEqual(stderr, "Flags", @as(u32, 0), try readU32Le(bytes, 48))) or failed;
        failed = (try expectEqual(stderr, "HeaderSize", expected_ehsize, try readU16Le(bytes, 52))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderEntrySize", expected_phentsize, try readU16Le(bytes, 54))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderCount", expected_phnum, try readU16Le(bytes, 56))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderEntrySize", expected_shentsize, try readU16Le(bytes, 58))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderCount", expected_shnum, try readU16Le(bytes, 60))) or failed;
        failed = (try expectEqual(stderr, "SectionNameIndex", expected_shstrndx, try readU16Le(bytes, 62))) or failed;
        try checkProgramHeaders64(stderr, bytes, args[13..], try toUsize(expected_phoff), &failed);
    } else if (expected_class == 1) {
        failed = (try expectEqual(stderr, "Entry", expected_entry, try readU32Le(bytes, 24))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderOffset", expected_phoff, try readU32Le(bytes, 28))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU32Le(bytes, 32))) or failed;
        failed = (try expectEqual(stderr, "Flags", @as(u32, 0), try readU32Le(bytes, 36))) or failed;
        failed = (try expectEqual(stderr, "HeaderSize", expected_ehsize, try readU16Le(bytes, 40))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderEntrySize", expected_phentsize, try readU16Le(bytes, 42))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderCount", expected_phnum, try readU16Le(bytes, 44))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderEntrySize", expected_shentsize, try readU16Le(bytes, 46))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderCount", expected_shnum, try readU16Le(bytes, 48))) or failed;
        failed = (try expectEqual(stderr, "SectionNameIndex", expected_shstrndx, try readU16Le(bytes, 50))) or failed;
        try checkProgramHeaders32(stderr, bytes, args[13..], try toUsize(expected_phoff), &failed);
    } else {
        try stderr.print("unsupported ELF class: {d}\n", .{expected_class});
        failed = true;
    }

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn checkProgramHeaders64(stderr: *Io.Writer, bytes: []const u8, args: []const []const u8, phoff: usize, failed: *bool) !void {
    var segment_index: usize = 0;
    while (segment_index < args.len / 6) : (segment_index += 1) {
        const arg_offset = segment_index * 6;
        const expected_offset = try parseNumber(u64, args[arg_offset]);
        const expected_vaddr = try parseNumber(u64, args[arg_offset + 1]);
        const expected_filesz = try parseNumber(u64, args[arg_offset + 2]);
        const expected_memsz = try parseNumber(u64, args[arg_offset + 3]);
        const expected_flags = try parseNumber(u32, args[arg_offset + 4]);
        const expected_align = try parseNumber(u64, args[arg_offset + 5]);
        const entry_offset = try checkedAdd(usize, phoff, try checkedMul(usize, segment_index, 56));
        failed.* = (try expectEqual(stderr, "SegmentType", @as(u32, 1), try readU32Le(bytes, entry_offset))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentFlags", expected_flags, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 4)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentOffset", expected_offset, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 8)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentVaddr", expected_vaddr, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 16)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentPaddr", expected_vaddr, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 24)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentFilesz", expected_filesz, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 32)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentMemsz", expected_memsz, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 40)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentAlign", expected_align, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 48)))) or failed.*;
    }
}

fn checkProgramHeaders32(stderr: *Io.Writer, bytes: []const u8, args: []const []const u8, phoff: usize, failed: *bool) !void {
    var segment_index: usize = 0;
    while (segment_index < args.len / 6) : (segment_index += 1) {
        const arg_offset = segment_index * 6;
        const expected_offset = try parseNumber(u32, args[arg_offset]);
        const expected_vaddr = try parseNumber(u32, args[arg_offset + 1]);
        const expected_filesz = try parseNumber(u32, args[arg_offset + 2]);
        const expected_memsz = try parseNumber(u32, args[arg_offset + 3]);
        const expected_flags = try parseNumber(u32, args[arg_offset + 4]);
        const expected_align = try parseNumber(u32, args[arg_offset + 5]);
        const entry_offset = try checkedAdd(usize, phoff, try checkedMul(usize, segment_index, 32));
        failed.* = (try expectEqual(stderr, "SegmentType", @as(u32, 1), try readU32Le(bytes, entry_offset))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentOffset", expected_offset, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 4)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentVaddr", expected_vaddr, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 8)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentPaddr", expected_vaddr, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 12)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentFilesz", expected_filesz, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 16)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentMemsz", expected_memsz, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 20)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentFlags", expected_flags, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 24)))) or failed.*;
        failed.* = (try expectEqual(stderr, "SegmentAlign", expected_align, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 28)))) or failed.*;
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn parseNumber(comptime T: type, text: []const u8) !T {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        return std.fmt.parseInt(T, text[2..], 16) catch return ElfCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return ElfCheckError.InvalidNumber;
}

fn expectPaddingZero(stderr: *Io.Writer, bytes: []const u8, failed: *bool, start: usize, end: usize) !void {
    var offset = start;
    while (offset < end) : (offset += 1) {
        failed.* = (try expectEqual(stderr, "IdentPadding", @as(u8, 0), try readU8(bytes, offset))) or failed.*;
    }
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn readU8(bytes: []const u8, offset: usize) !u8 {
    const end = try checkedAdd(usize, offset, 1);
    if (end > bytes.len) return ElfCheckError.InvalidElf;
    return bytes[offset];
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return ElfCheckError.InvalidElf;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return ElfCheckError.InvalidElf;
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
    return std.math.add(T, lhs, rhs) catch return ElfCheckError.InvalidElf;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return ElfCheckError.InvalidElf;
}

fn toUsize(value: u64) !usize {
    return std.math.cast(usize, value) orelse ElfCheckError.InvalidElf;
}
