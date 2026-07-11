const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const PeChecksumCheckError = error{
    InvalidPe,
};

const pe_signature = "PE\x00\x00";
const pe32_optional_magic: u16 = 0x10b;
const pe64_optional_magic: u16 = 0x20b;
const checksum_optional_offset: usize = 0x40;
const checksum_size: usize = 4;

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
    const checksum_offset = try peChecksumOffset(bytes);
    const actual = try readU32Le(bytes, checksum_offset);
    const expected = try calculatePeChecksum(bytes, checksum_offset);

    if (actual != expected) {
        try stderr.print(
            "PE checksum mismatch: expected {d}, actual {d}\n",
            .{ expected, actual },
        );
        try stderr.flush();
        std.process.exit(1);
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return Io.Dir.cwd().readFileAlloc(
        io,
        path,
        allocator,
        .limited(std.math.maxInt(usize)),
    );
}

fn peChecksumOffset(bytes: []const u8) !usize {
    try expectBytes(bytes, 0, "MZ");

    const pe_offset = try toUsize(try readU32Le(bytes, 0x3c));
    try expectBytes(bytes, pe_offset, pe_signature);

    const optional_size_offset = try checkedAdd(pe_offset, 20);
    const optional_size = try toUsize(try readU16Le(bytes, optional_size_offset));
    if (optional_size < checksum_optional_offset + checksum_size) {
        return PeChecksumCheckError.InvalidPe;
    }

    const optional_offset = try checkedAdd(pe_offset, 24);
    const magic = try readU16Le(bytes, optional_offset);
    if (magic != pe32_optional_magic and magic != pe64_optional_magic) {
        return PeChecksumCheckError.InvalidPe;
    }

    const checksum_offset = try checkedAdd(optional_offset, checksum_optional_offset);
    const checksum_end = try checkedAdd(checksum_offset, checksum_size);
    if (checksum_end > bytes.len or checksum_offset % 2 != 0) {
        return PeChecksumCheckError.InvalidPe;
    }
    return checksum_offset;
}

fn calculatePeChecksum(bytes: []const u8, checksum_offset: usize) !u32 {
    const checksum_second_word = try checkedAdd(checksum_offset, 2);
    var checksum: u64 = 0;
    var offset: usize = 0;

    while (true) {
        const end = try checkedAdd(offset, 2);
        if (end > bytes.len) break;

        const word: u16 = if (offset == checksum_offset or offset == checksum_second_word)
            0
        else
            try readU16Le(bytes, offset);
        checksum = reduceChecksum(checksum + word);
        offset = end;
    }

    if (offset < bytes.len) {
        checksum = reduceChecksum(checksum + bytes[offset]);
    }

    const file_size = std.math.cast(u64, bytes.len) orelse return PeChecksumCheckError.InvalidPe;
    checksum = std.math.add(u64, checksum, file_size) catch return PeChecksumCheckError.InvalidPe;
    return std.math.cast(u32, checksum) orelse PeChecksumCheckError.InvalidPe;
}

fn reduceChecksum(value: u64) u64 {
    var checksum = value;
    while ((checksum >> 16) != 0) {
        checksum = (checksum & 0xffff) + (checksum >> 16);
    }
    return checksum;
}

fn expectBytes(bytes: []const u8, offset: usize, expected: []const u8) !void {
    const end = try checkedAdd(offset, expected.len);
    if (end > bytes.len or !std.mem.eql(u8, bytes[offset..end], expected)) {
        return PeChecksumCheckError.InvalidPe;
    }
}

fn readU16Le(bytes: []const u8, offset: usize) !u16 {
    const end = try checkedAdd(offset, 2);
    if (end > bytes.len) return PeChecksumCheckError.InvalidPe;
    return @as(u16, bytes[offset]) |
        (@as(u16, bytes[offset + 1]) << 8);
}

fn readU32Le(bytes: []const u8, offset: usize) !u32 {
    const end = try checkedAdd(offset, 4);
    if (end > bytes.len) return PeChecksumCheckError.InvalidPe;
    return @as(u32, bytes[offset]) |
        (@as(u32, bytes[offset + 1]) << 8) |
        (@as(u32, bytes[offset + 2]) << 16) |
        (@as(u32, bytes[offset + 3]) << 24);
}

fn checkedAdd(lhs: usize, rhs: usize) !usize {
    return std.math.add(usize, lhs, rhs) catch PeChecksumCheckError.InvalidPe;
}

fn toUsize(value: anytype) !usize {
    return std.math.cast(usize, value) orelse PeChecksumCheckError.InvalidPe;
}
