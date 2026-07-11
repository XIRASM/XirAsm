const std = @import("std");

const Allocator = std.mem.Allocator;

pub const SourceId = struct {
    index: u32,
};

pub const SourceSpan = struct {
    source: ?SourceId = null,
    start: u32 = 0,
    end: u32 = 0,
};

pub const unknown_span: SourceSpan = .{};

pub const SourceInput = struct {
    path: []const u8,
    bytes: []const u8,
};

pub const SourceFile = struct {
    path: []u8,
    bytes: []u8,

    pub fn deinit(self: *SourceFile, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const SourceLocation = struct {
    path: []const u8,
    line: u32,
    column: u32,
};

pub const SourceMap = struct {
    items: std.ArrayList(SourceFile) = .empty,

    pub fn deinit(self: *SourceMap, allocator: Allocator) void {
        for (self.items.items) |*item| {
            item.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(self: *SourceMap, allocator: Allocator, path: []const u8, bytes: []const u8) !SourceId {
        if (self.items.items.len > std.math.maxInt(u32)) return error.TooManySources;
        if (bytes.len > std.math.maxInt(u32)) return error.SourceTooLarge;

        const owned_path = try allocator.dupe(u8, path);
        errdefer allocator.free(owned_path);

        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);

        const id: SourceId = .{ .index = @intCast(self.items.items.len) };
        try self.items.append(allocator, .{
            .path = owned_path,
            .bytes = owned_bytes,
        });
        return id;
    }

    pub fn get(self: *const SourceMap, id: SourceId) !*const SourceFile {
        if (id.index >= self.items.items.len) return error.InvalidSource;
        return &self.items.items[id.index];
    }

    pub fn location(self: *const SourceMap, span: SourceSpan) !?SourceLocation {
        const source_id = span.source orelse return null;
        const file = try self.get(source_id);
        const position = lineColumn(file.bytes, span.start);
        return .{
            .path = file.path,
            .line = position.line,
            .column = position.column,
        };
    }
};

const LineColumn = struct {
    line: u32,
    column: u32,
};

fn lineColumn(bytes: []const u8, offset: u32) LineColumn {
    const span_offset: usize = @intCast(offset);
    const wanted_offset = @min(span_offset, bytes.len);
    var index: usize = 0;
    var line: u32 = 1;
    var column: u32 = 1;

    while (index < wanted_offset) : (index += 1) {
        if (bytes[index] == '\n') {
            line += 1;
            column = 1;
        } else if (bytes[index] == '\r') {
            line += 1;
            column = 1;
            if (index + 1 < wanted_offset and bytes[index + 1] == '\n') {
                index += 1;
            }
        } else {
            column += 1;
        }
    }

    return .{
        .line = line,
        .column = column,
    };
}

test "source map resolves path line and column" {
    var source_map: SourceMap = .{};
    defer source_map.deinit(std.testing.allocator);

    const source_id = try source_map.add(std.testing.allocator, "src/main.xir", "one\n  two\n");
    const location_info = (try source_map.location(.{
        .source = source_id,
        .start = 6,
        .end = 9,
    })) orelse return error.MissingLocation;

    try std.testing.expectEqualStrings("src/main.xir", location_info.path);
    try std.testing.expectEqual(@as(u32, 2), location_info.line);
    try std.testing.expectEqual(@as(u32, 3), location_info.column);
}
