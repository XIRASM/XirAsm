const std = @import("std");

const meta_io = @import("meta_io.zig");
const source_mod = @import("source.zig");
const toml = @import("../data/toml_parser.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || meta_io.Error || toml.ParseError || error{
    InvalidArgument,
    InvalidApiInteger,
    TypeMismatch,
};

pub const ReadError = Allocator.Error || meta_io.Error || error{InvalidApiInteger};

pub const ByteRange = struct {
    offset: usize,
    count: usize,
};

const EvalContext = struct {
    file_resolver: ?meta_io.FileResolver,
    parent_path: ?[]const u8,
};

const BuiltinId = enum {
    fs_exists,
    fs_read_text,
    fs_read_bytes,
    fs_list_dir,
    fs_is_dir,
    toml_parse,
    toml_file,
    json_parse,
    json_file,
};

const Builtin = struct {
    name: []const u8,
    id: BuiltinId,
};

const builtins = [_]Builtin{
    // api-matrix-meta-data: "fs.exists"
    .{ .name = "fs.exists", .id = .fs_exists },
    // api-matrix-meta-data: "fs.read_text"
    .{ .name = "fs.read_text", .id = .fs_read_text },
    // api-matrix-meta-data: "fs.read_bytes"
    .{ .name = "fs.read_bytes", .id = .fs_read_bytes },
    // api-matrix-meta-data: "fs.list_dir"
    .{ .name = "fs.list_dir", .id = .fs_list_dir },
    // api-matrix-meta-data: "fs.is_dir"
    .{ .name = "fs.is_dir", .id = .fs_is_dir },
    // api-matrix-meta-data: "toml.parse"
    .{ .name = "toml.parse", .id = .toml_parse },
    // api-matrix-meta-data: "toml.file"
    .{ .name = "toml.file", .id = .toml_file },
    // api-matrix-meta-data: "json.parse"
    .{ .name = "json.parse", .id = .json_parse },
    // api-matrix-meta-data: "json.file"
    .{ .name = "json.file", .id = .json_file },
};

pub fn isBuiltinName(name: []const u8) bool {
    return lookupBuiltin(name) != null;
}

pub fn evalBuiltin(
    allocator: Allocator,
    name: []const u8,
    args: []const value_mod.Value,
    file_resolver: ?meta_io.FileResolver,
    parent_path: ?[]const u8,
) Error!value_mod.Value {
    const ctx: EvalContext = .{
        .file_resolver = file_resolver,
        .parent_path = parent_path,
    };
    return switch (lookupBuiltin(name) orelse return error.InvalidArgument) {
        .fs_exists => evalFsExists(allocator, args, ctx),
        .fs_read_text => evalFsRead(allocator, args, ctx, .text),
        .fs_read_bytes => evalFsRead(allocator, args, ctx, .bytes),
        .fs_list_dir => evalFsListDir(allocator, args, ctx),
        .fs_is_dir => evalFsIsDir(allocator, args, ctx),
        .toml_parse => evalTomlParse(allocator, args),
        .toml_file => evalTomlFile(allocator, args, ctx),
        .json_parse => evalJsonParse(allocator, args),
        .json_file => evalJsonFile(allocator, args, ctx),
    };
}

fn lookupBuiltin(name: []const u8) ?BuiltinId {
    for (builtins) |builtin| {
        if (std.mem.eql(u8, name, builtin.name)) return builtin.id;
    }
    return null;
}

fn evalFsExists(allocator: Allocator, args: []const value_mod.Value, ctx: EvalContext) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const resolver = ctx.file_resolver orelse return error.FileNotAvailable;
    const path = try expectString(args[0]);
    const exists = try resolver.exists(resolver.context, allocator, .{
        .path = path,
        .parent_path = ctx.parent_path,
        .span = source_mod.unknown_span,
        .kind = .bytes,
    });
    return .{ .boolean = exists };
}

