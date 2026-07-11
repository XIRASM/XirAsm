const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const PeWriterCheckError = error{
    InvalidNumber,
    InvalidPe,
};

const DataDirectory = struct {
    rva: u32 = 0,
    size: u32 = 0,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 10) {
        try stderr.print(
            "usage: {s} <pe> <bits> <dll> <sections> <size-headers> <size-image> <entry-rva> <subsystem> <dll-chars> (<name> <vsize> <rva> <raw-size> <raw-ptr> <chars>)* (<dir-index> <rva> <size>)*\n",
            .{args[0]},
        );
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    const bits = try parseNumber(u16, args[2]);
    const expect_dll = try parseNumber(u16, args[3]) != 0;
    const expected_sections = try parseNumber(u16, args[4]);
    const expected_size_of_headers = try parseNumber(u32, args[5]);
    const expected_size_of_image = try parseNumber(u32, args[6]);
    const expected_entry_rva = try parseNumber(u32, args[7]);
    const expected_subsystem = try parseNumber(u16, args[8]);
    const expected_dll_chars = try parseNumber(u16, args[9]);

    const section_args_start: usize = 10;
    const section_args_size = try checkedMul(usize, expected_sections, 6);
    const section_args_end = try checkedAdd(usize, section_args_start, section_args_size);
    if (args.len < section_args_end or (args.len - section_args_end) % 3 != 0) return PeWriterCheckError.InvalidNumber;

    var expected_directories: [16]DataDirectory = @splat(.{});
    var directory_arg = section_args_end;
    while (directory_arg < args.len) : (directory_arg += 3) {
        const directory_index = try parseNumber(usize, args[directory_arg]);
        if (directory_index >= expected_directories.len) return PeWriterCheckError.InvalidNumber;
        expected_directories[directory_index] = .{
            .rva = try parseNumber(u32, args[directory_arg + 1]),
            .size = try parseNumber(u32, args[directory_arg + 2]),
        };
    }

    var failed = false;

    const pe_offset = try readU32Le(bytes, 0x3c);
    const pe = try toUsize(pe_offset);
    const expected_machine: u16 = if (bits == 64) 0x8664 else if (bits == 32) 0x014c else return PeWriterCheckError.InvalidPe;
    const expected_opt_magic: u16 = if (bits == 64) 0x020b else 0x010b;
    const expected_optional_size: u16 = if (bits == 64) 0xf0 else 0xe0;

    failed = (try expectEqual(stderr, "MzMagic", @as(u16, 0x5a4d), try readU16Le(bytes, 0))) or failed;
    failed = (try expectEqual(stderr, "PeSignature", @as(u32, 0x00004550), try readU32Le(bytes, pe))) or failed;
    failed = (try expectEqual(stderr, "Machine", expected_machine, try readU16Le(bytes, try checkedAdd(usize, pe, 4)))) or failed;
    failed = (try expectEqual(stderr, "NumberOfSections", expected_sections, try readU16Le(bytes, try checkedAdd(usize, pe, 6)))) or failed;
    failed = (try expectEqual(stderr, "SizeOfOptionalHeader", expected_optional_size, try readU16Le(bytes, try checkedAdd(usize, pe, 20)))) or failed;

    const characteristics = try readU16Le(bytes, try checkedAdd(usize, pe, 22));
    failed = (try expectFlags(stderr, "Characteristics.Executable", characteristics, 0x0002)) or failed;
    if (bits == 32) {
        failed = (try expectFlags(stderr, "Characteristics.32Bit", characteristics, 0x0100)) or failed;
    }
    if (expect_dll) {
        failed = (try expectFlags(stderr, "Characteristics.Dll", characteristics, 0x2000)) or failed;
    } else if ((characteristics & 0x2000) != 0) {
        try stderr.print("Characteristics.Dll mismatch: expected unset, actual set\n", .{});
        failed = true;
    }

    const optional = try checkedAdd(usize, pe, 24);
    failed = (try expectEqual(stderr, "OptionalMagic", expected_opt_magic, try readU16Le(bytes, optional))) or failed;
    failed = (try expectEqual(stderr, "AddressOfEntryPoint", expected_entry_rva, try readU32Le(bytes, try checkedAdd(usize, optional, 16)))) or failed;
    failed = (try expectEqual(stderr, "SectionAlignment", @as(u32, 0x1000), try readU32Le(bytes, try checkedAdd(usize, optional, 32)))) or failed;
    failed = (try expectEqual(stderr, "FileAlignment", @as(u32, 0x200), try readU32Le(bytes, try checkedAdd(usize, optional, 36)))) or failed;
    failed = (try expectEqual(stderr, "SizeOfImage", expected_size_of_image, try readU32Le(bytes, try checkedAdd(usize, optional, 56)))) or failed;
    failed = (try expectEqual(stderr, "SizeOfHeaders", expected_size_of_headers, try readU32Le(bytes, try checkedAdd(usize, optional, 60)))) or failed;
    failed = (try expectEqual(stderr, "Subsystem", expected_subsystem, try readU16Le(bytes, try checkedAdd(usize, optional, 68)))) or failed;
    failed = (try expectEqual(stderr, "DllCharacteristics", expected_dll_chars, try readU16Le(bytes, try checkedAdd(usize, optional, 70)))) or failed;

    const number_of_rva_and_sizes_offset = try checkedAdd(usize, optional, if (bits == 64) 108 else 92);
    const data_dir_offset = try checkedAdd(usize, optional, if (bits == 64) 112 else 96);
    failed = (try expectEqual(stderr, "NumberOfRvaAndSizes", @as(u32, 16), try readU32Le(bytes, number_of_rva_and_sizes_offset))) or failed;

    var data_dir_index: usize = 0;
    while (data_dir_index < 16) : (data_dir_index += 1) {
        const dir_offset = try checkedAdd(usize, data_dir_offset, try checkedMul(usize, data_dir_index, 8));
        const expected_directory = expected_directories[data_dir_index];
        failed = (try expectEqual(stderr, "DataDirectoryRva", expected_directory.rva, try readU32Le(bytes, dir_offset))) or failed;
        failed = (try expectEqual(stderr, "DataDirectorySize", expected_directory.size, try readU32Le(bytes, try checkedAdd(usize, dir_offset, 4)))) or failed;
    }

    const section_table = try checkedAdd(usize, optional, expected_optional_size);
    var section_index: usize = 0;
    while (section_index < expected_sections) : (section_index += 1) {
        const arg_offset = 10 + section_index * 6;
        const expected_name = args[arg_offset];
        const expected_virtual_size = try parseNumber(u32, args[arg_offset + 1]);
        const expected_virtual_address = try parseNumber(u32, args[arg_offset + 2]);
        const expected_raw_size = try parseNumber(u32, args[arg_offset + 3]);
        const expected_raw_ptr = try parseNumber(u32, args[arg_offset + 4]);
        const expected_chars = try parseNumber(u32, args[arg_offset + 5]);
        const row = try checkedAdd(usize, section_table, try checkedMul(usize, section_index, 40));

        failed = (try expectSectionName(stderr, expected_name, bytes, row)) or failed;
        failed = (try expectEqual(stderr, "Section.VirtualSize", expected_virtual_size, try readU32Le(bytes, try checkedAdd(usize, row, 8)))) or failed;
        failed = (try expectEqual(stderr, "Section.VirtualAddress", expected_virtual_address, try readU32Le(bytes, try checkedAdd(usize, row, 12)))) or failed;
        failed = (try expectEqual(stderr, "Section.SizeOfRawData", expected_raw_size, try readU32Le(bytes, try checkedAdd(usize, row, 16)))) or failed;
        failed = (try expectEqual(stderr, "Section.PointerToRawData", expected_raw_ptr, try readU32Le(bytes, try checkedAdd(usize, row, 20)))) or failed;
        failed = (try expectEqual(stderr, "Section.Characteristics", expected_chars, try readU32Le(bytes, try checkedAdd(usize, row, 36)))) or failed;
    }

    failed = (try validateExportDirectory(stderr, bytes, section_table, expected_sections, expected_directories[0])) or failed;
    failed = (try validateImportDirectory(stderr, bytes, bits, section_table, expected_sections, expected_directories[1])) or failed;

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
        return std.fmt.parseInt(T, text[2..], 16) catch return PeWriterCheckError.InvalidNumber;
    }
    return std.fmt.parseInt(T, text, 10) catch return PeWriterCheckError.InvalidNumber;
}

