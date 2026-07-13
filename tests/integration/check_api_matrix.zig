const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

const MatrixError = error{
    InvalidArguments,
    InvalidHeader,
    InvalidRow,
    InvalidCategory,
    DuplicateId,
    DuplicateSurface,
    MissingImplementationMarker,
    MissingFixtureMarker,
    MissingMatrixEntry,
};

const Row = struct {
    id: []const u8,
    category: []const u8,
    surface: []const u8,
    implementation: []const u8,
    fixture: []const u8,
    note: []const u8,
};

const FileText = struct {
    path: []const u8,
    bytes: []const u8,
};

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 5) {
        try stderr.print("usage: {s} <matrix.tsv> <impl...> --fixtures <source-fixtures...>\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const separator_index = findSeparator(args[2..], "--fixtures") orelse {
        try stderr.print("error: missing --fixtures separator\n", .{});
        try stderr.flush();
        std.process.exit(2);
    };
    const impl_args = args[2 .. 2 + separator_index];
    const fixture_args = args[3 + separator_index ..];
    if (impl_args.len == 0 or fixture_args.len == 0) {
        try stderr.print("error: implementation and fixture file lists must be non-empty\n", .{});
        try stderr.flush();
        std.process.exit(2);
    }

    const matrix_text = try readFile(allocator, init.io, args[1]);
    var rows = parseMatrix(allocator, matrix_text) catch |err| {
        try stderr.print("api matrix parse failed: {s}\n", .{@errorName(err)});
        try stderr.flush();
        std.process.exit(1);
    };
    defer rows.deinit(allocator);

    const impl_files = try readFiles(allocator, init.io, impl_args);
    const fixture_files = try readFiles(allocator, init.io, fixture_args);

    var lower_apis: std.ArrayList([]const u8) = .empty;
    var expr_apis: std.ArrayList([]const u8) = .empty;
    try collectImplementedApis(allocator, impl_files, &lower_apis, &expr_apis);

    var failed = false;
    failed = (try validateRows(stderr, rows.items, impl_files, fixture_files)) or failed;
    failed = (try validateExtractedApis(stderr, rows.items, lower_apis.items, "api")) or failed;
    failed = (try validateExtractedApis(stderr, rows.items, expr_apis.items, "expr")) or failed;

    if (failed) {
        try stderr.flush();
        std.process.exit(1);
    }
}

