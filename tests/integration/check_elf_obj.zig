const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const ElfObjCheckError = error{
    InvalidNumber,
    InvalidElfObject,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 11 and args.len != 14) {
        try stderr.print(
            "usage: {s} <obj> <class> <machine> <shoff> <shnum> <shstrndx> <rel-section-index> <rel-section-type> <rel-offset> <rel-info> [<bss-section-index> <bss-size> <require-gnu-stack-note>]\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const expected_class = try parseNumber(u8, args[2]);
    const expected_machine = try parseNumber(u16, args[3]);
    const expected_shoff = try parseNumber(u64, args[4]);
    const expected_shnum = try parseNumber(u16, args[5]);
    const expected_shstrndx = try parseNumber(u16, args[6]);
    const rel_section_index = try parseNumber(usize, args[7]);
    const expected_rel_section_type = try parseNumber(u32, args[8]);
    const expected_rel_offset = try parseNumber(u64, args[9]);
    const expected_rel_info = try parseNumber(u64, args[10]);
    const check_ordinary_layout = args.len == 14;
    const bss_section_index = if (check_ordinary_layout) try parseNumber(usize, args[11]) else 0;
    const expected_bss_size = if (check_ordinary_layout) try parseNumber(u64, args[12]) else 0;
    const require_gnu_stack_note = if (check_ordinary_layout) (try parseNumber(u8, args[13])) != 0 else false;

    var failed = false;
    failed = (try expectEqual(stderr, "Magic", @as(u32, 0x464c457f), try readU32Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "Class", expected_class, try readU8(bytes, 4))) or failed;
    failed = (try expectEqual(stderr, "Data", @as(u8, 1), try readU8(bytes, 5))) or failed;
    failed = (try expectEqual(stderr, "Type", @as(u16, 1), try readU16Le(bytes, 16))) or failed;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, 18))) or failed;

    if (expected_class == 2) {
        failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU64Le(bytes, 40))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderCount", expected_shnum, try readU16Le(bytes, 60))) or failed;
        failed = (try expectEqual(stderr, "SectionNameStringIndex", expected_shstrndx, try readU16Le(bytes, 62))) or failed;
        const shoff = try toUsize(expected_shoff);
        const section_offset = try checkedAdd(usize, shoff, try checkedMul(usize, rel_section_index, 64));
        failed = (try expectEqual(stderr, "RelSectionType", expected_rel_section_type, try readU32Le(bytes, try checkedAdd(usize, section_offset, 4)))) or failed;
        const rel_table_offset = try readU64Le(bytes, try checkedAdd(usize, section_offset, 24));
        failed = (try expectEqual(stderr, "RelocOffset", expected_rel_offset, try readU64Le(bytes, try toUsize(rel_table_offset)))) or failed;
        failed = (try expectEqual(stderr, "RelocInfo", expected_rel_info, try readU64Le(bytes, try checkedAdd(usize, try toUsize(rel_table_offset), 8)))) or failed;
        if (check_ordinary_layout) {
            failed = (try checkBss64(stderr, bytes, expected_shoff, bss_section_index, expected_bss_size)) or failed;
        }
        if (require_gnu_stack_note) {
            failed = (try checkGnuStack64(stderr, bytes, expected_shoff, expected_shnum, expected_shstrndx)) or failed;
        }
    } else if (expected_class == 1) {
        failed = (try expectEqual(stderr, "SectionHeaderOffset", expected_shoff, try readU32Le(bytes, 32))) or failed;
        failed = (try expectEqual(stderr, "SectionHeaderCount", expected_shnum, try readU16Le(bytes, 48))) or failed;
        failed = (try expectEqual(stderr, "SectionNameStringIndex", expected_shstrndx, try readU16Le(bytes, 50))) or failed;
        const shoff = try toUsize(expected_shoff);
        const section_offset = try checkedAdd(usize, shoff, try checkedMul(usize, rel_section_index, 40));
        failed = (try expectEqual(stderr, "RelSectionType", expected_rel_section_type, try readU32Le(bytes, try checkedAdd(usize, section_offset, 4)))) or failed;
        const rel_table_offset = try readU32Le(bytes, try checkedAdd(usize, section_offset, 16));
        failed = (try expectEqual(stderr, "RelocOffset", expected_rel_offset, try readU32Le(bytes, try toUsize(rel_table_offset)))) or failed;
        failed = (try expectEqual(stderr, "RelocInfo", expected_rel_info, try readU32Le(bytes, try checkedAdd(usize, try toUsize(rel_table_offset), 4)))) or failed;
        if (check_ordinary_layout) {
            failed = (try checkBss32(stderr, bytes, expected_shoff, bss_section_index, expected_bss_size)) or failed;
        }
        if (require_gnu_stack_note) {
            failed = (try checkGnuStack32(stderr, bytes, expected_shoff, expected_shnum, expected_shstrndx)) or failed;
        }
    } else {
        try stderr.print("unsupported ELF class: {d}\n", .{expected_class});
        failed = true;
    }

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn checkBss32(
    stderr: *Io.Writer,
    bytes: []const u8,
    shoff: u64,
    section_index: usize,
    expected_size: u64,
) !bool {
    const section_offset = try checkedAdd(usize, try toUsize(shoff), try checkedMul(usize, section_index, 40));
    var failed = false;
    failed = (try expectEqual(stderr, "BssType", @as(u32, 8), try readU32Le(bytes, try checkedAdd(usize, section_offset, 4)))) or failed;
    failed = (try expectEqual(stderr, "BssFlags", @as(u32, 3), try readU32Le(bytes, try checkedAdd(usize, section_offset, 8)))) or failed;
    failed = (try expectEqual(stderr, "BssSize", expected_size, @as(u64, try readU32Le(bytes, try checkedAdd(usize, section_offset, 20))))) or failed;
    return failed;
}

