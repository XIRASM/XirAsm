const std = @import("std");

const token_match = @import("token_match.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{
    InvalidArgument,
    InvalidApiInteger,
    OutputTooLarge,
    TypeMismatch,
};

const BuiltinId = enum {
    len,
    to_string,
    trim,
    lower,
    upper,
    starts_with,
    ends_with,
    contains,
    replace,
    split,
    join,
    sym_join,
    bytes_new,
    bytes_push,
    bytes_concat,
    bytes_repeat,
    bytes_le,
    bytes_insert,
    bytes_replace,
    bytes_eq,
    bytes_hex,
    bytes_from_hex,
    list_new,
    list_of,
    list_push,
    list_concat,
    list_get,
    list_set,
    list_slice,
    list_eq,
    map_new,
    map_set,
    map_has,
    map_get,
    map_get_or,
    map_keys,
    map_values,
    map_eq,
    tokens_of,
    tokens_join,
    match_tokens,
};

const Builtin = struct {
    name: []const u8,
    id: BuiltinId,
};

const builtins = [_]Builtin{
    // api-matrix-meta-std: "len"
    .{ .name = "len", .id = .len },
    // api-matrix-meta-std: "to_string"
    .{ .name = "to_string", .id = .to_string },
    // api-matrix-meta-std: "trim"
    .{ .name = "trim", .id = .trim },
    // api-matrix-meta-std: "lower"
    .{ .name = "lower", .id = .lower },
    // api-matrix-meta-std: "upper"
    .{ .name = "upper", .id = .upper },
    // api-matrix-meta-std: "starts_with"
    .{ .name = "starts_with", .id = .starts_with },
    // api-matrix-meta-std: "ends_with"
    .{ .name = "ends_with", .id = .ends_with },
    // api-matrix-meta-std: "contains"
    .{ .name = "contains", .id = .contains },
    // api-matrix-meta-std: "replace"
    .{ .name = "replace", .id = .replace },
    // api-matrix-meta-std: "split"
    .{ .name = "split", .id = .split },
    // api-matrix-meta-std: "join"
    .{ .name = "join", .id = .join },
    // api-matrix-meta-std: "sym.join"
    .{ .name = "sym.join", .id = .sym_join },
    // api-matrix-meta-std: "bytes.new"
    .{ .name = "bytes.new", .id = .bytes_new },
    // api-matrix-meta-std: "bytes.push"
    .{ .name = "bytes.push", .id = .bytes_push },
    // api-matrix-meta-std: "bytes.concat"
    .{ .name = "bytes.concat", .id = .bytes_concat },
    // api-matrix-meta-std: "bytes.repeat"
    .{ .name = "bytes.repeat", .id = .bytes_repeat },
    // api-matrix-meta-std: "bytes.le"
    .{ .name = "bytes.le", .id = .bytes_le },
    // api-matrix-meta-std: "bytes.insert"
    .{ .name = "bytes.insert", .id = .bytes_insert },
    // api-matrix-meta-std: "bytes.replace"
    .{ .name = "bytes.replace", .id = .bytes_replace },
    // api-matrix-meta-std: "bytes.eq"
    .{ .name = "bytes.eq", .id = .bytes_eq },
    // api-matrix-meta-std: "bytes.hex"
    .{ .name = "bytes.hex", .id = .bytes_hex },
    // api-matrix-meta-std: "bytes.from_hex"
    .{ .name = "bytes.from_hex", .id = .bytes_from_hex },
    // api-matrix-meta-std: "list.new"
    .{ .name = "list.new", .id = .list_new },
    // api-matrix-meta-std: "list.of"
    .{ .name = "list.of", .id = .list_of },
    // api-matrix-meta-std: "list.push"
    .{ .name = "list.push", .id = .list_push },
    // api-matrix-meta-std: "list.concat"
    .{ .name = "list.concat", .id = .list_concat },
    // api-matrix-meta-std: "list.get"
    .{ .name = "list.get", .id = .list_get },
    // api-matrix-meta-std: "list.set"
    .{ .name = "list.set", .id = .list_set },
    // api-matrix-meta-std: "list.slice"
    .{ .name = "list.slice", .id = .list_slice },
    // api-matrix-meta-std: "list.eq"
    .{ .name = "list.eq", .id = .list_eq },
    // api-matrix-meta-std: "map.new"
    .{ .name = "map.new", .id = .map_new },
    // api-matrix-meta-std: "map.set"
    .{ .name = "map.set", .id = .map_set },
    // api-matrix-meta-std: "map.has"
    .{ .name = "map.has", .id = .map_has },
    // api-matrix-meta-std: "map.get"
    .{ .name = "map.get", .id = .map_get },
    // api-matrix-meta-std: "map.get_or"
    .{ .name = "map.get_or", .id = .map_get_or },
    // api-matrix-meta-std: "map.keys"
    .{ .name = "map.keys", .id = .map_keys },
    // api-matrix-meta-std: "map.values"
    .{ .name = "map.values", .id = .map_values },
    // api-matrix-meta-std: "map.eq"
    .{ .name = "map.eq", .id = .map_eq },
    // api-matrix-meta-std: "tokens.of"
    .{ .name = "tokens.of", .id = .tokens_of },
    // api-matrix-meta-std: "tokens.join"
    .{ .name = "tokens.join", .id = .tokens_join },
    // api-matrix-meta-std: "match.tokens"
    .{ .name = "match.tokens", .id = .match_tokens },
};

