const std = @import("std");

const fragment = @import("../fragment.zig");

pub const Error = error{
    InvalidApiArgument,
    InvalidApiInteger,
    OffsetOverflow,
};

/// Final output byte image exposed to fixup patching and deferred finalizers.
///
/// `origin` is the logical address basis. `file_offset` in each region is the
/// final physical file offset chosen by the active writer.
pub const Image = struct {
    section: fragment.SectionId,
    origin: u64,
    regions: []const ImageRegion = &.{},
    bytes: []u8,

    pub fn loadBytes(self: Image, absolute_address: u64, out: []u8) Error!void {
        const start = try offsetForRange(self, absolute_address, out.len);
        const end = std.math.add(usize, start, out.len) catch return error.OffsetOverflow;
        @memcpy(out, self.bytes[start..end]);
    }

    pub fn loadBytesInSection(self: Image, section: fragment.SectionId, absolute_address: u64, out: []u8) Error!void {
        const start = try offsetForSectionRange(self, section, absolute_address, out.len);
        const end = std.math.add(usize, start, out.len) catch return error.OffsetOverflow;
        @memcpy(out, self.bytes[start..end]);
    }

    pub fn storeBytes(self: Image, absolute_address: u64, bytes: []const u8) Error!void {
        const start = try offsetForRange(self, absolute_address, bytes.len);
        const end = std.math.add(usize, start, bytes.len) catch return error.OffsetOverflow;
        @memcpy(self.bytes[start..end], bytes);
    }

    pub fn storeBytesInSection(self: Image, section: fragment.SectionId, absolute_address: u64, bytes: []const u8) Error!void {
        const start = try offsetForSectionRange(self, section, absolute_address, bytes.len);
        const end = std.math.add(usize, start, bytes.len) catch return error.OffsetOverflow;
        @memcpy(self.bytes[start..end], bytes);
    }

    pub fn loadInteger(self: Image, absolute_address: u64, byte_count: u8) Error!u64 {
        if (!validScalarByteCount(byte_count)) return error.InvalidApiInteger;
        var bytes: [8]u8 = @splat(0);
        try self.loadBytes(absolute_address, bytes[0..byte_count]);
        return std.mem.readInt(u64, &bytes, .little);
    }

    pub fn loadIntegerInSection(self: Image, section: fragment.SectionId, absolute_address: u64, byte_count: u8) Error!u64 {
        if (!validScalarByteCount(byte_count)) return error.InvalidApiInteger;
        var bytes: [8]u8 = @splat(0);
        try self.loadBytesInSection(section, absolute_address, bytes[0..byte_count]);
        return std.mem.readInt(u64, &bytes, .little);
    }

    pub fn storeInteger(self: Image, absolute_address: u64, integer_value: u64, byte_count: u8) Error!void {
        if (!validScalarByteCount(byte_count)) return error.InvalidApiInteger;
        if (!integerFitsByteCount(integer_value, byte_count)) return error.InvalidApiInteger;
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, integer_value, .little);
        try self.storeBytes(absolute_address, bytes[0..byte_count]);
    }

    pub fn storeIntegerInSection(
        self: Image,
        section: fragment.SectionId,
        absolute_address: u64,
        integer_value: u64,
        byte_count: u8,
    ) Error!void {
        if (!validScalarByteCount(byte_count)) return error.InvalidApiInteger;
        if (!integerFitsByteCount(integer_value, byte_count)) return error.InvalidApiInteger;
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, integer_value, .little);
        try self.storeBytesInSection(section, absolute_address, bytes[0..byte_count]);
    }
};

pub const ImageRegion = struct {
    section: fragment.SectionId,
    origin: u64,
    file_offset: u64,
    logical_size: u64,
    file_size: u64,
};

pub const RegionFacts = struct {
    file_offset: u64,
    logical_size: u64,
    file_size: u64,
};

