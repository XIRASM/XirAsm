const std = @import("std");

const image = @import("image.zig");

const Allocator = std.mem.Allocator;

pub const ImageRegion = image.ImageRegion;

pub const WriterResult = struct {
    bytes: []u8,
    regions: []ImageRegion = &.{},

    pub fn deinit(self: *WriterResult, allocator: Allocator) void {
        allocator.free(self.regions);
        allocator.free(self.bytes);
        self.* = undefined;
    }
};