pub fn isBuiltinName(name: []const u8) bool {
    return lookupBuiltin(name) != null;
}

pub fn evalBuiltin(allocator: Allocator, name: []const u8, args: []const value_mod.Value) Error!value_mod.Value {
    return switch (lookupBuiltin(name) orelse return error.InvalidArgument) {
        .len => evalLen(args),
        .to_string => evalToString(allocator, args),
        .trim => evalTrim(allocator, args),
        .lower => evalAsciiCase(allocator, args, .lower),
        .upper => evalAsciiCase(allocator, args, .upper),
        .starts_with => evalStartsWith(args),
        .ends_with => evalEndsWith(args),
        .contains => evalContains(args),
        .replace => evalReplace(allocator, args),
        .split => evalSplit(allocator, args),
        .join => evalJoin(allocator, args),
        .sym_join => evalSymJoin(allocator, args),
        .bytes_new => evalBytesNew(allocator, args),
        .bytes_push => evalBytesPush(allocator, args),
        .bytes_concat => evalBytesConcat(allocator, args),
        .bytes_repeat => evalBytesRepeat(allocator, args),
        .bytes_le => evalBytesLe(allocator, args),
        .bytes_insert => evalBytesInsert(allocator, args),
        .bytes_replace => evalBytesReplace(allocator, args),
        .bytes_eq => evalBytesEq(args),
        .bytes_hex => evalBytesHex(allocator, args),
        .bytes_from_hex => evalBytesFromHex(allocator, args),
        .list_new => evalListNew(allocator, args),
        .list_of => evalListOf(allocator, args),
        .list_push => evalListPush(allocator, args),
        .list_concat => evalListConcat(allocator, args),
        .list_get => evalListGet(allocator, args),
        .list_set => evalListSet(allocator, args),
        .list_slice => evalListSlice(allocator, args),
        .list_eq => evalListEq(args),
        .map_new => evalMapNew(allocator, args),
        .map_set => evalMapSet(allocator, args),
        .map_has => evalMapHas(args),
        .map_get => evalMapGet(allocator, args),
        .map_get_or => evalMapGetOr(allocator, args),
        .map_keys => evalMapKeys(allocator, args),
        .map_values => evalMapValues(allocator, args),
        .map_eq => evalMapEq(args),
        .tokens_of => evalTokensOf(allocator, args),
        .tokens_join => evalTokensJoin(allocator, args),
        .match_tokens => evalMatchTokens(allocator, args),
    };
}

fn lookupBuiltin(name: []const u8) ?BuiltinId {
    for (builtins) |builtin| {
        if (std.mem.eql(u8, name, builtin.name)) return builtin.id;
    }
    return null;
}

fn evalLen(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    return value_mod.Value.int(switch (args[0]) {
        .string => |text| text.len,
        .bytes => |data| data.len,
        .list => |list| list.items.len,
        .map => |map| map.entries.len,
        .void, .integer, .float32, .float64, .boolean, .type, .@"struct" => return error.TypeMismatch,
    });
}

fn evalToString(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const text = try valueToString(allocator, args[0]);
    return .{ .string = text };
}

fn valueToString(allocator: Allocator, value: value_mod.Value) Error![]u8 {
    return switch (value) {
        .void => try allocator.dupe(u8, "void"),
        .integer => |integer| try std.fmt.allocPrint(allocator, "{}", .{integer.value}),
        .float32 => |stored| try value_mod.formatFloatLiteral(allocator, stored),
        .float64 => |stored| try value_mod.formatFloatLiteral(allocator, stored),
        .boolean => |stored| try allocator.dupe(u8, if (stored) "true" else "false"),
        .string => |text| try allocator.dupe(u8, text),
        .bytes => |data| try bytesToHex(allocator, data),
        .type => |id| try std.fmt.allocPrint(allocator, "type#{}", .{id.index}),
        .@"struct", .list, .map => return error.TypeMismatch,
    };
}

fn evalTrim(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const text = try expectString(args[0]);
    return .{ .string = try allocator.dupe(u8, std.mem.trim(u8, text, " \t\r\n")) };
}

const AsciiCase = enum { lower, upper };

fn evalAsciiCase(allocator: Allocator, args: []const value_mod.Value, case: AsciiCase) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const text = try expectString(args[0]);
    const owned = try allocator.dupe(u8, text);
    for (owned) |*byte| {
        byte.* = switch (case) {
            .lower => std.ascii.toLower(byte.*),
            .upper => std.ascii.toUpper(byte.*),
        };
    }
    return .{ .string = owned };
}

fn evalStartsWith(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = std.mem.startsWith(u8, try expectString(args[0]), try expectString(args[1])) };
}

fn evalEndsWith(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = std.mem.endsWith(u8, try expectString(args[0]), try expectString(args[1])) };
}

fn evalContains(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = switch (args[0]) {
        .string => |haystack| std.mem.indexOf(u8, haystack, try expectString(args[1])) != null,
        .bytes => |haystack| std.mem.indexOf(u8, haystack, try expectBytes(args[1])) != null,
        .void, .integer, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.TypeMismatch,
    } };
}

fn evalReplace(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const text = try expectString(args[0]);
    const needle = try expectString(args[1]);
    const replacement = try expectString(args[2]);
    if (needle.len == 0) return error.InvalidArgument;
    return .{ .string = try replaceAll(allocator, text, needle, replacement) };
}

