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

const EvalContext = struct {
    file_resolver: ?meta_io.FileResolver,
    parent_path: ?[]const u8,
};

const BuiltinId = enum {
    fs_exists,
    fs_read_text,
    fs_read_bytes,
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
            if (args.len == 1) {
                const result = try readFile(allocator, args[0], ctx, kind);
                allocator.free(result.path);
                return .{ .bytes = result.bytes };
            }

            var result = try readFile(allocator, args[0], ctx, kind);
            defer result.deinit(allocator);

            const offset = try expectUsize(args[1]);
            const count = try expectUsize(args[2]);
            if (offset > result.bytes.len) return error.InvalidApiInteger;
            const available = result.bytes.len - offset;
            if (count > available) return error.InvalidApiInteger;

            return .{ .bytes = try allocator.dupe(u8, result.bytes[offset..][0..count]) };
        },
    }
}

fn evalTomlParse(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const source = switch (args[0]) {
        .string => |text| text,
        .bytes => |bytes| bytes,
        .void, .integer, .boolean, .type, .@"struct", .list, .map => return error.TypeMismatch,
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
        .void, .integer, .boolean, .type, .@"struct", .list, .map => return error.TypeMismatch,
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
    return switch (node) {
        .null => .void,
        .bool => |stored| .{ .boolean = stored },
        .integer => |stored| jsonIntegerToValue(stored),
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .array => |items| .{ .list = .{ .items = try jsonArrayToList(allocator, items.items) } },
        .object => |object| .{ .map = .{ .entries = try jsonObjectToMap(allocator, object) } },
        .float, .number_string => return error.TypeMismatch,
    };
}

fn jsonIntegerToValue(stored: i64) Error!value_mod.Value {
    if (stored < 0) return error.InvalidApiInteger;
    return value_mod.Value.int(@intCast(stored));
}

fn jsonArrayToList(allocator: Allocator, items: []const std.json.Value) Error![]value_mod.Value {
    const output = try allocator.alloc(value_mod.Value, items.len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (items, 0..) |item, index| {
        output[index] = try jsonValueToValue(allocator, item);
        initialized += 1;
    }
    return output;
}

fn jsonObjectToMap(allocator: Allocator, object: std.json.ObjectMap) Error![]value_mod.MapEntry {
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
            .value = try jsonValueToValue(allocator, entry.value_ptr.*),
        };
        initialized += 1;
    }
    return output;
}

fn expectString(value: value_mod.Value) Error![]const u8 {
    return switch (value) {
        .string => |text| text,
        .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => error.TypeMismatch,
    };
}

fn expectUsize(value: value_mod.Value) Error!usize {
    const integer = switch (value) {
        .integer => |stored| stored.value,
        .void, .boolean, .string, .bytes, .type, .@"struct", .list, .map => return error.TypeMismatch,
    };
    if (integer > std.math.maxInt(usize)) return error.InvalidApiInteger;
    return @intCast(integer);
}

test "meta data parses toml into map values" {
    const allocator = std.testing.allocator;
    var result = try evalBuiltin(allocator, "toml.parse", &.{
        .{ .string = @constCast("name = \"cfg\"\n[target]\nbits = 64\n") },
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