fn expectEqual(stderr: *Io.Writer, name: []const u8, expected: anytype, actual: @TypeOf(expected)) !bool {
    if (actual == expected) return false;
    try stderr.print("{s} mismatch: expected {d}, actual {d}\n", .{ name, expected, actual });
    return true;
}

fn expectFlags(stderr: *Io.Writer, name: []const u8, actual: u16, mask: u16) !bool {
    if ((actual & mask) == mask) return false;
    try stderr.print("{s} mismatch: missing mask {d}, actual {d}\n", .{ name, mask, actual });
    return true;
}

fn expectSectionName(stderr: *Io.Writer, expected: []const u8, bytes: []const u8, row: usize) !bool {
    if (expected.len > 8) return PeWriterCheckError.InvalidPe;
    const end = try checkedAdd(usize, row, 8);
    if (end > bytes.len) return PeWriterCheckError.InvalidPe;
    var actual_len: usize = 0;
    while (actual_len < 8 and bytes[row + actual_len] != 0) : (actual_len += 1) {}
    if (std.mem.eql(u8, expected, bytes[row .. row + actual_len])) return false;
    try stderr.print("Section.Name mismatch: expected {s}\n", .{expected});
    return true;
}

fn expectNonZero(stderr: *Io.Writer, name: []const u8, actual: u32) !bool {
    if (actual != 0) return false;
    try stderr.print("{s} mismatch: expected non-zero, actual 0\n", .{name});
    return true;
}