fn evalSplit(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const text = try expectString(args[0]);
    const sep = try expectString(args[1]);
    if (sep.len == 0) return error.InvalidArgument;

    const item_count = std.math.add(usize, std.mem.count(u8, text, sep), 1) catch return error.OutputTooLarge;
    const items = try allocator.alloc(value_mod.Value, item_count);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    var rest = text;
    while (std.mem.indexOf(u8, rest, sep)) |index| {
        items[initialized] = .{ .string = try allocator.dupe(u8, rest[0..index]) };
        initialized += 1;
        rest = rest[index + sep.len ..];
    }
    items[initialized] = .{ .string = try allocator.dupe(u8, rest) };
    initialized += 1;

    return .{ .list = .{ .items = items } };
}

fn evalJoin(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const list = try expectList(args[0]);
    const sep = try expectString(args[1]);

    var output_len: usize = 0;
    for (list.items, 0..) |item, index| {
        const text = try expectString(item);
        output_len = std.math.add(usize, output_len, text.len) catch return error.OutputTooLarge;
        if (index != 0) {
            output_len = std.math.add(usize, output_len, sep.len) catch return error.OutputTooLarge;
        }
    }

    const output = try allocator.alloc(u8, output_len);
    var write_index: usize = 0;
    for (list.items, 0..) |item, index| {
        if (index != 0) {
            @memcpy(output[write_index .. write_index + sep.len], sep);
            write_index += sep.len;
        }
        const text = try expectString(item);
        @memcpy(output[write_index .. write_index + text.len], text);
        write_index += text.len;
    }
    return .{ .string = output };
}

fn evalSymJoin(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    var parts: std.ArrayList([]u8) = .empty;
    defer {
        for (parts.items) |part| {
            allocator.free(part);
        }
        parts.deinit(allocator);
    }

    var output_len: usize = 0;
    for (args) |arg| {
        const text = try valueToString(allocator, arg);
        errdefer allocator.free(text);
        try parts.append(allocator, text);
        output_len = std.math.add(usize, output_len, text.len) catch return error.OutputTooLarge;
    }

    const output = try allocator.alloc(u8, output_len);
    var write_index: usize = 0;
    for (parts.items) |part| {
        @memcpy(output[write_index .. write_index + part.len], part);
        write_index += part.len;
    }
    return .{ .string = output };
}

fn evalBytesNew(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 0) return error.InvalidArgument;
    return .{ .bytes = try allocator.alloc(u8, 0) };
}

fn evalBytesPush(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const input = try expectBytes(args[0]);
    const byte = try expectU8(args[1]);
    const output_len = std.math.add(usize, input.len, 1) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    @memcpy(output[0..input.len], input);
    output[input.len] = byte;
    return .{ .bytes = output };
}

fn evalBytesConcat(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const left = try expectBytes(args[0]);
    const right = try expectBytes(args[1]);
    const output_len = std.math.add(usize, left.len, right.len) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    @memcpy(output[0..left.len], left);
    @memcpy(output[left.len..], right);
    return .{ .bytes = output };
}

fn evalBytesRepeat(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const count = try expectUsize(args[0]);
    const byte = try expectU8(args[1]);
    const output = try allocator.alloc(u8, count);
    @memset(output, byte);
    return .{ .bytes = output };
}

fn evalBytesLe(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const value = try expectInteger(args[0]);
    const count = try expectUsize(args[1]);
    if (count > @sizeOf(u64)) return error.InvalidApiInteger;
    const output = try allocator.alloc(u8, count);
    var rest = value;
    for (output) |*byte| {
        byte.* = @intCast(rest & 0xff);
        rest >>= 8;
    }
    return .{ .bytes = output };
}

fn evalBytesInsert(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const target = try expectBytes(args[0]);
    const index = try expectUsize(args[1]);
    const src = try expectBytes(args[2]);
    if (index > target.len) return error.InvalidArgument;
    const output_len = std.math.add(usize, target.len, src.len) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    @memcpy(output[0..index], target[0..index]);
    @memcpy(output[index .. index + src.len], src);
    @memcpy(output[index + src.len ..], target[index..]);
    return .{ .bytes = output };
}

fn evalBytesReplace(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 4) return error.InvalidArgument;
    const target = try expectBytes(args[0]);
    const index = try expectUsize(args[1]);
    const count = try expectUsize(args[2]);
    const src = try expectBytes(args[3]);
    if (index > target.len) return error.InvalidArgument;
    const end = std.math.add(usize, index, count) catch return error.InvalidArgument;
    if (end > target.len) return error.InvalidArgument;
    const output_len = std.math.add(usize, target.len - count, src.len) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    @memcpy(output[0..index], target[0..index]);
    @memcpy(output[index .. index + src.len], src);
    @memcpy(output[index + src.len ..], target[end..]);
    return .{ .bytes = output };
}

fn evalBytesEq(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = std.mem.eql(u8, try expectBytes(args[0]), try expectBytes(args[1])) };
}

fn evalBytesHex(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    return .{ .string = try bytesToHex(allocator, try expectBytes(args[0])) };
}

fn evalBytesFromHex(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const text = try expectString(args[0]);
    if (text.len % 2 != 0) return error.InvalidArgument;
    const output = try allocator.alloc(u8, text.len / 2);
    errdefer allocator.free(output);
    var index: usize = 0;
    while (index < output.len) : (index += 1) {
        output[index] = (try hexNibble(text[index * 2]) << 4) | try hexNibble(text[index * 2 + 1]);
    }
    return .{ .bytes = output };
}