fn evalFsRead(
    allocator: Allocator,
    args: []const value_mod.Value,
    ctx: EvalContext,
    kind: meta_io.FileReadKind,
) Error!value_mod.Value {
    switch (kind) {
        .text => {
            if (args.len != 1) return error.InvalidArgument;
            const result = try readFile(allocator, args[0], ctx, kind);
            allocator.free(result.path);
            return .{ .string = result.bytes };
        },
        .bytes => {
            if (args.len != 1 and args.len != 3) return error.InvalidArgument;
            const resolver = ctx.file_resolver orelse return error.FileNotAvailable;
            const path = try expectString(args[0]);
            const range: ?ByteRange = if (args.len == 3) .{
                .offset = try expectUsize(args[1]),
                .count = try expectUsize(args[2]),
            } else null;
            return .{ .bytes = try readBytes(
                allocator,
                resolver,
                path,
                ctx.parent_path,
                source_mod.unknown_span,
                range,
            ) };
        },
    }
}

/// Entries of a directory as a list of names, sorted so the result does not
/// depend on the order the host filesystem returns.
fn evalFsListDir(allocator: Allocator, args: []const value_mod.Value, ctx: EvalContext) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const resolver = ctx.file_resolver orelse return error.FileNotAvailable;
    const list = resolver.list orelse return error.FileNotAvailable;
    const path = try expectString(args[0]);

    var listing = try list(resolver.context, allocator, .{
        .path = path,
        .parent_path = ctx.parent_path,
        .span = source_mod.unknown_span,
    });
    defer listing.deinit(allocator);

    const items = try allocator.alloc(value_mod.Value, listing.entries.len);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| item.deinit(allocator);
        allocator.free(items);
    }
    for (listing.entries, 0..) |entry, index| {
        items[index] = .{ .string = try allocator.dupe(u8, entry.name) };
        initialized += 1;
    }
    sortStrings(items);
    return .{ .list = .{ .items = items } };
}

/// True when the path names an existing directory. Like `fs.exists`, this never
/// fails: a host without directory support answers false.
fn evalFsIsDir(allocator: Allocator, args: []const value_mod.Value, ctx: EvalContext) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const resolver = ctx.file_resolver orelse return error.FileNotAvailable;
    const path = try expectString(args[0]);
    const is_directory = if (resolver.is_dir) |check| try check(resolver.context, allocator, .{
        .path = path,
        .parent_path = ctx.parent_path,
        .span = source_mod.unknown_span,
    }) else false;
    return .{ .boolean = is_directory };
}

fn sortStrings(items: []value_mod.Value) void {
    std.mem.sort(value_mod.Value, items, {}, struct {
        fn lessThan(_: void, left: value_mod.Value, right: value_mod.Value) bool {
            return std.mem.order(u8, stringOf(left), stringOf(right)) == .lt;
        }

        fn stringOf(value: value_mod.Value) []const u8 {
            return switch (value) {
                .string => |text| text,
                else => "",
            };
        }
    }.lessThan);
}

pub fn readBytes(
    allocator: Allocator,
    resolver: meta_io.FileResolver,
    path: []const u8,
    parent_path: ?[]const u8,
    span: source_mod.SourceSpan,
    range: ?ByteRange,
) ReadError![]u8 {
    var result = try resolver.read(resolver.context, allocator, .{
        .path = path,
        .parent_path = parent_path,
        .span = span,
        .kind = .bytes,
    });
    const selected = range orelse {
        allocator.free(result.path);
        return result.bytes;
    };
    defer result.deinit(allocator);

    if (selected.offset > result.bytes.len) return error.InvalidApiInteger;
    const available = result.bytes.len - selected.offset;
    if (selected.count > available) return error.InvalidApiInteger;
    return allocator.dupe(u8, result.bytes[selected.offset..][0..selected.count]);
}

fn evalTomlParse(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const source = switch (args[0]) {
        .string => |text| text,
        .bytes => |bytes| bytes,
        .operand, .void, .integer, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.TypeMismatch,
    };
    return parseTomlValue(allocator, source);
}