fn validateImportDirectory(
    stderr: *Io.Writer,
    bytes: []const u8,
    bits: u16,
    section_table: usize,
    section_count: usize,
    directory: DataDirectory,
) !bool {
    if (directory.rva == 0 and directory.size == 0) return false;
    var failed = false;
    if (directory.size < 40) {
        try stderr.print("ImportDirectory.Size mismatch: expected at least 40, actual {d}\n", .{directory.size});
        return true;
    }

    const descriptor = try rvaToOffset(bytes, section_table, section_count, directory.rva);
    const original_first_thunk = try readU32Le(bytes, descriptor);
    const name_rva = try readU32Le(bytes, try checkedAdd(usize, descriptor, 12));
    const first_thunk = try readU32Le(bytes, try checkedAdd(usize, descriptor, 16));
    failed = (try expectNonZero(stderr, "Import.OriginalFirstThunk", original_first_thunk)) or failed;
    failed = (try expectNonZero(stderr, "Import.NameRva", name_rva)) or failed;
    failed = (try expectNonZero(stderr, "Import.FirstThunk", first_thunk)) or failed;

    const null_descriptor = try checkedAdd(usize, descriptor, 20);
    var field_offset: usize = 0;
    while (field_offset < 20) : (field_offset += 4) {
        failed = (try expectEqual(stderr, "Import.NullDescriptor", @as(u32, 0), try readU32Le(bytes, try checkedAdd(usize, null_descriptor, field_offset)))) or failed;
    }

    const library_name = try rvaToOffset(bytes, section_table, section_count, name_rva);
    failed = (try expectCStringNonEmpty(stderr, "Import.LibraryName", bytes, library_name)) or failed;

    const thunk_offset = try rvaToOffset(bytes, section_table, section_count, first_thunk);
    const hint_name_rva = if (bits == 64) try readU64LeAsU32(bytes, thunk_offset) else try readU32Le(bytes, thunk_offset);
    failed = (try expectNonZero(stderr, "Import.HintNameRva", hint_name_rva)) or failed;
    const hint_name = try rvaToOffset(bytes, section_table, section_count, hint_name_rva);
    failed = (try expectCStringNonEmpty(stderr, "Import.FunctionName", bytes, try checkedAdd(usize, hint_name, 2))) or failed;

    return failed;
}