fn evalListNew(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 0) return error.InvalidArgument;
    return .{ .list = .{ .items = try allocator.alloc(value_mod.Value, 0) } };
}

fn evalListOf(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    return .{ .list = .{ .items = try value_mod.cloneValueSlice(allocator, args) } };
}

fn evalListPush(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const input = try expectList(args[0]);
    const output_len = std.math.add(usize, input.items.len, 1) catch return error.OutputTooLarge;
    const output = try allocator.alloc(value_mod.Value, output_len);
    var output_count: usize = 0;
    errdefer {
        for (output[0..output_count]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (input.items, 0..) |item, index| {
        output[index] = try item.clone(allocator);
        output_count += 1;
    }
    output[input.items.len] = try args[1].clone(allocator);
    output_count += 1;
    return .{ .list = .{ .items = output } };
}

fn evalListConcat(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const left = try expectList(args[0]);
    const right = try expectList(args[1]);
    const output_len = std.math.add(usize, left.items.len, right.items.len) catch return error.OutputTooLarge;
    const output = try allocator.alloc(value_mod.Value, output_len);
    var output_count: usize = 0;
    errdefer {
        for (output[0..output_count]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (left.items) |item| {
        output[output_count] = try item.clone(allocator);
        output_count += 1;
    }
    for (right.items) |item| {
        output[output_count] = try item.clone(allocator);
        output_count += 1;
    }
    return .{ .list = .{ .items = output } };
}

fn evalListGet(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const list = try expectList(args[0]);
    const index = try expectUsize(args[1]);
    if (index >= list.items.len) return error.InvalidArgument;
    return try list.items[index].clone(allocator);
}

fn evalListSet(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const list = try expectList(args[0]);
    const index = try expectUsize(args[1]);
    if (index >= list.items.len) return error.InvalidArgument;

    const output = try allocator.alloc(value_mod.Value, list.items.len);
    var output_count: usize = 0;
    errdefer {
        for (output[0..output_count]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (list.items, 0..) |item, item_index| {
        output[item_index] = if (item_index == index)
            try args[2].clone(allocator)
        else
            try item.clone(allocator);
        output_count += 1;
    }
    return .{ .list = .{ .items = output } };
}

fn evalListSlice(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const list = try expectList(args[0]);
    const start = try expectUsize(args[1]);
    const count = try expectUsize(args[2]);
    if (start > list.items.len) return error.InvalidArgument;
    const end = std.math.add(usize, start, count) catch return error.InvalidArgument;
    if (end > list.items.len) return error.InvalidArgument;
    return .{ .list = .{ .items = try value_mod.cloneValueSlice(allocator, list.items[start..end]) } };
}

fn evalListEq(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = listValuesEqual(try expectList(args[0]), try expectList(args[1])) };
}

fn evalMapNew(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 0) return error.InvalidArgument;
    return .{ .map = .{ .entries = try allocator.alloc(value_mod.MapEntry, 0) } };
}

fn evalMapSet(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const key = try expectString(args[1]);
    const existing_index = mapEntryIndex(input, key);
    const output_len = if (existing_index == null) input.entries.len + 1 else input.entries.len;
    const output = try allocator.alloc(value_mod.MapEntry, output_len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(output);
    }

    for (input.entries, 0..) |entry, index| {
        if (existing_index != null and existing_index.? == index) {
            output[index] = try cloneMapEntryWithValue(allocator, entry.key, args[2]);
        } else {
            output[index] = try entry.clone(allocator);
        }
        initialized += 1;
    }

    if (existing_index == null) {
        output[input.entries.len] = try cloneMapEntryWithValue(allocator, key, args[2]);
        initialized += 1;
    }

    return .{ .map = .{ .entries = output } };
}

fn cloneMapEntryWithValue(
    allocator: Allocator,
    key: []const u8,
    value: value_mod.Value,
) Allocator.Error!value_mod.MapEntry {
    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);

    return .{
        .key = owned_key,
        .value = try value.clone(allocator),
    };
}

fn evalMapHas(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const key = try expectString(args[1]);
    return .{ .boolean = input.entryByKey(key) != null };
}

fn evalMapGet(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const key = try expectString(args[1]);
    const entry = input.entryByKey(key) orelse return error.InvalidArgument;
    return try entry.value.clone(allocator);
}

fn evalMapGetOr(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 3) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const key = try expectString(args[1]);
    if (input.entryByKey(key)) |entry| return try entry.value.clone(allocator);
    return try args[2].clone(allocator);
}

fn evalMapKeys(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const output = try allocator.alloc(value_mod.Value, input.entries.len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (input.entries, 0..) |entry, index| {
        output[index] = .{ .string = try allocator.dupe(u8, entry.key) };
        initialized += 1;
    }

    return .{ .list = .{ .items = output } };
}

fn evalMapValues(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    const input = try expectMap(args[0]);
    const output = try allocator.alloc(value_mod.Value, input.entries.len);
    var initialized: usize = 0;
    errdefer {
        for (output[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(output);
    }

    for (input.entries, 0..) |entry, index| {
        output[index] = try entry.value.clone(allocator);
        initialized += 1;
    }

    return .{ .list = .{ .items = output } };
}

fn evalMapEq(args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return .{ .boolean = mapValuesEqual(try expectMap(args[0]), try expectMap(args[1])) };
}

fn evalTokensOf(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    return token_match.tokenizeValue(allocator, args[0]) catch |err| return mapTokenMatchError(err);
}

fn evalTokensJoin(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 1) return error.InvalidArgument;
    return token_match.joinValue(allocator, args[0]) catch |err| return mapTokenMatchError(err);
}

fn evalMatchTokens(allocator: Allocator, args: []const value_mod.Value) Error!value_mod.Value {
    if (args.len != 2) return error.InvalidArgument;
    return token_match.matchTokensValue(allocator, args[0], args[1]) catch |err| return mapTokenMatchError(err);
}

fn mapTokenMatchError(err: token_match.Error) Error {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidArgument => error.InvalidArgument,
        error.OutputTooLarge => error.OutputTooLarge,
        error.TypeMismatch => error.TypeMismatch,
    };
}

fn expectInteger(value: value_mod.Value) Error!u64 {
    return value.expectInteger() catch error.TypeMismatch;
}

fn expectString(value: value_mod.Value) Error![]const u8 {
    return value.expectString() catch error.TypeMismatch;
}

fn expectBytes(value: value_mod.Value) Error![]const u8 {
    return value.expectBytes() catch error.TypeMismatch;
}

fn expectList(value: value_mod.Value) Error!value_mod.ListValue {
    return value.expectList() catch error.TypeMismatch;
}

fn expectMap(value: value_mod.Value) Error!value_mod.MapValue {
    return value.expectMap() catch error.TypeMismatch;
}

fn mapEntryIndex(map: value_mod.MapValue, key: []const u8) ?usize {
    for (map.entries, 0..) |entry, index| {
        if (std.mem.eql(u8, entry.key, key)) return index;
    }
    return null;
}

fn expectU8(value: value_mod.Value) Error!u8 {
    const integer = try expectInteger(value);
    if (integer > std.math.maxInt(u8)) return error.InvalidApiInteger;
    return @intCast(integer);
}

fn expectUsize(value: value_mod.Value) Error!usize {
    const integer = try expectInteger(value);
    if (integer > std.math.maxInt(usize)) return error.InvalidApiInteger;
    return @intCast(integer);
}

fn replaceAll(allocator: Allocator, text: []const u8, needle: []const u8, replacement: []const u8) Error![]u8 {
    const replacement_count = std.mem.count(u8, text, needle);
    if (replacement_count == 0) return allocator.dupe(u8, text);
    const removed_len = std.math.mul(usize, replacement_count, needle.len) catch return error.OutputTooLarge;
    const added_len = std.math.mul(usize, replacement_count, replacement.len) catch return error.OutputTooLarge;
    const output_len = std.math.add(usize, text.len - removed_len, added_len) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    var read_index: usize = 0;
    var write_index: usize = 0;
    while (std.mem.indexOf(u8, text[read_index..], needle)) |relative_index| {
        const match_index = read_index + relative_index;
        const prefix = text[read_index..match_index];
        @memcpy(output[write_index .. write_index + prefix.len], prefix);
        write_index += prefix.len;
        @memcpy(output[write_index .. write_index + replacement.len], replacement);
        write_index += replacement.len;
        read_index = match_index + needle.len;
    }
    @memcpy(output[write_index..], text[read_index..]);
    return output;
}

fn bytesToHex(allocator: Allocator, bytes: []const u8) Error![]u8 {
    const output_len = std.math.mul(usize, bytes.len, 2) catch return error.OutputTooLarge;
    const output = try allocator.alloc(u8, output_len);
    for (bytes, 0..) |byte, index| {
        output[index * 2] = lower_hex[byte >> 4];
        output[index * 2 + 1] = lower_hex[byte & 0x0f];
    }
    return output;
}

const lower_hex = "0123456789abcdef";

fn hexNibble(byte: u8) Error!u8 {
    return switch (byte) {
        '0'...'9' => byte - '0',
        'a'...'f' => byte - 'a' + 10,
        'A'...'F' => byte - 'A' + 10,
        else => error.InvalidArgument,
    };
}

fn valuesEqual(left: value_mod.Value, right: value_mod.Value) bool {
    return switch (left) {
        .void => right == .void,
        .integer => |left_integer| switch (right) {
            .integer => |right_integer| left_integer.value == right_integer.value,
            else => false,
        },
        .float32 => |left_float| switch (right) {
            .float32 => |right_float| left_float == right_float,
            else => false,
        },
        .float64 => |left_float| switch (right) {
            .float64 => |right_float| left_float == right_float,
            else => false,
        },
        .boolean => |left_bool| switch (right) {
            .boolean => |right_bool| left_bool == right_bool,
            else => false,
        },
        .string => |left_text| switch (right) {
            .string => |right_text| std.mem.eql(u8, left_text, right_text),
            else => false,
        },
        .bytes => |left_bytes| switch (right) {
            .bytes => |right_bytes| std.mem.eql(u8, left_bytes, right_bytes),
            else => false,
        },
        .type => |left_type| switch (right) {
            .type => |right_type| left_type.index == right_type.index,
            else => false,
        },
        .@"struct" => |left_struct| switch (right) {
            .@"struct" => |right_struct| structValuesEqual(left_struct, right_struct),
            else => false,
        },
        .list => |left_list| switch (right) {
            .list => |right_list| listValuesEqual(left_list, right_list),
            else => false,
        },
        .map => |left_map| switch (right) {
            .map => |right_map| mapValuesEqual(left_map, right_map),
            else => false,
        },
    };
}

fn structValuesEqual(left: value_mod.StructValue, right: value_mod.StructValue) bool {
    if (left.type_id.index != right.type_id.index) return false;
    if (left.fields.len != right.fields.len) return false;
    for (left.fields, right.fields) |left_field, right_field| {
        if (!std.mem.eql(u8, left_field.name, right_field.name)) return false;
        if (!valuesEqual(left_field.value, right_field.value)) return false;
    }
    return true;
}

fn listValuesEqual(left: value_mod.ListValue, right: value_mod.ListValue) bool {
    if (left.items.len != right.items.len) return false;
    for (left.items, right.items) |left_item, right_item| {
        if (!valuesEqual(left_item, right_item)) return false;
    }
    return true;
}

fn mapValuesEqual(left: value_mod.MapValue, right: value_mod.MapValue) bool {
    if (left.entries.len != right.entries.len) return false;
    for (left.entries) |left_entry| {
        const right_entry = right.entryByKey(left_entry.key) orelse return false;
        if (!valuesEqual(left_entry.value, right_entry.value)) return false;
    }
    return true;
}

test "meta std string helpers cover ascii DSL operations" {
    var raw_name = [_]u8{ ' ', ' ', 'K', 'e', 'r', 'n', 'e', 'l', '6', '4', ' ', ' ' };
    var trimmed = try evalBuiltin(std.testing.allocator, "trim", &.{.{ .string = &raw_name }});
    defer trimmed.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("Kernel64", try trimmed.expectString());

    var lowered = try evalBuiltin(std.testing.allocator, "lower", &.{trimmed});
    defer lowered.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("kernel64", try lowered.expectString());

    var uppered = try evalBuiltin(std.testing.allocator, "upper", &.{lowered});
    defer uppered.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("KERNEL64", try uppered.expectString());

    var replace_text = [_]u8{ 'a', ',', 'b', ',', 'c' };
    var replace_needle = [_]u8{','};
    var replace_replacement = [_]u8{'|'};
    var replaced = try evalBuiltin(std.testing.allocator, "replace", &.{
        .{ .string = &replace_text },
        .{ .string = &replace_needle },
        .{ .string = &replace_replacement },
    });
    defer replaced.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("a|b|c", try replaced.expectString());
}

test "meta std split join helpers bridge strings and lists" {
    var csv = [_]u8{ 'a', ',', 'b', ',', 'c' };
    var comma = [_]u8{','};
    var parts = try evalBuiltin(std.testing.allocator, "split", &.{
        .{ .string = &csv },
        .{ .string = &comma },
    });
    defer parts.deinit(std.testing.allocator);

    const list = try parts.expectList();
    try std.testing.expectEqual(@as(usize, 3), list.items.len);
    try std.testing.expectEqualStrings("a", try list.items[0].expectString());
    try std.testing.expectEqualStrings("b", try list.items[1].expectString());
    try std.testing.expectEqualStrings("c", try list.items[2].expectString());

    var dash = [_]u8{'-'};
    var joined = try evalBuiltin(std.testing.allocator, "join", &.{
        parts,
        .{ .string = &dash },
    });
    defer joined.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("a-b-c", try joined.expectString());
}

test "meta std symbol join converts scalar parts" {
    var prefix = [_]u8{ 'v', 'e', 'c', '_' };
    var name = [_]u8{ 'p', 'u', 's', 'h' };
    var separator = [_]u8{ '_', '_' };
    var joined = try evalBuiltin(std.testing.allocator, "sym.join", &.{
        .{ .string = &prefix },
        value_mod.Value.int(32),
        .{ .string = &separator },
        .{ .string = &name },
    });
    defer joined.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("vec_32__push", try joined.expectString());
}

test "meta std split join covers empty and unmatched strings" {
    var empty_text = [_]u8{};
    var comma = [_]u8{','};
    var empty_parts = try evalBuiltin(std.testing.allocator, "split", &.{
        .{ .string = &empty_text },
        .{ .string = &comma },
    });
    defer empty_parts.deinit(std.testing.allocator);
    const empty_list = try empty_parts.expectList();
    try std.testing.expectEqual(@as(usize, 1), empty_list.items.len);
    try std.testing.expectEqualStrings("", try empty_list.items[0].expectString());

    var word = [_]u8{ 'k', 'e', 'r', 'n', 'e', 'l' };
    var unmatched = try evalBuiltin(std.testing.allocator, "split", &.{
        .{ .string = &word },
        .{ .string = &comma },
    });
    defer unmatched.deinit(std.testing.allocator);
    const unmatched_list = try unmatched.expectList();
    try std.testing.expectEqual(@as(usize, 1), unmatched_list.items.len);
    try std.testing.expectEqualStrings("kernel", try unmatched_list.items[0].expectString());

    var empty_join = try evalBuiltin(std.testing.allocator, "join", &.{
        .{ .list = .{ .items = try std.testing.allocator.alloc(value_mod.Value, 0) } },
        .{ .string = &comma },
    });
    defer empty_join.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("", try empty_join.expectString());
}

test "meta std bytes helpers construct and patch byte buffers" {
    var hex_text = [_]u8{ '4', 'b', '4', '5', '5', '2', '4', 'e' };
    var data = try evalBuiltin(std.testing.allocator, "bytes.from_hex", &.{.{ .string = &hex_text }});
    defer data.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0x4b, 0x45, 0x52, 0x4e }, try data.expectBytes());

    var pushed = try evalBuiltin(std.testing.allocator, "bytes.push", &.{ data, value_mod.Value.int(0x21) });
    defer pushed.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0x4b, 0x45, 0x52, 0x4e, 0x21 }, try pushed.expectBytes());

    var replacement = [_]u8{ 0xaa, 0xbb };
    var replaced = try evalBuiltin(std.testing.allocator, "bytes.replace", &.{
        pushed,
        value_mod.Value.int(1),
        value_mod.Value.int(2),
        .{ .bytes = &replacement },
    });
    defer replaced.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0x4b, 0xaa, 0xbb, 0x4e, 0x21 }, try replaced.expectBytes());
}

