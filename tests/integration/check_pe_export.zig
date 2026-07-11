const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const PeExportCheckError = error{
    InvalidNumber,
    InvalidPe,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 9 or ((args.len - 7) % 2) != 0) {
        try stderr.print(
            "usage: {s} <dll> <bits> <export-rva> <export-size> <ordinal-base> <dll-name> (<export-name> <function-rva>)+\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const bits = try parseNumber(u16, args[2]);
    const expected_export_rva = try parseNumber(u32, args[3]);
    const expected_export_size = try parseNumber(u32, args[4]);
    const expected_ordinal_base = try parseNumber(u32, args[5]);
    const expected_dll_name = args[6];
    const expected_export_count = try toU32((args.len - 7) / 2);

    var failed = false;

    const pe_offset = try readU32Le(bytes, 0x3c);
    const pe = try toUsize(pe_offset);
    failed = (try expectEqual(stderr, "MzMagic", @as(u16, 0x5a4d), try readU16Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "PeSignature", @as(u32, 0x00004550), try readU32Le(bytes, pe))) or failed;

    const expected_machine: u16 = if (bits == 64) 0x8664 else if (bits == 32) 0x014c else return PeExportCheckError.InvalidPe;
    const expected_opt_magic: u16 = if (bits == 64) 0x020b else 0x010b;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, try checkedAdd(usize, pe, 4)))) or failed;

    const section_count = try readU16Le(bytes, try checkedAdd(usize, pe, 6));
    const optional_size = try readU16Le(bytes, try checkedAdd(usize, pe, 20));
    const optional_offset = try checkedAdd(usize, pe, 24);
    failed = (try expectEqual(stderr, "OptionalMagic", expected_opt_magic, try readU16Le(bytes, optional_offset))) or failed;

    const data_dir_offset = try checkedAdd(usize, optional_offset, if (bits == 64) 112 else 96);
    failed = (try expectEqual(stderr, "ExportDataDirectoryRva", expected_export_rva, try readU32Le(bytes, data_dir_offset))) or failed;
    failed = (try expectEqual(stderr, "ExportDataDirectorySize", expected_export_size, try readU32Le(bytes, try checkedAdd(usize, data_dir_offset, 4)))) or failed;

    const section_table = try checkedAdd(usize, optional_offset, optional_size);
    const export_foa = try rvaToFoa(bytes, section_table, section_count, expected_export_rva);

    const dll_name_rva = try readU32Le(bytes, try checkedAdd(usize, export_foa, 12));
    const ordinal_base = try readU32Le(bytes, try checkedAdd(usize, export_foa, 16));
    const function_count = try readU32Le(bytes, try checkedAdd(usize, export_foa, 20));
    const name_count = try readU32Le(bytes, try checkedAdd(usize, export_foa, 24));
    const address_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_foa, 28));
    const name_pointer_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_foa, 32));
    const ordinal_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_foa, 36));

    failed = (try expectEqual(stderr, "OrdinalBase", expected_ordinal_base, ordinal_base)) or failed;
    failed = (try expectEqual(stderr, "FunctionCount", expected_export_count, function_count)) or failed;
    failed = (try expectEqual(stderr, "NameCount", expected_export_count, name_count)) or failed;
    failed = (try expectNullTerminatedString(stderr, "DllName", expected_dll_name, bytes, try rvaToFoa(bytes, section_table, section_count, dll_name_rva))) or failed;

    const address_table = try rvaToFoa(bytes, section_table, section_count, address_table_rva);
    const name_pointer_table = try rvaToFoa(bytes, section_table, section_count, name_pointer_table_rva);
    const ordinal_table = try rvaToFoa(bytes, section_table, section_count, ordinal_table_rva);

    var arg_index: usize = 7;
    var export_index: u32 = 0;
    while (arg_index < args.len) : (arg_index += 2) {
        const expected_name = args[arg_index];
        const expected_function_rva = try parseNumber(u32, args[arg_index + 1]);
        const entry_offset = try checkedMul(usize, try toUsize(export_index), 4);
        const ordinal_offset = try checkedMul(usize, try toUsize(export_index), 2);
        const name_rva = try readU32Le(bytes, try checkedAdd(usize, name_pointer_table, entry_offset));
        const ordinal = try readU16Le(bytes, try checkedAdd(usize, ordinal_table, ordinal_offset));
        const function_rva = try readU32Le(bytes, try checkedAdd(usize, address_table, try checkedMul(usize, @as(usize, ordinal), 4)));

        failed = (try expectNullTerminatedString(stderr, "ExportName", expected_name, bytes, try rvaToFoa(bytes, section_table, section_count, name_rva))) or failed;
        failed = (try expectEqual(stderr, "ExportOrdinal", try toU16(export_index), ordinal)) or failed;
        failed = (try expectEqual(stderr, "ExportFunctionRva", expected_function_rva, function_rva)) or failed;
        export_index += 1;
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
        return std.fmt.parseInt(T, text[2..], 16) catch return PeExportCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return PeExportCheckError.InvalidNumber;
}

fn rvaToFoa(bytes: []const u8, section_table: usize, section_count: u16, rva: u32) !usize {
    const section_total = try toUsize(section_count);
    var index: usize = 0;
    while (index < section_total) : (index += 1) {
        const row = try checkedAdd(usize, section_table, try checkedMul(usize, index, 40));
        const virtual_size = try readU32Le(bytes, try checkedAdd(usize, row, 8));
        const virtual_address = try readU32Le(bytes, try checkedAdd(usize, row, 12));
        const raw_size = try readU32Le(bytes, try checkedAdd(usize, row, 16));
        const raw_pointer = try readU32Le(bytes, try checkedAdd(usize, row, 20));
        const mapped_size = @max(virtual_size, raw_size);
        if (rva >= virtual_address and rva - virtual_address < mapped_size) {
            return try checkedAdd(usize, try toUsize(raw_pointer), try toUsize(rva - virtual_address));
        }
    }
    return PeExportCheckError.InvalidPe;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn expectNullTerminatedString(stderr: *Io.Writer, name: []const u8, expected: []const u8, bytes: []const u8, offset: usize) !bool {
    const end = std.mem.indexOfScalarPos(u8, bytes, offset, 0) orelse return PeExportCheckError.InvalidPe;
    if (std.mem.eql(u8, expected, bytes[offset..end])) return false;
    try stderr.print("{s} mismatch\n", .{name});
    return true;
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return PeExportCheckError.InvalidPe;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return PeExportCheckError.InvalidPe;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return PeExportCheckError.InvalidPe;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return PeExportCheckError.InvalidPe;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse PeExportCheckError.InvalidPe;
}

fn toU32(value: anytype) !u32 {
    return std.math.cast(u32, value) orelse PeExportCheckError.InvalidPe;
}

fn toU16(value: anytype) !u16 {
    return std.math.cast(u16, value) orelse PeExportCheckError.InvalidPe;
}
