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

pub const FileListRequest = struct {
    path: []const u8,
    parent_path: ?[]const u8,
    span: source.SourceSpan,
};

/// One entry of a directory listing. The name is the entry's own name, not a
/// path, and the listing owns the text. An entry deliberately carries no kind:
/// whether a name can be entered is a question about the path, and answering it
/// from a directory entry is unreliable on filesystems that report no type, so
/// `fs.is_dir` asks the resolver instead.
pub const DirEntry = struct {
    name: []u8,
};

/// Entries of one directory, sorted by name so a listing does not depend on the
/// order the host filesystem happens to return.
pub const DirListing = struct {
    entries: []DirEntry,

    pub fn deinit(self: *DirListing, allocator: Allocator) void {
        for (self.entries) |entry| allocator.free(entry.name);
        allocator.free(self.entries);
        self.* = undefined;
    }
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
    /// Directory support is optional: a host that cannot enumerate directories
    /// leaves these null, and `fs.list_dir` then reports the path as
    /// unavailable while `fs.is_dir` answers false.
    list: ?*const fn (context: *anyopaque, allocator: Allocator, request: FileListRequest) Error!DirListing = null,
    is_dir: ?*const fn (context: *anyopaque, allocator: Allocator, request: FileListRequest) Allocator.Error!bool = null,
};