fn evalTomlFile(allocator: Allocator, args: []const value_mod.Value, ctx: EvalContext) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    var result = try readFile(allocator, args[0], ctx, .text);
    defer result.deinit(allocator);
    return parseTomlValue(allocator, result.bytes);
}

fn evalJsonParse(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const source = switch (args[0]) {
        .string => |text| text,
        .bytes => |bytes| bytes,
        .operand, .void, .integer, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.TypeMismatch,
    };
    return parseJsonValue(allocator, source);
}

fn evalJsonFile(allocator: Allocator, args: []const value_mod.Value, ctx: EvalContext) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    var result = try readFile(allocator, args[0], ctx, .text);
    defer result.deinit(allocator);
    return parseJsonValue(allocator, result.bytes);
}

fn readFile(
    allocator: Allocator,
    path_value: value_mod.Value,
    ctx: EvalContext,
    kind: meta_io.FileReadKind,
) Error!meta_io.FileReadResult {
    const resolver = ctx.file_resolver orelse return error.FileNotAvailable;
    const path = try expectString(path_value);
    return resolver.read(resolver.context, allocator, .{
        .path = path,
        .parent_path = ctx.parent_path,
        .span = source_mod.unknown_span,
        .kind = kind,
    });
}

fn parseTomlValue(allocator: Allocator, source: []const u8) Error!value_mod.Value {
    var parsed = try toml.parse(allocator, source);
    defer parsed.deinit();
    return tomlNodeToValue(allocator, parsed.node);
}

fn parseJsonValue(allocator: Allocator, source: []const u8) Error!value_mod.Value {
    const options: std.json.ParseOptions = .{
        .duplicate_field_behavior = .@"error",
        .parse_numbers = true,
    };
    const parsed = std.json.parseFromSlice(std.json.Value, allocator, source, options) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.Overflow => return error.Overflow,
        error.DuplicateField => return error.DuplicateKey,
        error.BufferUnderrun,
        error.InvalidCharacter,
        error.InvalidEnumTag,
        error.InvalidNumber,
        error.LengthMismatch,
        error.MissingField,
        error.SyntaxError,
        error.UnexpectedEndOfInput,
        error.UnexpectedToken,
        error.UnknownField,
        error.ValueTooLong,
        => return error.Syntax,
    };
    defer parsed.deinit();
    return jsonValueToValue(allocator, parsed.value);
}

fn tomlNodeToValue(allocator: Allocator, node: toml.Node) Error!value_mod.Value {
    return switch (node.tag) {
        .string => .{ .string = try allocator.dupe(u8, node.data.string) },
        .boolean => .{ .boolean = node.data.boolean },
        .int64 => blk: {
            if (node.data.int64 < 0) return error.InvalidApiInteger;
            break :blk value_mod.Value.int(@intCast(node.data.int64));
        },
        .array => .{ .list = .{ .items = try tomlArrayToList(allocator, node.data.array) } },
        .table => .{ .map = .{ .entries = try tomlTableToMap(allocator, node.data.table) } },
        .fp64, .timestamp => return error.TypeMismatch,
    };
}

fn tomlArrayToList(allocator: Allocator, nodes: []const toml.Node) Error![]value_mod.Value {
    const items = try allocator.alloc(value_mod.Value, nodes.len);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    for (nodes, 0..) |node, index| {
        items[index] = try tomlNodeToValue(allocator, node);
        initialized += 1;
    }
    return items;
}

fn tomlTableToMap(allocator: Allocator, entries: []const toml.Node.Entry) Error![]value_mod.MapEntry {
    const output = try allocator.alloc(value_mod.MapEntry, entries.len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(output);
    }

    for (entries, 0..) |entry, index| {
        const key = try allocator.dupe(u8, entry.key);
        errdefer allocator.free(key);
        output[index] = .{
            .key = key,
            .value = try tomlNodeToValue(allocator, entry.value),
        };
        initialized += 1;
    }
    return output;
}