test "meta std list helpers own clone and compare nested values" {
    var text = [_]u8{ 'O', 'K' };
    var data = [_]u8{ 0x34, 0x12 };
    var nested = try evalBuiltin(std.testing.allocator, "list.of", &.{
        value_mod.Value.int(0xaa),
        .{ .string = &text },
        .{ .bytes = &data },
    });
    defer nested.deinit(std.testing.allocator);

    var base = try evalBuiltin(std.testing.allocator, "list.of", &.{
        value_mod.Value.int(1),
        nested,
    });
    defer base.deinit(std.testing.allocator);

    var pushed = try evalBuiltin(std.testing.allocator, "list.push", &.{ base, value_mod.Value.int(3) });
    defer pushed.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 3), try (try evalBuiltin(std.testing.allocator, "len", &.{pushed})).expectInteger());

    var got = try evalBuiltin(std.testing.allocator, "list.get", &.{ pushed, value_mod.Value.int(1) });
    defer got.deinit(std.testing.allocator);
    const got_list = try got.expectList();
    try std.testing.expectEqual(@as(u64, 0xaa), try got_list.items[0].expectInteger());
    try std.testing.expectEqualStrings("OK", try got_list.items[1].expectString());
    try std.testing.expectEqualSlices(u8, &.{ 0x34, 0x12 }, try got_list.items[2].expectBytes());

    var replacement = try evalBuiltin(std.testing.allocator, "list.of", &.{value_mod.Value.int(9)});
    defer replacement.deinit(std.testing.allocator);
    var set = try evalBuiltin(std.testing.allocator, "list.set", &.{ pushed, value_mod.Value.int(1), replacement });
    defer set.deinit(std.testing.allocator);
    var slice = try evalBuiltin(std.testing.allocator, "list.slice", &.{ set, value_mod.Value.int(1), value_mod.Value.int(2) });
    defer slice.deinit(std.testing.allocator);
    var expected = try evalBuiltin(std.testing.allocator, "list.of", &.{ replacement, value_mod.Value.int(3) });
    defer expected.deinit(std.testing.allocator);
    const eq = try evalBuiltin(std.testing.allocator, "list.eq", &.{ slice, expected });
    try std.testing.expect(try eq.expectBoolean());
}

