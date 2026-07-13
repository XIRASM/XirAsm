const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const BoundaryError = error{
    InvalidArguments,
    InvalidReleasePath,
    BannedPathReference,
    BannedBrandReference,
    BannedAbsolutePath,
};

const FileText = struct {
    path: []const u8,
    bytes: []const u8,
};

const banned_brand_tokens = [_][]const u8{
    &[_]u8{ 'f', 'a', 's', 'm', 'g' },
    &[_]u8{ 'f', 'a', 's', 'm' },
    &[_]u8{ 'n', 'a', 's', 'm' },
    &[_]u8{ 'm', 'a', 's', 'm' },
    &[_]u8{ 'g', 'a', 's' },
    &[_]u8{ 'y', 'a', 's', 'm' },
    &[_]u8{ 'z', 'a', 's', 'm', 'g' },
    &[_]u8{ 'c', 'o', 'd', 'e', 'x' },
    &[_]u8{ 'c', 'h', 'a', 't', 'g', 'p', 't' },
    &[_]u8{ 'o', 'p', 'e', 'n', 'a', 'i' },
    &[_]u8{ 'c', 'l', 'a', 'u', 'd', 'e' },
    &[_]u8{ 'a', 'n', 't', 'h', 'r', 'o', 'p', 'i', 'c' },
    &[_]u8{ 'g', 'e', 'm', 'i', 'n', 'i' },
    &[_]u8{ 'c', 'o', 'p', 'i', 'l', 'o', 't' },
};