fn findSeparator(values: []const []const u8, name: []const u8) ?usize {
    for (values, 0..) |value, index| {
        if (std.mem.eql(u8, value, name)) return index;
    }
    return null;
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn readFiles(allocator: Allocator, io: Io, paths: []const []const u8) ![]FileText {
    const files = try allocator.alloc(FileText, paths.len);
    errdefer allocator.free(files);
    for (paths, 0..) |path, index| {
        files[index] = .{
            .path = path,
            .bytes = try readFile(allocator, io, path),
        };
    }
    return files;
}

fn parseMatrix(allocator: Allocator, text: []const u8) !std.ArrayList(Row) {
    var rows: std.ArrayList(Row) = .empty;
    errdefer rows.deinit(allocator);

    var line_it = std.mem.splitScalar(u8, text, '\n');
    const header = std.mem.trim(u8, line_it.next() orelse return MatrixError.InvalidHeader, "\r");
    if (!std.mem.eql(u8, header, "id\tcategory\tsurface\timplementation\tfixture\tnote")) {
        return MatrixError.InvalidHeader;
    }

    while (line_it.next()) |raw_line| {
        const line = std.mem.trim(u8, raw_line, "\r");
        if (line.len == 0) continue;
        const row = try parseRow(line);
        if (!isCategory(row.category)) return MatrixError.InvalidCategory;
        if (row.id.len == 0 or row.surface.len == 0 or row.implementation.len == 0 or row.fixture.len == 0) {
            return MatrixError.InvalidRow;
        }
        for (rows.items) |existing| {
            if (std.mem.eql(u8, existing.id, row.id)) return MatrixError.DuplicateId;
            if (std.mem.eql(u8, existing.category, row.category) and std.mem.eql(u8, existing.surface, row.surface)) {
                return MatrixError.DuplicateSurface;
            }
        }
        try rows.append(allocator, row);
    }

    return rows;
}

fn parseRow(line: []const u8) !Row {
    var fields: [6][]const u8 = undefined;
    var field_count: usize = 0;
    var it = std.mem.splitScalar(u8, line, '\t');
    while (it.next()) |field| {
        if (field_count >= fields.len) return MatrixError.InvalidRow;
        fields[field_count] = field;
        field_count += 1;
    }
    if (field_count != fields.len) return MatrixError.InvalidRow;
    return .{
        .id = fields[0],
        .category = fields[1],
        .surface = fields[2],
        .implementation = fields[3],
        .fixture = fields[4],
        .note = fields[5],
    };
}

fn isCategory(value: []const u8) bool {
    return std.mem.eql(u8, value, "syntax") or
        std.mem.eql(u8, value, "api") or
        std.mem.eql(u8, value, "expr") or
        std.mem.eql(u8, value, "format");
}

fn validateRows(
    stderr: *Io.Writer,
    rows: []const Row,
    impl_files: []const FileText,
    fixture_files: []const FileText,
) !bool {
    var failed = false;
    for (rows) |row| {
        if (!markersCovered(row.implementation, impl_files)) {
            try stderr.print(
                "api matrix missing implementation marker: {s} ({s}) marker={s}\n",
                .{ row.id, row.surface, row.implementation },
            );
            failed = true;
        }
        if (!markersCovered(row.fixture, fixture_files)) {
            try stderr.print(
                "api matrix missing fixture marker: {s} ({s}) marker={s}\n",
                .{ row.id, row.surface, row.fixture },
            );
            failed = true;
        }
    }
    return failed;
}

fn markersCovered(markers: []const u8, files: []const FileText) bool {
    var it = std.mem.splitScalar(u8, markers, ';');
    while (it.next()) |raw_marker| {
        const marker = std.mem.trim(u8, raw_marker, " ");
        if (marker.len == 0) return false;
        if (!filesContain(files, marker)) return false;
    }
    return true;
}

fn filesContain(files: []const FileText, needle: []const u8) bool {
    for (files) |file| {
        if (std.mem.indexOf(u8, file.bytes, needle) != null) return true;
    }
    return false;
}

fn collectImplementedApis(
    allocator: Allocator,
    impl_files: []const FileText,
    lower_apis: *std.ArrayList([]const u8),
    expr_apis: *std.ArrayList([]const u8),
) !void {
    for (impl_files) |file| {
        if (isLowerImplementationPath(file.path)) {
            try collectQuotedAfter(allocator, file.bytes, "call.callee, \"", lower_apis);
            try collectQuotedAfter(allocator, file.bytes, "api-matrix-lower: \"", lower_apis);
        } else if (std.mem.endsWith(u8, file.path, "expr.zig")) {
            try collectQuotedAfter(allocator, file.bytes, "call.name, \"", expr_apis);
        } else if (std.mem.endsWith(u8, file.path, "meta_std.zig")) {
            try collectQuotedAfter(allocator, file.bytes, "api-matrix-meta-std: \"", expr_apis);
        } else if (std.mem.endsWith(u8, file.path, "meta_data.zig")) {
            try collectQuotedAfter(allocator, file.bytes, "api-matrix-meta-data: \"", expr_apis);
        }
    }
}

fn isLowerImplementationPath(path: []const u8) bool {
    return std.mem.endsWith(u8, path, "lower.zig") or
        std.mem.indexOf(u8, path, "/lower/") != null or
        std.mem.indexOf(u8, path, "\\lower\\") != null;
}

fn collectQuotedAfter(
    allocator: Allocator,
    text: []const u8,
    prefix: []const u8,
    out: *std.ArrayList([]const u8),
) !void {
    var offset: usize = 0;
    while (std.mem.indexOfPos(u8, text, offset, prefix)) |prefix_index| {
        const start = prefix_index + prefix.len;
        const rest = text[start..];
        const end_delta = std.mem.indexOfScalar(u8, rest, '"') orelse return MatrixError.InvalidRow;
        const value = text[start .. start + end_delta];
        if (!contains(out.items, value)) try out.append(allocator, value);
        offset = start + end_delta + 1;
    }
}

fn validateExtractedApis(
    stderr: *Io.Writer,
    rows: []const Row,
    names: []const []const u8,
    category: []const u8,
) !bool {
    var failed = false;
    for (names) |name| {
        if (!hasSurface(rows, category, name)) {
            try stderr.print("api matrix missing {s} implementation entry: {s}\n", .{ category, name });
            failed = true;
        }
    }
    for (rows) |row| {
        if (std.mem.eql(u8, row.category, category) and !contains(names, row.surface)) {
            try stderr.print("api matrix {s} entry not implemented: {s}\n", .{ category, row.surface });
            failed = true;
        }
    }
    return failed;
}

fn hasSurface(rows: []const Row, category: []const u8, surface: []const u8) bool {
    for (rows) |row| {
        if (std.mem.eql(u8, row.category, category) and std.mem.eql(u8, row.surface, surface)) return true;
    }
    return false;
}

fn contains(values: []const []const u8, needle: []const u8) bool {
    for (values) |value| {
        if (std.mem.eql(u8, value, needle)) return true;
    }
    return false;
}