test "meta std map helpers own clone and compare key values" {
    var empty = try evalBuiltin(std.testing.allocator, "map.new", &.{});
    defer empty.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 0), try (try evalBuiltin(std.testing.allocator, "len", &.{empty})).expectInteger());

    var key_arch = [_]u8{ 'a', 'r', 'c', 'h' };
    var value_x64 = [_]u8{ 'x', '6', '4' };
    var with_arch = try evalBuiltin(std.testing.allocator, "map.set", &.{
        empty,
        .{ .string = &key_arch },
        .{ .string = &value_x64 },
    });
    defer with_arch.deinit(std.testing.allocator);

    var key_mode = [_]u8{ 'm', 'o', 'd', 'e' };
    var with_mode = try evalBuiltin(std.testing.allocator, "map.set", &.{
        with_arch,
        .{ .string = &key_mode },
        value_mod.Value.int(64),
    });
    defer with_mode.deinit(std.testing.allocator);

    var value_rv64 = [_]u8{ 'r', 'v', '6', '4' };
    var overwritten = try evalBuiltin(std.testing.allocator, "map.set", &.{
        with_mode,
        .{ .string = &key_arch },
        .{ .string = &value_rv64 },
    });
    defer overwritten.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 2), try (try evalBuiltin(std.testing.allocator, "len", &.{overwritten})).expectInteger());
    try std.testing.expect(try (try evalBuiltin(std.testing.allocator, "map.has", &.{
        overwritten,
        .{ .string = &key_arch },
    })).expectBoolean());

    var missing_key = [_]u8{ 'm', 'i', 's', 's' };
    try std.testing.expect(!try (try evalBuiltin(std.testing.allocator, "map.has", &.{
        overwritten,
        .{ .string = &missing_key },
    })).expectBoolean());

    var got = try evalBuiltin(std.testing.allocator, "map.get", &.{
        overwritten,
        .{ .string = &key_arch },
    });
    defer got.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("rv64", try got.expectString());

    var fallback_bytes = [_]u8{0xff};
    var fallback = try evalBuiltin(std.testing.allocator, "map.get_or", &.{
        overwritten,
        .{ .string = &missing_key },
        .{ .bytes = &fallback_bytes },
    });
    defer fallback.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{0xff}, try fallback.expectBytes());

    var keys = try evalBuiltin(std.testing.allocator, "map.keys", &.{overwritten});
    defer keys.deinit(std.testing.allocator);
    const key_list = try keys.expectList();
    try std.testing.expectEqual(@as(usize, 2), key_list.items.len);
    try std.testing.expectEqualStrings("arch", try key_list.items[0].expectString());
    try std.testing.expectEqualStrings("mode", try key_list.items[1].expectString());

    var values = try evalBuiltin(std.testing.allocator, "map.values", &.{overwritten});
    defer values.deinit(std.testing.allocator);
    const value_list = try values.expectList();
    try std.testing.expectEqualStrings("rv64", try value_list.items[0].expectString());
    try std.testing.expectEqual(@as(u64, 64), try value_list.items[1].expectInteger());

    var left0 = try evalBuiltin(std.testing.allocator, "map.new", &.{});
    defer left0.deinit(std.testing.allocator);
    var key_a = [_]u8{'a'};
    var left1 = try evalBuiltin(std.testing.allocator, "map.set", &.{ left0, .{ .string = &key_a }, value_mod.Value.int(1) });
    defer left1.deinit(std.testing.allocator);
    var key_b = [_]u8{'b'};
    var left2 = try evalBuiltin(std.testing.allocator, "map.set", &.{ left1, .{ .string = &key_b }, value_mod.Value.int(2) });
    defer left2.deinit(std.testing.allocator);

    var right0 = try evalBuiltin(std.testing.allocator, "map.new", &.{});
    defer right0.deinit(std.testing.allocator);
    var right1 = try evalBuiltin(std.testing.allocator, "map.set", &.{ right0, .{ .string = &key_b }, value_mod.Value.int(2) });
    defer right1.deinit(std.testing.allocator);
    var right2 = try evalBuiltin(std.testing.allocator, "map.set", &.{ right1, .{ .string = &key_a }, value_mod.Value.int(1) });
    defer right2.deinit(std.testing.allocator);

    try std.testing.expect(try (try evalBuiltin(std.testing.allocator, "map.eq", &.{ left2, right2 })).expectBoolean());
}