pub fn regionFactsForAddress(image: Image, absolute_address: u64) Error!RegionFacts {
    var best_origin: ?u64 = null;
    var best_facts: RegionFacts = undefined;
    for (image.regions) |region| {
        if (absolute_address < region.origin) continue;
        const relative = absolute_address - region.origin;
        if (relative >= region.logical_size) continue;
        if (best_origin) |origin| {
            if (region.origin < origin) continue;
        }
        best_origin = region.origin;
        best_facts = .{
            .file_offset = region.file_offset,
            .logical_size = region.logical_size,
            .file_size = region.file_size,
        };
    }
    if (best_origin != null) return best_facts;
    return error.InvalidApiArgument;
}

pub fn regionFactsForSection(image: Image, section: fragment.SectionId, absolute_address: u64) Error!RegionFacts {
    for (image.regions) |region| {
        if (region.section.index != section.index) continue;
        if (absolute_address < region.origin) return error.InvalidApiArgument;
        const relative = absolute_address - region.origin;
        if (relative >= region.logical_size) return error.InvalidApiArgument;
        return .{
            .file_offset = region.file_offset,
            .logical_size = region.logical_size,
            .file_size = region.file_size,
        };
    }
    return error.InvalidApiArgument;
}

pub fn offsetForRange(image: Image, absolute_address: u64, byte_count: usize) Error!usize {
    if (image.regions.len != 0) {
        for (image.regions) |region| {
            const offset = regionOffsetForRange(region, absolute_address, byte_count) catch |err| switch (err) {
                error.InvalidApiArgument => continue,
                error.OffsetOverflow => return error.OffsetOverflow,
                error.InvalidApiInteger => return error.InvalidApiInteger,
            };
            const end = std.math.add(usize, offset, byte_count) catch return error.OffsetOverflow;
            if (end > image.bytes.len) return error.InvalidApiArgument;
            return offset;
        }
        return error.InvalidApiArgument;
    }

    if (absolute_address < image.origin) return error.InvalidApiArgument;
    const offset = absolute_address - image.origin;
    if (offset > std.math.maxInt(usize)) return error.InvalidApiArgument;
    const start: usize = @intCast(offset);
    const end = std.math.add(usize, start, byte_count) catch return error.OffsetOverflow;
    if (end > image.bytes.len) return error.InvalidApiArgument;
    return start;
}

pub fn offsetForSectionRange(
    image: Image,
    section: fragment.SectionId,
    absolute_address: u64,
    byte_count: usize,
) Error!usize {
    for (image.regions) |region| {
        if (region.section.index != section.index) continue;
        const offset = try regionOffsetForRange(region, absolute_address, byte_count);
        const end = std.math.add(usize, offset, byte_count) catch return error.OffsetOverflow;
        if (end > image.bytes.len) return error.InvalidApiArgument;
        return offset;
    }
    return error.InvalidApiArgument;
}

fn regionOffsetForRange(region: ImageRegion, absolute_address: u64, byte_count: usize) Error!usize {
    if (absolute_address < region.origin) return error.InvalidApiArgument;
    const region_relative = absolute_address - region.origin;
    if (region_relative > region.file_size) return error.InvalidApiArgument;
    const region_end = std.math.add(u64, region_relative, byte_count) catch return error.OffsetOverflow;
    if (region_end > region.file_size) return error.InvalidApiArgument;
    const output_offset = std.math.add(u64, region.file_offset, region_relative) catch return error.OffsetOverflow;
    if (output_offset > std.math.maxInt(usize)) return error.InvalidApiArgument;
    const start: usize = @intCast(output_offset);
    return start;
}

fn validScalarByteCount(byte_count: u8) bool {
    return byte_count == 1 or byte_count == 2 or byte_count == 4 or byte_count == 8;
}

fn integerFitsByteCount(integer_value: u64, byte_count: u8) bool {
    return switch (byte_count) {
        1 => integer_value <= std.math.maxInt(u8),
        2 => integer_value <= std.math.maxInt(u16),
        4 => integer_value <= std.math.maxInt(u32),
        8 => true,
        else => false,
    };
}