const banned_docs_dir = [_]u8{ 'd', 'o', 'c', 's' };
const banned_local_dir = [_]u8{ '.', 'l', 'o', 'c', 'a', 'l' };
const banned_agents_dir = [_]u8{ '.', 'a', 'g', 'e', 'n', 't', 's' };

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 2) {
        try stderr.print("usage: {s} <release-candidate-file>...\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    var failed = false;
    var manifest_text: ?[]const u8 = null;
    var readme_text: ?[]const u8 = null;
    var readme_zh_text: ?[]const u8 = null;
    for (args[1..]) |path| {
        const file = FileText{
            .path = path,
            .bytes = readFile(allocator, init.io, path) catch |err| {
                try stderr.print("release boundary read failed: {s}: {s}\n", .{ path, @errorName(err) });
                failed = true;
                continue;
            },
        };

        if (pathIs(file.path, "build.zig.zon")) manifest_text = file.bytes;
        if (pathIs(file.path, "README.md")) readme_text = file.bytes;
        if (pathIs(file.path, "README.zh-CN.md")) readme_zh_text = file.bytes;

        failed = (try validateReleasePath(stderr, file.path)) or failed;
        failed = (try validateBannedPathReferences(stderr, file)) or failed;
        failed = (try validateBannedAbsolutePaths(stderr, file)) or failed;
        failed = (try validateBannedBrands(stderr, file)) or failed;
    }

    failed = (try validateVersionConsistency(
        stderr,
        manifest_text,
        readme_text,
        readme_zh_text,
    )) or failed;

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn validateReleasePath(stderr: *Io.Writer, path: []const u8) !bool {
    const allowed = pathIs(path, "build.zig") or
        pathIs(path, "build.zig.zon") or
        pathIs(path, "LICENSE") or
        pathIs(path, "README.md") or
        pathIs(path, "README.zh-CN.md") or
        pathHasSegmentPrefix(path, "src") or
        pathHasSegmentPrefix(path, "include") or
        pathHasSegmentPrefix(path, "tests") or
        pathHasSegmentPrefix(path, "deps") or
        pathHasSegmentPrefix(path, "document");
    if (allowed) return false;
    try stderr.print("release boundary invalid candidate path: {s}\n", .{path});
    return true;
}

fn validateBannedPathReferences(stderr: *Io.Writer, file: FileText) !bool {
    var failed = false;
    if (containsPathReference(file.bytes, banned_local_dir[0..])) {
        try stderr.print("release boundary banned .local reference: {s}\n", .{file.path});
        failed = true;
    }
    if (containsPathReference(file.bytes, banned_agents_dir[0..])) {
        try stderr.print("release boundary banned .agents reference: {s}\n", .{file.path});
        failed = true;
    }
    if (containsPathReference(file.bytes, banned_docs_dir[0..])) {
        try stderr.print("release boundary banned docs directory reference: {s}\n", .{file.path});
        failed = true;
    }
    return failed;
}

fn validateBannedAbsolutePaths(stderr: *Io.Writer, file: FileText) !bool {
    if (hasWindowsDrivePath(file.bytes) or hasWslMountPath(file.bytes)) {
        try stderr.print("release boundary absolute path reference: {s}\n", .{file.path});
        return true;
    }
    return false;
}

fn validateBannedBrands(stderr: *Io.Writer, file: FileText) !bool {
    var failed = false;
    var line_it = std.mem.splitScalar(u8, file.bytes, '\n');
    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        for (banned_brand_tokens) |token| {
            if (containsWordIgnoreCase(line, token)) {
                try stderr.print(
                    "release boundary banned brand reference: {s}: {s}\n",
                    .{ file.path, token },
                );
                failed = true;
            }
        }
    }
    return failed;
}

fn validateVersionConsistency(
    stderr: *Io.Writer,
    manifest_text: ?[]const u8,
    readme_text: ?[]const u8,
    readme_zh_text: ?[]const u8,
) !bool {
    const manifest_bytes = manifest_text orelse {
        try stderr.writeAll("release boundary missing build.zig.zon\n");
        return true;
    };
    const manifest_version = manifestVersion(manifest_bytes) orelse {
        try stderr.writeAll("release boundary missing build.zig.zon version\n");
        return true;
    };

    var failed = false;
    failed = (try validateDocumentVersion(
        stderr,
        "README.md",
        readme_text,
        "Current version: **",
        manifest_version,
    )) or failed;
    failed = (try validateDocumentVersion(
        stderr,
        "README.zh-CN.md",
        readme_zh_text,
        "当前版本：**",
        manifest_version,
    )) or failed;
    return failed;
}

fn validateDocumentVersion(
    stderr: *Io.Writer,
    path: []const u8,
    text: ?[]const u8,
    marker: []const u8,
    expected: []const u8,
) !bool {
    const bytes = text orelse {
        try stderr.print("release boundary missing version document: {s}\n", .{path});
        return true;
    };
    const actual = markedVersion(bytes, marker) orelse {
        try stderr.print("release boundary missing version marker: {s}\n", .{path});
        return true;
    };
    if (std.mem.eql(u8, actual, expected)) return false;
    try stderr.print(
        "release boundary version mismatch: {s}={s}, build.zig.zon={s}\n",
        .{ path, actual, expected },
    );
    return true;
}

fn markedVersion(bytes: []const u8, marker: []const u8) ?[]const u8 {
    const marker_index = std.mem.indexOf(u8, bytes, marker) orelse return null;
    const after_marker = bytes[marker_index + marker.len ..];
    const end_index = std.mem.indexOf(u8, after_marker, "**") orelse return null;
    return after_marker[0..end_index];
}

fn manifestVersion(bytes: []const u8) ?[]const u8 {
    const marker = ".version";
    const marker_index = std.mem.indexOf(u8, bytes, marker) orelse return null;
    const after_marker = bytes[marker_index + marker.len ..];
    const first_quote_index = std.mem.indexOfScalar(u8, after_marker, '"') orelse return null;
    const after_first_quote = after_marker[first_quote_index + 1 ..];
    const second_quote_index = std.mem.indexOfScalar(u8, after_first_quote, '"') orelse return null;
    return after_first_quote[0..second_quote_index];
}

fn containsPathReference(text: []const u8, name: []const u8) bool {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, text, offset, name)) |index| {
        const next = index + name.len;
        if (next >= text.len) return true;
        if (text[next] == '/' or text[next] == '\\') return true;
        offset = next;
    }
    return false;
}