test "meta std rejects invalid map helper arguments" {
    var empty = try evalBuiltin(std.testing.allocator, "map.new", &.{});
    defer empty.deinit(std.testing.allocator);

    var missing_key = [_]u8{ 'm', 'i', 's', 's' };
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "map.get", &.{
        empty,
        .{ .string = &missing_key },
    }));
    try std.testing.expectError(error.TypeMismatch, evalBuiltin(std.testing.allocator, "map.set", &.{
        empty,
        value_mod.Value.int(1),
        value_mod.Value.int(2),
    }));
    try std.testing.expectError(error.TypeMismatch, evalBuiltin(std.testing.allocator, "map.eq", &.{
        empty,
        value_mod.Value.int(1),
    }));
}

test "meta std rejects invalid list helper arguments" {
    var empty = try evalBuiltin(std.testing.allocator, "list.new", &.{});
    defer empty.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "list.get", &.{
        empty,
        value_mod.Value.int(0),
    }));
    try std.testing.expectError(error.TypeMismatch, evalBuiltin(std.testing.allocator, "list.push", &.{
        value_mod.Value.int(1),
        value_mod.Value.int(2),
    }));

    var one = try evalBuiltin(std.testing.allocator, "list.of", &.{value_mod.Value.int(1)});
    defer one.deinit(std.testing.allocator);
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "list.set", &.{
        one,
        value_mod.Value.int(1),
        value_mod.Value.int(2),
    }));
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "list.slice", &.{
        one,
        value_mod.Value.int(0),
        value_mod.Value.int(2),
    }));
    try std.testing.expectError(error.TypeMismatch, evalBuiltin(std.testing.allocator, "list.eq", &.{
        one,
        value_mod.Value.int(1),
    }));
}