fn jsonValueToValue(allocator: Allocator, node: std.json.Value) Error!value_mod.Value {
    return jsonValueToValueAt(allocator, node, 0);
}

/// JSON documents arrive from `json.parse`/`json.file`, whose parser is
/// iterative and accepts any nesting depth, so this conversion is the first
/// recursive descent over them: without a bound a two-megabyte file of nested
/// `[` exhausts the stack and the process dies with no diagnostic. The name is
/// shared with the TOML document bound; both mean "this document nests too deep".
fn jsonValueToValueAt(allocator: Allocator, node: std.json.Value, depth: usize) Error!value_mod.Value {
    if (depth >= toml.max_document_nesting) return error.NestingTooDeep;
    return switch (node) {
        .null => .void,
        .bool => |stored| .{ .boolean = stored },
        .integer => |stored| jsonIntegerToValue(stored),
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |items| .{ .list = .{ .items = try jsonArrayToList(allocator, items.items, depth + 1) } },
        .object => |object| .{ .map = .{ .entries = try jsonObjectToMap(allocator, object, depth + 1) } },
        .float, .number_string => return error.TypeMismatch,
    };
}

fn jsonIntegerToValue(stored: i64) Error!value_mod.Value {
    if (stored < 0) return error.InvalidApiInteger;
    return value_mod.Value.int(@intCast(stored));
}

fn jsonArrayToList(allocator: Allocator, items: []const std.json.Value, depth: usize) Error![]value_mod.Value {
    const output = try allocator.alloc(value_mod.Value, items.len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (items, 0..) |item, index| {
        output[index] = try jsonValueToValueAt(allocator, item, depth);
        initialized += 1;
    }
    return output;
}

fn jsonObjectToMap(allocator: Allocator, object: std.json.ObjectMap, depth: usize) Error![]value_mod.MapEntry {
    const output = try allocator.alloc(value_mod.MapEntry, object.count());
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(output);
    }

    var iterator = object.iterator();
    while (iterator.next()) |entry| {
        const key = try allocator.dupe(u8, entry.key_ptr.*);
        errdefer allocator.free(key);
        output[initialized] = .{
            .key = key,
            .value = try jsonValueToValueAt(allocator, entry.value_ptr.*, depth),
        };
        initialized += 1;
    }
    return output;
}

fn expectString(value: value_mod.Value) Error![]const u8 {
    return switch (value) {
        .string => |text| text,
        .operand, .void, .integer, .float32, .float64, .boolean, .bytes, .type, .@"struct", .list, .map => error.TypeMismatch,
    };
}

fn expectUsize(value: value_mod.Value) Error!usize {
    const integer = switch (value) {
        .integer => |stored| stored.value,
        .operand, .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => return error.TypeMismatch,
    };
    if (integer > std.math.maxInt(usize)) return error.InvalidApiInteger;
    return @intCast(integer);
}