fn hasWindowsDrivePath(text: []const u8) bool {
    if (text.len < 3) return false;
    var index: usize = 0;
    while (index + 2 < text.len) : (index += 1) {
        const c = text[index];
        const before_ok = index == 0 or !std.ascii.isAlphanumeric(text[index - 1]);
        if (before_ok and
            ((c >= 'A' and c <= 'Z') or (c >= 'a' and c <= 'z')) and
            text[index + 1] == ':' and
            (text[index + 2] == '\\' or text[index + 2] == '/'))
        {
            return true;
        }
    }
    return false;
}

fn hasWslMountPath(text: []const u8) bool {
    const prefix = "/mnt/";
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, text, offset, prefix)) |index| {
        const drive_index = index + prefix.len;
        const separator_index = drive_index + 1;
        const before_ok = index == 0 or !std.ascii.isAlphanumeric(text[index - 1]);
        if (separator_index < text.len and
            before_ok and
            std.ascii.isAlphabetic(text[drive_index]) and
            text[separator_index] == '/')
        {
            return true;
        }
        offset = index + prefix.len;
    }
    return false;
}

fn containsWordIgnoreCase(text: []const u8, needle: []const u8) bool {
    var index: usize = 0;
    while (index + needle.len <= text.len) : (index += 1) {
        if (!wordBoundary(text, index)) continue;
        if (!wordBoundary(text, index + needle.len)) continue;
        if (asciiEqlIgnoreCase(text[index .. index + needle.len], needle)) return true;
    }
    return false;
}

fn wordBoundary(text: []const u8, index: usize) bool {
    if (index == 0 or index >= text.len) return true;
    const c = text[index - 1];
    if (std.ascii.isAlphanumeric(c) or c == '_') return false;
    return true;
}

fn asciiEqlIgnoreCase(a: []const u8, b: []const u8) bool {
    if (a.len != b.len) return false;
    for (a, b) |left, right| {
        if (std.ascii.toLower(left) != std.ascii.toLower(right)) return false;
    }
    return true;
}

fn startsWithPath(path: []const u8, prefix: []const u8) bool {
    return std.mem.startsWith(u8, path, prefix);
}

fn pathIs(path: []const u8, expected: []const u8) bool {
    return std.mem.eql(u8, path, expected) or pathEndsWith(path, expected);
}

fn pathEndsWith(path: []const u8, suffix: []const u8) bool {
    if (std.mem.endsWith(u8, path, suffix)) {
        if (path.len == suffix.len) return true;
        const separator = path[path.len - suffix.len - 1];
        return separator == '/' or separator == '\\';
    }

    var suffix_index = suffix.len;
    var path_index = path.len;
    while (suffix_index > 0 and path_index > 0) {
        suffix_index -= 1;
        path_index -= 1;
        const expected = suffix[suffix_index];
        const actual = path[path_index];
        const matches = if (expected == '/')
            actual == '/' or actual == '\\'
        else
            actual == expected;
        if (!matches) return false;
    }
    if (suffix_index != 0) return false;
    if (path_index == 0) return true;
    return path[path_index - 1] == '/' or path[path_index - 1] == '\\';
}

fn pathHasSegmentPrefix(path: []const u8, segment: []const u8) bool {
    if (std.mem.startsWith(u8, path, segment) and path.len > segment.len and
        (path[segment.len] == '/' or path[segment.len] == '\\'))
    {
        return true;
    }

    var index: usize = 0;
    while (std.mem.indexOfPos(u8, path, index, segment)) |found| {
        const before_ok = found == 0 or path[found - 1] == '/' or path[found - 1] == '\\';
        const after = found + segment.len;
        const after_ok = after < path.len and (path[after] == '/' or path[after] == '\\');
        if (before_ok and after_ok) return true;
        index = after;
    }
    return false;
}
