const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const ResourceCheckError = error{
    InvalidPe,
};

const pe_signature = "PE\x00\x00";
const pe32_optional_magic: u16 = 0x10b;
const pe64_optional_magic: u16 = 0x20b;
const resource_directory_index: usize = 2;
const section_header_size: usize = 40;
const resource_subdirectory_flag: u32 = 0x80000000;
const resource_name_flag: u32 = 0x80000000;

const PeImage = struct {
    resource_root_foa: usize,
    resource_rva: u32,
    resource_size: usize,
    section_table_foa: usize,
    section_count: usize,
};

const Directory = struct {
    foa: usize,
    named_count: usize,
    id_count: usize,

    fn count(self: Directory) usize {
        return self.named_count + self.id_count;
    }
};

const Entry = struct {
    name: u32,
    target: u32,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 2) {
        try stderr.print("usage: {s} <pe>\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const bytes = try readFile(allocator, init.io, args[1]);
    try validateResourceTree(bytes);
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
}

fn validateResourceTree(bytes: []const u8) !void {
    const image = try parsePeImage(bytes);
    const root = try readDirectory(bytes, image, 0);
    try expectDirectoryCounts(root, 2, 1);

    const atype_rel = try expectNamedSubdirectory(bytes, image, root, 0, "ATYPE");
    const ztype_rel = try expectNamedSubdirectory(bytes, image, root, 1, "ZTYPE");
    const type10_rel = try expectIdSubdirectory(bytes, root, 2, 10);

    const atype = try readDirectory(bytes, image, atype_rel);
    try expectDirectoryCounts(atype, 0, 1);
    const atype_id7_rel = try expectIdSubdirectory(bytes, atype, 0, 7);
    const atype_id7 = try readDirectory(bytes, image, atype_id7_rel);
    try expectDirectoryCounts(atype_id7, 0, 2);
    try expectIdData(bytes, image, atype_id7, 0, 0x0409, "AB");
    try expectIdData(bytes, image, atype_id7, 1, 0x0411, "CDEFG");

    const ztype = try readDirectory(bytes, image, ztype_rel);
    try expectDirectoryCounts(ztype, 0, 1);
    const ztype_id7_rel = try expectIdSubdirectory(bytes, ztype, 0, 7);
    const ztype_id7 = try readDirectory(bytes, image, ztype_id7_rel);
    try expectDirectoryCounts(ztype_id7, 0, 1);
    try expectIdData(bytes, image, ztype_id7, 0, 0x0409, &.{ 0x10, 0x20, 0x30 });

    const type10 = try readDirectory(bytes, image, type10_rel);
    try expectDirectoryCounts(type10, 1, 1);
    const beta_rel = try expectNamedSubdirectory(bytes, image, type10, 0, "BETA");
    const id2_rel = try expectIdSubdirectory(bytes, type10, 1, 2);

    const beta = try readDirectory(bytes, image, beta_rel);
    try expectDirectoryCounts(beta, 0, 1);
    try expectIdData(bytes, image, beta, 0, 0x0409, &.{ 0xaa, 0xbb, 0xcc, 0xdd });

    const id2 = try readDirectory(bytes, image, id2_rel);
    try expectDirectoryCounts(id2, 0, 1);
    try expectIdData(bytes, image, id2, 0, 0x0409, &.{0xee});
}

fn parsePeImage(bytes: []const u8) !PeImage {
    try expectBytes(bytes, 0, "MZ");
    const pe_offset = try toUsize(try readU32Le(bytes, 0x3c));
    try expectBytes(bytes, pe_offset, pe_signature);

    const section_count = try toUsize(try readU16Le(bytes, try checkedAdd(pe_offset, 6)));
    const optional_size = try toUsize(try readU16Le(bytes, try checkedAdd(pe_offset, 20)));
    const optional_foa = try checkedAdd(pe_offset, 24);
    const optional_end = try checkedAdd(optional_foa, optional_size);
    if (optional_end > bytes.len) return ResourceCheckError.InvalidPe;

    const magic = try readU16Le(bytes, optional_foa);
    const directories_offset: usize = switch (magic) {
        pe32_optional_magic => 96,
        pe64_optional_magic => 112,
        else => return ResourceCheckError.InvalidPe,
    };
    const resource_directory_foa = try checkedAdd(
        optional_foa,
        try checkedAdd(directories_offset, resource_directory_index * 8),
    );
    const resource_rva = try readU32Le(bytes, resource_directory_foa);
    const resource_size = try toUsize(try readU32Le(bytes, try checkedAdd(resource_directory_foa, 4)));
    if (resource_rva == 0 or resource_size == 0) return ResourceCheckError.InvalidPe;

    const section_table_foa = optional_end;
    const root_foa = try rvaToFileOffset(bytes, section_table_foa, section_count, resource_rva);
    const resource_end = try checkedAdd(root_foa, resource_size);
    if (resource_end > bytes.len) return ResourceCheckError.InvalidPe;

    return .{
        .resource_root_foa = root_foa,
        .resource_rva = resource_rva,
        .resource_size = resource_size,
        .section_table_foa = section_table_foa,
        .section_count = section_count,
    };
}

fn rvaToFileOffset(
    bytes: []const u8,
    section_table_foa: usize,
    section_count: usize,
    rva: u32,
) !usize {
    var index: usize = 0;
    while (index < section_count) : (index += 1) {
        const section_offset = try checkedAdd(
            section_table_foa,
            try checkedMul(index, section_header_size),
        );
        const virtual_size = try readU32Le(bytes, try checkedAdd(section_offset, 8));
        const virtual_address = try readU32Le(bytes, try checkedAdd(section_offset, 12));
        const raw_size = try readU32Le(bytes, try checkedAdd(section_offset, 16));
        const raw_pointer = try readU32Le(bytes, try checkedAdd(section_offset, 20));
        const span = if (virtual_size > raw_size) virtual_size else raw_size;

        if (rva >= virtual_address and rva - virtual_address < span) {
            const delta = rva - virtual_address;
            if (delta >= raw_size) return ResourceCheckError.InvalidPe;
            const file_offset = try checkedAdd(
                try toUsize(raw_pointer),
                try toUsize(delta),
            );
            if (file_offset > bytes.len) return ResourceCheckError.InvalidPe;
            return file_offset;
        }
    }
    return ResourceCheckError.InvalidPe;
}

fn readDirectory(bytes: []const u8, image: PeImage, relative_offset: u32) !Directory {
    const foa = try resourceRelativeFoa(image, relative_offset, 16);
    return .{
        .foa = foa,
        .named_count = try toUsize(try readU16Le(bytes, try checkedAdd(foa, 12))),
        .id_count = try toUsize(try readU16Le(bytes, try checkedAdd(foa, 14))),
    };
}

fn readEntry(bytes: []const u8, directory: Directory, index: usize) !Entry {
    if (index >= directory.count()) return ResourceCheckError.InvalidPe;
    const entry_foa = try checkedAdd(
        try checkedAdd(directory.foa, 16),
        try checkedMul(index, 8),
    );
    return .{
        .name = try readU32Le(bytes, entry_foa),
        .target = try readU32Le(bytes, try checkedAdd(entry_foa, 4)),
    };
}

fn expectDirectoryCounts(directory: Directory, named: usize, ids: usize) !void {
    if (directory.named_count != named or directory.id_count != ids) {
        return ResourceCheckError.InvalidPe;
    }
}

fn expectNamedSubdirectory(
    bytes: []const u8,
    image: PeImage,
    directory: Directory,
    index: usize,
    expected_name: []const u8,
) !u32 {
    const entry = try readEntry(bytes, directory, index);
    if ((entry.name & resource_name_flag) == 0 or
        (entry.target & resource_subdirectory_flag) == 0)
    {
        return ResourceCheckError.InvalidPe;
    }
    try expectUtf16Name(bytes, image, entry.name & ~resource_name_flag, expected_name);
    return entry.target & ~resource_subdirectory_flag;
}

fn expectIdSubdirectory(
    bytes: []const u8,
    directory: Directory,
    index: usize,
    expected_id: u32,
) !u32 {
    const entry = try readEntry(bytes, directory, index);
    if ((entry.name & resource_name_flag) != 0 or
        entry.name != expected_id or
        (entry.target & resource_subdirectory_flag) == 0)
    {
        return ResourceCheckError.InvalidPe;
    }
    return entry.target & ~resource_subdirectory_flag;
}

fn expectIdData(
    bytes: []const u8,
    image: PeImage,
    directory: Directory,
    index: usize,
    expected_id: u32,
    expected_payload: []const u8,
) !void {
    const entry = try readEntry(bytes, directory, index);
    if ((entry.name & resource_name_flag) != 0 or
        entry.name != expected_id or
        (entry.target & resource_subdirectory_flag) != 0)
    {
        return ResourceCheckError.InvalidPe;
    }
    try expectDataEntry(bytes, image, entry.target, expected_payload);
}

fn expectUtf16Name(
    bytes: []const u8,
    image: PeImage,
    relative_offset: u32,
    expected_name: []const u8,
) !void {
    const name_foa = try resourceRelativeFoa(image, relative_offset, 2);
    const length = try toUsize(try readU16Le(bytes, name_foa));
    if (length != expected_name.len) return ResourceCheckError.InvalidPe;

    for (expected_name, 0..) |character, index| {
        const character_offset = try checkedAdd(
            try checkedAdd(name_foa, 2),
            try checkedMul(index, 2),
        );
        if (try readU16Le(bytes, character_offset) != @as(u16, character)) {
            return ResourceCheckError.InvalidPe;
        }
    }
}

fn expectDataEntry(
    bytes: []const u8,
    image: PeImage,
    relative_offset: u32,
    expected_payload: []const u8,
) !void {
    const entry_foa = try resourceRelativeFoa(image, relative_offset, 16);
    const data_rva = try readU32Le(bytes, entry_foa);
    const data_size = try toUsize(try readU32Le(bytes, try checkedAdd(entry_foa, 4)));
    const codepage = try readU32Le(bytes, try checkedAdd(entry_foa, 8));
    const reserved = try readU32Le(bytes, try checkedAdd(entry_foa, 12));
    if (data_size != expected_payload.len or codepage != 0 or reserved != 0) {
        return ResourceCheckError.InvalidPe;
    }

    const data_foa = try rvaToFileOffset(
        bytes,
        image.section_table_foa,
        image.section_count,
        data_rva,
    );
    if (data_rva < image.resource_rva) return ResourceCheckError.InvalidPe;
    const data_relative = try toUsize(data_rva - image.resource_rva);
    const data_end = try checkedAdd(data_relative, data_size);
    if (data_end > image.resource_size) return ResourceCheckError.InvalidPe;
    if (data_foa != try checkedAdd(image.resource_root_foa, data_relative)) {
        return ResourceCheckError.InvalidPe;
    }
    if (data_foa % 4 != 0) return ResourceCheckError.InvalidPe;
    try expectBytes(bytes, data_foa, expected_payload);
}

fn resourceRelativeFoa(image: PeImage, relative_offset: u32, size: usize) !usize {
    const relative = try toUsize(relative_offset);
    const end = try checkedAdd(relative, size);
    if (end > image.resource_size) return ResourceCheckError.InvalidPe;
    return checkedAdd(image.resource_root_foa, relative);
}

fn expectBytes(bytes: []const u8, offset: usize, expected: []const u8) !void {
    const end = try checkedAdd(offset, expected.len);
    if (end > bytes.len or !std.mem.eql(u8, bytes[offset..end], expected)) {
        return ResourceCheckError.InvalidPe;
    }
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(offset, 2);
    if (end > bytes.len) return ResourceCheckError.InvalidPe;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(offset, 4);
    if (end > bytes.len) return ResourceCheckError.InvalidPe;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn checkedAdd(lhs: usize, rhs: usize) !usize {
    return std.math.add(usize, lhs, rhs) catch ResourceCheckError.InvalidPe;
}

fn checkedMul(lhs: usize, rhs: usize) !usize {
    return std.math.mul(usize, lhs, rhs) catch ResourceCheckError.InvalidPe;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse ResourceCheckError.InvalidPe;
}