test "output image maps addresses through logical regions" {
    var bytes = [_]u8{ 0xaa, 0xbb, 0xcc, 0xdd, 0, 0, 0x11, 0x22 };
    const output_image: Image = .{
        .section = .{ .index = 0 },
        .origin = 0x1000,
        .regions = &.{
            .{ .section = .{ .index = 0 }, .origin = 0x1000, .file_offset = 0, .logical_size = 4, .file_size = 4 },
            .{ .section = .{ .index = 1 }, .origin = 0x2000, .file_offset = 6, .logical_size = 2, .file_size = 2 },
        },
        .bytes = &bytes,
    };

    try std.testing.expectEqual(@as(u64, 0xbbaa), try output_image.loadInteger(0x1000, 2));
    try std.testing.expectEqual(@as(u64, 0x2211), try output_image.loadInteger(0x2000, 2));
    try output_image.storeInteger(0x2001, 0x33, 1);
    try std.testing.expectEqual(@as(u8, 0x33), bytes[7]);
}

test "region facts prefer the most specific overlapping logical region" {
    var bytes = [_]u8{ 0xaa, 0xbb, 0xcc, 0xdd, 0x11, 0x22, 0x33, 0x44 };
    const output_image: Image = .{
        .section = .{ .index = 0 },
        .origin = 0,
        .regions = &.{
            .{ .section = .{ .index = 0 }, .origin = 0, .file_offset = 0, .logical_size = 0x1000, .file_size = 4 },
            .{ .section = .{ .index = 1 }, .origin = 0x100, .file_offset = 4, .logical_size = 4, .file_size = 4 },
        },
        .bytes = &bytes,
    };

    const facts = try regionFactsForAddress(output_image, 0x100);
    try std.testing.expectEqual(@as(u64, 4), facts.file_offset);
    try std.testing.expectEqual(@as(u64, 4), facts.logical_size);
    try std.testing.expectEqual(@as(u64, 4), facts.file_size);
}

test "output image section access selects the identified overlapping region" {
    var bytes = [_]u8{ 0x11, 0x22, 0x33, 0x44, 0x55, 0x66 };
    const output_image: Image = .{
        .section = .{ .index = 0 },
        .origin = 0x1000,
        .regions = &.{
            .{ .section = .{ .index = 0 }, .origin = 0x1000, .file_offset = 0, .logical_size = 4, .file_size = 4 },
            .{ .section = .{ .index = 1 }, .origin = 0x1002, .file_offset = 4, .logical_size = 2, .file_size = 2 },
        },
        .bytes = &bytes,
    };

    try std.testing.expectEqual(@as(u64, 0x6655), try output_image.loadIntegerInSection(.{ .index = 1 }, 0x1002, 2));
    try output_image.storeIntegerInSection(.{ .index = 1 }, 0x1002, 0x8877, 2);
    try std.testing.expectEqualSlices(u8, &.{ 0x11, 0x22, 0x33, 0x44, 0x77, 0x88 }, &bytes);
}

test "output image section access rejects a trimmed identified region" {
    var bytes = [_]u8{ 0x11, 0x22, 0x33, 0x44 };
    const output_image: Image = .{
        .section = .{ .index = 0 },
        .origin = 0x1000,
        .regions = &.{
            .{ .section = .{ .index = 0 }, .origin = 0x1000, .file_offset = 0, .logical_size = 4, .file_size = 4 },
            .{ .section = .{ .index = 1 }, .origin = 0x1002, .file_offset = 4, .logical_size = 2, .file_size = 0 },
        },
        .bytes = &bytes,
    };

    try std.testing.expectError(error.InvalidApiArgument, output_image.loadIntegerInSection(.{ .index = 1 }, 0x1002, 1));
    try std.testing.expectError(error.InvalidApiArgument, output_image.storeIntegerInSection(.{ .index = 1 }, 0x1002, 0xaa, 1));
}
