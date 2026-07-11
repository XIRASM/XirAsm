const source = @import("source.zig");

const Allocator = @import("std").mem.Allocator;

pub const FileReadKind = enum {
    text,
    bytes,
};

pub const Error = Allocator.Error || error{
    FileNotAvailable,
};

pub const FileReadRequest = struct {
    path: []const u8,
    parent_path: ?[]const u8,
    span: source.SourceSpan,
    kind: FileReadKind,
};

pub const FileReadResult = struct {
    path: []u8,
    bytes: []u8,

    pub fn deinit(self: *FileReadResult, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const FileResolver = struct {
    context: *anyopaque,
    read: *const fn (context: *anyopaque, allocator: Allocator, request: FileReadRequest) Error!FileReadResult,
    exists: *const fn (context: *anyopaque, allocator: Allocator, request: FileReadRequest) Allocator.Error!bool,
};