test "meta std rejects invalid byte helper arguments" {
    var empty_bytes = [_]u8{};
    try std.testing.expectError(error.InvalidApiInteger, evalBuiltin(std.testing.allocator, "bytes.push", &.{
        .{ .bytes = &empty_bytes },
        value_mod.Value.int(256),
    }));
    var odd_hex = [_]u8{ 'a', 'b', 'c' };
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "bytes.from_hex", &.{.{ .string = &odd_hex }}));
    var text = [_]u8{ 'a', 'b', 'c' };
    var empty_needle = [_]u8{};
    var replacement = [_]u8{'x'};
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "replace", &.{
        .{ .string = &text },
        .{ .string = &empty_needle },
        .{ .string = &replacement },
    }));
    try std.testing.expectError(error.InvalidArgument, evalBuiltin(std.testing.allocator, "split", &.{
        .{ .string = &text },
        .{ .string = &empty_needle },
    }));
    var separator = [_]u8{','};
    var non_string_list: value_mod.Value = .{
        .list = .{ .items = try std.testing.allocator.dupe(value_mod.Value, &.{value_mod.Value.int(1)}) },
    };
    defer non_string_list.deinit(std.testing.allocator);
    try std.testing.expectError(error.TypeMismatch, evalBuiltin(std.testing.allocator, "join", &.{
        non_string_list,
        .{ .string = &separator },
    }));
}

test "meta std reports explicit types and lengths" {
    var text = try evalBuiltin(std.testing.allocator, "to_string", &.{value_mod.Value.int(123)});
    defer text.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("123", try text.expectString());

    var raw_bytes = [_]u8{ 0x4b, 0x45 };
    var hex = try evalBuiltin(std.testing.allocator, "to_string", &.{.{ .bytes = &raw_bytes }});
    defer hex.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("4b45", try hex.expectString());

    const fake_type: types.TypeId = .{ .index = 7 };
    var type_text = try evalBuiltin(std.testing.allocator, "to_string", &.{.{ .type = fake_type }});
    defer type_text.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("type#7", try type_text.expectString());
}