fn validateExportDirectory(
    stderr: *Io.Writer,
    bytes: []const u8,
    section_table: usize,
    section_count: usize,
    directory: DataDirectory,
) !bool {
    if (directory.rva == 0 and directory.size == 0) return false;
    var failed = false;
    if (directory.size < 40) {
        try stderr.print("ExportDirectory.Size mismatch: expected at least 40, actual {d}\n", .{directory.size});
        return true;
    }

    const export_dir = try rvaToOffset(bytes, section_table, section_count, directory.rva);
    const name_rva = try readU32Le(bytes, try checkedAdd(usize, export_dir, 12));
    const ordinal_base = try readU32Le(bytes, try checkedAdd(usize, export_dir, 16));
    const functions = try readU32Le(bytes, try checkedAdd(usize, export_dir, 20));
    const names = try readU32Le(bytes, try checkedAdd(usize, export_dir, 24));
    const address_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_dir, 28));
    const name_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_dir, 32));
    const ordinal_table_rva = try readU32Le(bytes, try checkedAdd(usize, export_dir, 36));

    failed = (try expectNonZero(stderr, "Export.NameRva", name_rva)) or failed;
    failed = (try expectEqual(stderr, "Export.OrdinalBase", @as(u32, 1), ordinal_base)) or failed;
    failed = (try expectNonZero(stderr, "Export.NumberOfFunctions", functions)) or failed;
    failed = (try expectNonZero(stderr, "Export.NumberOfNames", names)) or failed;
    failed = (try expectNonZero(stderr, "Export.AddressTable", address_table_rva)) or failed;
    failed = (try expectNonZero(stderr, "Export.NameTable", name_table_rva)) or failed;
    failed = (try expectNonZero(stderr, "Export.OrdinalTable", ordinal_table_rva)) or failed;
    if (names > functions) {
        try stderr.print("Export.NumberOfNames mismatch: names {d}, functions {d}\n", .{ names, functions });
        failed = true;
    }

    failed = (try expectCStringNonEmpty(stderr, "Export.DllName", bytes, try rvaToOffset(bytes, section_table, section_count, name_rva))) or failed;
    const address_table = try rvaToOffset(bytes, section_table, section_count, address_table_rva);
    failed = (try expectNonZero(stderr, "Export.FirstFunctionRva", try readU32Le(bytes, address_table))) or failed;
    const name_table = try rvaToOffset(bytes, section_table, section_count, name_table_rva);
    const first_name_rva = try readU32Le(bytes, name_table);
    failed = (try expectNonZero(stderr, "Export.FirstNameRva", first_name_rva)) or failed;
    failed = (try expectCStringNonEmpty(stderr, "Export.FirstName", bytes, try rvaToOffset(bytes, section_table, section_count, first_name_rva))) or failed;

    return failed;
}

fn expectCStringNonEmpty(stderr: *Io.Writer, name: []const u8, bytes: []const u8, offset: usize) !bool {
    if (offset >= bytes.len) return PeWriterCheckError.InvalidPe;
    if (bytes[offset] != 0) return false;
    try stderr.print("{s} mismatch: expected non-empty string\n", .{name});
    return true;
}

fn rvaToOffset(bytes: []const u8, section_table: usize, section_count: usize, rva: u32) !usize {
    var section_index: usize = 0;
    while (section_index < section_count) : (section_index += 1) {
        const row = try checkedAdd(usize, section_table, try checkedMul(usize, section_index, 40));
        const virtual_size = try readU32Le(bytes, try checkedAdd(usize, row, 8));
        const virtual_address = try readU32Le(bytes, try checkedAdd(usize, row, 12));
        const raw_size = try readU32Le(bytes, try checkedAdd(usize, row, 16));
        const raw_pointer = try readU32Le(bytes, try checkedAdd(usize, row, 20));
        const extent = if (virtual_size > raw_size) virtual_size else raw_size;
        if (rva >= virtual_address and rva < virtual_address + extent) {
            const delta = rva - virtual_address;
            if (delta >= raw_size) return PeWriterCheckError.InvalidPe;
            return checkedAdd(usize, try toUsize(raw_pointer), try toUsize(delta));
        }
    }
    return PeWriterCheckError.InvalidPe;
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(usize, offset, 2);
    if (end > bytes.len) return PeWriterCheckError.InvalidPe;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 4);
    if (end > bytes.len) return PeWriterCheckError.InvalidPe;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn readU64LeAsU32(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(usize, offset, 8);
    if (end > bytes.len) return PeWriterCheckError.InvalidPe;
    const low = try readU32Le(bytes, offset);
    const high = try readU32Le(bytes, try checkedAdd(usize, offset, 4));
    if (high != 0) return PeWriterCheckError.InvalidPe;
    return low;
}

fn checkedAdd(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.add(T, lhs, rhs) catch return PeWriterCheckError.InvalidPe;
}

fn checkedMul(comptime T: type, lhs: T, rhs: T) !T {
    return std.math.mul(T, lhs, rhs) catch return PeWriterCheckError.InvalidPe;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse PeWriterCheckError.InvalidPe;
}