test "meta list_dir sorts by byte value and is_dir follows the resolver" {
    const allocator = std.testing.allocator;
    const Fake = struct {
        fn read(_: *anyopaque, _: Allocator, _: meta_io.FileReadRequest) meta_io.Error!meta_io.FileReadResult {
            return error.FileNotAvailable;
        }

        fn exists(_: *anyopaque, _: Allocator, _: meta_io.FileReadRequest) Allocator.Error!bool {
            return false;
        }

        /// Entries arrive in an order no filesystem promises, and the names are
        /// chosen so that byte order differs from a case-insensitive order: the
        /// uppercase `Z` sorts before the underscore, which sorts before the
        /// lowercase names.
        fn list(_: *anyopaque, list_allocator: Allocator, _: meta_io.FileListRequest) meta_io.Error!meta_io.DirListing {
            var entries: std.ArrayList(meta_io.DirEntry) = .empty;
            errdefer {
                for (entries.items) |entry| list_allocator.free(entry.name);
                entries.deinit(list_allocator);
            }
            for ([_][]const u8{ "apple.txt", "_under.txt", "sub", "Zebra.txt" }) |name| {
                const owned = try list_allocator.dupe(u8, name);
                errdefer list_allocator.free(owned);
                try entries.append(list_allocator, .{ .name = owned });
            }
            return .{ .entries = try entries.toOwnedSlice(list_allocator) };
        }

        /// Answers per path, so a wrong answer or a dropped request is visible.
        fn isDir(_: *anyopaque, _: Allocator, request: meta_io.FileListRequest) Allocator.Error!bool {
            return std.mem.eql(u8, request.path, "some/dir");
        }
    };

    var marker: u8 = 0;
    const resolver: meta_io.FileResolver = .{
        .context = @ptrCast(&marker),
        .read = Fake.read,
        .exists = Fake.exists,
        .list = Fake.list,
        .is_dir = Fake.isDir,
    };

    // A path argument is an owned mutable slice, so the literal is copied rather
    // than cast: `@constCast` would hand the callee a pointer into read-only data.
    const dir_name = try allocator.dupe(u8, "some/dir");
    defer allocator.free(dir_name);
    const other_dir_name = try allocator.dupe(u8, "other/dir");
    defer allocator.free(other_dir_name);

    var listing = try evalBuiltin(allocator, "fs.list_dir", &.{
        .{ .string = dir_name },
    }, resolver, null);
    defer listing.deinit(allocator);
    const items = try listing.expectList();
    try std.testing.expectEqual(@as(usize, 4), items.items.len);
    try std.testing.expectEqualStrings("Zebra.txt", try items.items[0].expectString());
    try std.testing.expectEqualStrings("_under.txt", try items.items[1].expectString());
    try std.testing.expectEqualStrings("apple.txt", try items.items[2].expectString());
    try std.testing.expectEqualStrings("sub", try items.items[3].expectString());

    var is_dir = try evalBuiltin(allocator, "fs.is_dir", &.{
        .{ .string = dir_name },
    }, resolver, null);
    defer is_dir.deinit(allocator);
    try std.testing.expect(try is_dir.expectBoolean());

    var other = try evalBuiltin(allocator, "fs.is_dir", &.{
        .{ .string = other_dir_name },
    }, resolver, null);
    defer other.deinit(allocator);
    try std.testing.expect(!try other.expectBoolean());

    // A host without directory support reports the path as unavailable and
    // answers false, which is the documented contract for the optional entry.
    const bare: meta_io.FileResolver = .{
        .context = @ptrCast(&marker),
        .read = Fake.read,
        .exists = Fake.exists,
    };
    try std.testing.expectError(error.FileNotAvailable, evalBuiltin(allocator, "fs.list_dir", &.{
        .{ .string = dir_name },
    }, bare, null));
    var absent = try evalBuiltin(allocator, "fs.is_dir", &.{
        .{ .string = dir_name },
    }, bare, null);
    defer absent.deinit(allocator);
    try std.testing.expect(!try absent.expectBoolean());
}

test "meta data parses toml into map values" {
    const allocator = std.testing.allocator;
    const toml_text = try allocator.dupe(u8, "name = \"cfg\"\n[target]\nbits = 64\n");
    defer allocator.free(toml_text);
    var result = try evalBuiltin(allocator, "toml.parse", &.{
        .{ .string = toml_text },
    }, null, null);
    defer result.deinit(allocator);

    const root = try result.expectMap();
    const name = root.entryByKey("name") orelse return error.UnexpectedTestResult;
    try std.testing.expectEqualStrings("cfg", try name.value.expectString());
    const target = root.entryByKey("target") orelse return error.UnexpectedTestResult;
    const target_map = try target.value.expectMap();
    const bits = target_map.entryByKey("bits") orelse return error.UnexpectedTestResult;
    try std.testing.expectEqual(@as(u64, 64), try bits.value.expectInteger());
}
