const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const ElfCheckError = error{
    InvalidNumber,
    InvalidElf,
};

const ExpectedProgramHeader = struct {
    segment_type: u64,
    flags: u64,
    offset: u64,
    vaddr: u64,
    paddr: u64,
    filesz: u64,
    memsz: u64,
    alignment: u64,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 16 or (args.len - 8) % 8 != 0) {
        try stderr.print(
            "usage: {s} <elf> <class> <machine> <phoff> <phnum> <entry> <elf-type> <type> <flags> <offset> <vaddr> <paddr> <filesz> <memsz> <align> [...]\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_class = try parseNumber(u8, args[2]);
    const expected_machine = try parseNumber(u16, args[3]);
    const expected_phoff = try parseNumber(u64, args[4]);
    const expected_phnum = try parseNumber(u16, args[5]);
    const expected_entry = try parseNumber(u64, args[6]);
    const expected_type = try parseNumber(u16, args[7]);
    const expected_segment_count = (args.len - 8) / 8;
    if (expected_segment_count != expected_phnum) return ElfCheckError.InvalidNumber;

    var failed = false;
    failed = (try expectEqual(stderr, "Magic", @as(u64, 0x464c457f), try readU32Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "Class", expected_class, try readU8(bytes, 4))) or failed;
    failed = (try expectEqual(stderr, "Data", @as(u8, 1), try readU8(bytes, 5))) or failed;
    failed = (try expectEqual(stderr, "Type", expected_type, try readU16Le(bytes, 16))) or failed;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, 18))) or failed;

    if (expected_class == 2) {
        failed = (try expectEqual(stderr, "Entry", expected_entry, try readU64Le(bytes, 24))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderOffset", expected_phoff, try readU64Le(bytes, 32))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderCount", expected_phnum, try readU16Le(bytes, 56))) or failed;
        failed = (try checkProgramHeaders64(stderr, bytes, try toUsize(expected_phoff), args[8..])) or failed;
    } else if (expected_class == 1) {
        failed = (try expectEqual(stderr, "Entry", expected_entry, try readU32Le(bytes, 24))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderOffset", expected_phoff, try readU32Le(bytes, 28))) or failed;
        failed = (try expectEqual(stderr, "ProgramHeaderCount", expected_phnum, try readU16Le(bytes, 44))) or failed;
        failed = (try checkProgramHeaders32(stderr, bytes, try toUsize(expected_phoff), args[8..])) or failed;
    } else {
        try stderr.print("unsupported ELF class: {d}\n", .{expected_class});
        failed = true;
    }

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn checkProgramHeaders64(stderr: *Io.Writer, bytes: []const u8, phoff: usize, args: []const []const u8) !bool {
    var failed = false;
    var segment_index: usize = 0;
    while (segment_index < args.len / 8) : (segment_index += 1) {
        const expected = try parseExpectedProgramHeader(args[segment_index * 8 ..][0..8]);
        const entry_offset = try checkedAdd(usize, phoff, try checkedMul(usize, segment_index, 56));
        failed = (try expectProgramField(stderr, segment_index, "Type", expected.segment_type, try readU32Le(bytes, entry_offset))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Flags", expected.flags, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 4)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Offset", expected.offset, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 8)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Vaddr", expected.vaddr, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 16)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Paddr", expected.paddr, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 24)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Filesz", expected.filesz, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 32)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Memsz", expected.memsz, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 40)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Align", expected.alignment, try readU64Le(bytes, try checkedAdd(usize, entry_offset, 48)))) or failed;
    }
    return failed;
}

fn checkProgramHeaders32(stderr: *Io.Writer, bytes: []const u8, phoff: usize, args: []const []const u8) !bool {
    var failed = false;
    var segment_index: usize = 0;
    while (segment_index < args.len / 8) : (segment_index += 1) {
        const expected = try parseExpectedProgramHeader(args[segment_index * 8 ..][0..8]);
        const entry_offset = try checkedAdd(usize, phoff, try checkedMul(usize, segment_index, 32));
        failed = (try expectProgramField(stderr, segment_index, "Type", expected.segment_type, try readU32Le(bytes, entry_offset))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Offset", expected.offset, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 4)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Vaddr", expected.vaddr, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 8)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Paddr", expected.paddr, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 12)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Filesz", expected.filesz, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 16)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Memsz", expected.memsz, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 20)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Flags", expected.flags, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 24)))) or failed;
        failed = (try expectProgramField(stderr, segment_index, "Align", expected.alignment, try readU32Le(bytes, try checkedAdd(usize, entry_offset, 28)))) or failed;
    }
    return failed;
}

fn parseExpectedProgramHeader(args: []const []const u8) !ExpectedProgramHeader {
    if (args.len != 8) return ElfCheckError.InvalidNumber;
    return .{
        .segment_type = try parseNumber(u64, args[0]),
        .flags = try parseNumber(u64, args[1]),
        .offset = try parseNumber(u64, args[2]),
        .vaddr = try parseNumber(u64, args[3]),
        .paddr = try parseNumber(u64, args[4]),
        .filesz = try parseNumber(u64, args[5]),
        .memsz = try parseNumber(u64, args[6]),
        .alignment = try parseNumber(u64, args[7]),
    };
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

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: anytype) !bool {
    const actual_value: @TypeOf(expected) = @intCast(actual);
    if (actual_value == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual_value });
    return true;
}

fn expectProgramField(stderr: *Io.Writer, row: usize, name: []const u8, expected: u64, actual: anytype) !bool {
    const actual_value: u64 = @intCast(actual);
    if (actual_value == expected) return false;
    try stderr.print("program header {d} {s} mismatch: expected {d}, actual {d}\n", .{ row, name, expected, actual_value });
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