fn checkBss64(
    stderr: *Io.Writer,
    bytes: []const u8,
    shoff: u64,
    section_index: usize,
    expected_size: u64,
) !bool {
    const section_offset = try checkedAdd(usize, try toUsize(shoff), try checkedMul(usize, section_index, 64));
    var failed = false;
    failed = (try expectEqual(stderr, "BssType", @as(u32, 8), try readU32Le(bytes, try checkedAdd(usize, section_offset, 4)))) or failed;
    failed = (try expectEqual(stderr, "BssFlags", @as(u64, 3), try readU64Le(bytes, try checkedAdd(usize, section_offset, 8)))) or failed;
    failed = (try expectEqual(stderr, "BssSize", expected_size, try readU64Le(bytes, try checkedAdd(usize, section_offset, 32)))) or failed;
    return failed;
}

fn checkGnuStack32(
    stderr: *Io.Writer,
    bytes: []const u8,
    shoff: u64,
    shnum: u16,
    shstrndx: u16,
) !bool {
    if (shnum == 0 or shstrndx >= shnum) return ElfObjCheckError.InvalidElfObject;
    const section_table = try toUsize(shoff);
    const shstr_header = try checkedAdd(usize, section_table, try checkedMul(usize, shstrndx, 40));
    const shstr_offset = try readU32Le(bytes, try checkedAdd(usize, shstr_header, 16));
    const shstr_size = try readU32Le(bytes, try checkedAdd(usize, shstr_header, 20));
    const note_index = try toUsize(shnum - 1);
    const note_header = try checkedAdd(usize, section_table, try checkedMul(usize, note_index, 40));
    const name_offset = try readU32Le(bytes, note_header);

    var failed = false;
    failed = (try expectEqual(stderr, "GnuStackType", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, note_header, 4)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackFlags", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, note_header, 8)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackSize", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, note_header, 20)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackAlign", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, note_header, 32)))) or failed;
    failed = (try expectStringInTable(stderr, bytes, shstr_offset, shstr_size, name_offset, ".note.GNU-stack\x00")) or failed;
    return failed;
}

fn checkGnuStack64(
    stderr: *Io.Writer,
    bytes: []const u8,
    shoff: u64,
    shnum: u16,
    shstrndx: u16,
) !bool {
    if (shnum == 0 or shstrndx >= shnum) return ElfObjCheckError.InvalidElfObject;
    const section_table = try toUsize(shoff);
    const shstr_header = try checkedAdd(usize, section_table, try checkedMul(usize, shstrndx, 64));
    const shstr_offset = try readU64Le(bytes, try checkedAdd(usize, shstr_header, 24));
    const shstr_size = try readU64Le(bytes, try checkedAdd(usize, shstr_header, 32));
    const note_index = try toUsize(shnum - 1);
    const note_header = try checkedAdd(usize, section_table, try checkedMul(usize, note_index, 64));
    const name_offset = try readU32Le(bytes, note_header);

    var failed = false;
    failed = (try expectEqual(stderr, "GnuStackType", @as(u32, 1), try readU32Le(bytes, try checkedAdd(usize, note_header, 4)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackFlags", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, note_header, 8)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackSize", @as(u64, 0), try readU64Le(bytes, try checkedAdd(usize, note_header, 32)))) or failed;
    failed = (try expectEqual(stderr, "GnuStackAlign", @as(u64, 1), try readU64Le(bytes, try checkedAdd(usize, note_header, 48)))) or failed;
    failed = (try expectStringInTable(stderr, bytes, shstr_offset, shstr_size, name_offset, ".note.GNU-stack\x00")) or failed;
    return failed;
}

fn expectStringInTable(
    stderr: *Io.Writer,
    bytes: []const u8,
    table_offset: anytype,
    table_size: anytype,
    string_offset: u32,
    expected: []const u8,
) !bool {
    const table_start = try toUsize(table_offset);
    const table_end = try checkedAdd(usize, table_start, try toUsize(table_size));
    const start = try checkedAdd(usize, table_start, try toUsize(string_offset));
    const end = try checkedAdd(usize, start, expected.len);
    if (table_end > bytes.len or end > table_end) return ElfObjCheckError.InvalidElfObject;
    if (std.mem.eql(u8, expected, bytes[start..end])) return false;
    try stderr.print("GnuStackName mismatch\n", .{});
    return true;
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn parseNumber(comptime T: type, text: []const u8) !T {
    if (std.mem.startsWith(u8, text, "0x") or std.mem.startsWith(u8, text, "0X")) {
        return std.fmt.parseInt(T, text[2..], 16) catch return ElfObjCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return ElfObjCheckError.InvalidNumber;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn readU8(bytes: []const u8, offset: usize) !u8 {
    const end = try checkedAdd(usize, offset, 1);
    if (end > bytes.len) return ElfObjCheckError.InvalidElfObject;
    return bytes[offset];
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return ElfObjCheckError.InvalidElfObject;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return ElfObjCheckError.InvalidElfObject;
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
    return std.math.add(T, lhs, rhs) catch return ElfObjCheckError.InvalidElfObject;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return ElfObjCheckError.InvalidElfObject;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse ElfObjCheckError.InvalidElfObject;
}
