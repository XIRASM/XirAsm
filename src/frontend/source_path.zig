const std = @import("std");

const Allocator = std.mem.Allocator;

pub fn normalizeIdentity(allocator: Allocator, path: []const u8) Allocator.Error![]u8 {
    if (usesWindowsSyntax(path)) {
        return std.fs.path.resolveWindows(allocator, &.{path});
    }
    return std.fs.path.resolvePosix(allocator, &.{path});
}

pub fn resolveIdentity(
    allocator: Allocator,
    parent_path: ?[]const u8,
    include_path: []const u8,
) Allocator.Error![]u8 {
    const parent = parent_path orelse return normalizeIdentity(allocator, include_path);
    const windows = usesWindowsSyntax(parent) or usesWindowsSyntax(include_path);
    const parent_dir = if (windows)
        std.fs.path.dirnameWindows(parent)
    else
        std.fs.path.dirnamePosix(parent);

    if (parent_dir) |directory| {
        if (windows) return std.fs.path.resolveWindows(allocator, &.{ directory, include_path });
        return std.fs.path.resolvePosix(allocator, &.{ directory, include_path });
    }
    return normalizeIdentity(allocator, include_path);
}

fn usesWindowsSyntax(path: []const u8) bool {
    if (std.mem.indexOfScalar(u8, path, '\\') != null) return true;
    return path.len >= 2 and std.ascii.isAlphabetic(path[0]) and path[1] == ':';
}

test "source identities normalize POSIX aliases" {
    const normalized = try normalizeIdentity(std.testing.allocator, "src/shared/../shared/./file.xir");
    defer std.testing.allocator.free(normalized);
    try std.testing.expectEqualStrings("src/shared/file.xir", normalized);
}

test "source identities resolve Windows aliases with canonical separators" {
    const resolved = try resolveIdentity(std.testing.allocator, "c" ++ ":/project/src/main.xir", ".\\shared\\..\\file.xir");
    defer std.testing.allocator.free(resolved);
    try std.testing.expectEqualStrings("C" ++ ":\\project\\src\\file.xir", resolved);
}
