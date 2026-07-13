const std = @import("std");

const types = @import("types.zig");

pub const Mutability = enum {
    @"const",
    let,
};

/// Compile-time Meta value categories. These describe values produced by
/// expression evaluation and Meta execution; binary layout types live in
/// `types.zig` and are referenced through `.type` values.
pub const ValueType = enum {
    void,
    boolean,
    integer,
    f32,
    f64,
    string,
    bytes,
    type,
    @"struct",
    list,
    map,
};

pub const MutableValueLookup = union(enum) {
    missing,
    immutable,
    value: *Value,
};

pub fn valueTypeFromName(name: []const u8) ?ValueType {
    if (std.mem.eql(u8, name, "void")) return .void;
    if (std.mem.eql(u8, name, "bool")) return .boolean;
    if (std.mem.eql(u8, name, "boolean")) return .boolean;
    if (std.mem.eql(u8, name, "integer")) return .integer;
    if (std.mem.eql(u8, name, "f32")) return .f32;
    if (std.mem.eql(u8, name, "f64")) return .f64;
    if (std.mem.eql(u8, name, "string")) return .string;
    if (std.mem.eql(u8, name, "bytes")) return .bytes;
    if (std.mem.eql(u8, name, "type")) return .type;
    if (std.mem.eql(u8, name, "struct")) return .@"struct";
    if (std.mem.eql(u8, name, "list")) return .list;
    if (std.mem.eql(u8, name, "map")) return .map;
    return null;
}

pub fn formatFloatLiteral(allocator: std.mem.Allocator, value: anytype) std.mem.Allocator.Error![]u8 {
    const text = try std.fmt.allocPrint(allocator, "{d}", .{value});
    if (std.mem.indexOfAny(u8, text, ".eE") != null) return text;
    defer allocator.free(text);
    return std.fmt.allocPrint(allocator, "{s}.0", .{text});
}

pub fn formatFloat32Literal(allocator: std.mem.Allocator, value: f32) std.mem.Allocator.Error![]u8 {
    const literal = try formatFloatLiteral(allocator, value);
    defer allocator.free(literal);
    return std.fmt.allocPrint(allocator, "f32({s})", .{literal});
}

/// Minimal integer value facts for Meta runtime integers. `type_id == null`
/// means the value is still an untyped compile-time integer; type checking may
/// attach a layout integer type after range validation.
pub const IntegerValue = struct {
    value: u64,
    type_id: ?types.TypeId = null,

    pub fn untyped(value: u64) IntegerValue {
        return .{ .value = value };
    }

    pub fn typed(value: u64, type_id: types.TypeId) IntegerValue {
        return .{
            .value = value,
            .type_id = type_id,
        };
    }
};

pub const StructFieldValue = struct {
    name: []u8,
    value: Value,

    pub fn deinit(self: *StructFieldValue, allocator: std.mem.Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: StructFieldValue, allocator: std.mem.Allocator) std.mem.Allocator.Error!StructFieldValue {
        const owned_name = try allocator.dupe(u8, self.name);
        errdefer allocator.free(owned_name);

        return .{
            .name = owned_name,
            .value = try self.value.clone(allocator),
        };
    }
};

pub const StructValue = struct {
    type_id: types.TypeId,
    fields: []StructFieldValue,

    pub fn deinit(self: *StructValue, allocator: std.mem.Allocator) void {
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }

    pub fn clone(self: StructValue, allocator: std.mem.Allocator) std.mem.Allocator.Error!StructValue {
        const fields = try allocator.alloc(StructFieldValue, self.fields.len);
        var fields_len: usize = 0;
        errdefer {
            for (fields[0..fields_len]) |*field| {
                field.deinit(allocator);
            }
            allocator.free(fields);
        }

        for (self.fields, 0..) |field, index| {
            fields[index] = try field.clone(allocator);
            fields_len += 1;
        }

        return .{
            .type_id = self.type_id,
            .fields = fields,
        };
    }

    pub fn fieldByName(self: *const StructValue, name: []const u8) ?*const StructFieldValue {
        for (self.fields) |*field| {
            if (std.mem.eql(u8, field.name, name)) return field;
        }
        return null;
    }

    pub fn fieldValueByName(self: *const StructValue, allocator: std.mem.Allocator, name: []const u8) std.mem.Allocator.Error!?Value {
        const field = self.fieldByName(name) orelse return null;
        return try field.value.clone(allocator);
    }
};

pub const ListValue = struct {
    items: []Value,

    pub const PushError = std.mem.Allocator.Error || error{CollectionTooLarge};
    pub const SetError = std.mem.Allocator.Error || error{IndexOutOfBounds};

    pub fn deinit(self: *ListValue, allocator: std.mem.Allocator) void {
        for (self.items) |*item| {
            item.deinit(allocator);
        }
        allocator.free(self.items);
        self.* = undefined;
    }

    pub fn clone(self: ListValue, allocator: std.mem.Allocator) std.mem.Allocator.Error!ListValue {
        return .{
            .items = try cloneValueSlice(allocator, self.items),
        };
    }

    pub fn pushCloned(self: *ListValue, allocator: std.mem.Allocator, item: Value) PushError!void {
        var cloned = try item.clone(allocator);
        errdefer cloned.deinit(allocator);

        const old_len = self.items.len;
        const new_len = std.math.add(usize, old_len, 1) catch return error.CollectionTooLarge;
        self.items = try allocator.realloc(self.items, new_len);
        self.items[old_len] = cloned;
    }

    pub fn setCloned(self: *ListValue, allocator: std.mem.Allocator, index: usize, item: Value) SetError!void {
        if (index >= self.items.len) return error.IndexOutOfBounds;
        var replacement = try item.clone(allocator);
        errdefer replacement.deinit(allocator);

        var previous = self.items[index];
        self.items[index] = replacement;
        previous.deinit(allocator);
    }
};

pub const MapEntry = struct {
    key: []u8,
    value: Value,

    pub fn deinit(self: *MapEntry, allocator: std.mem.Allocator) void {
        allocator.free(self.key);
        self.value.deinit(allocator);
        self.* = undefined;
    }

    pub fn clone(self: MapEntry, allocator: std.mem.Allocator) std.mem.Allocator.Error!MapEntry {
        const owned_key = try allocator.dupe(u8, self.key);
        errdefer allocator.free(owned_key);

        return .{
            .key = owned_key,
            .value = try self.value.clone(allocator),
        };
    }
};

pub const MapValue = struct {
    entries: []MapEntry,

    pub const MutationError = std.mem.Allocator.Error || error{CollectionTooLarge};

    pub fn deinit(self: *MapValue, allocator: std.mem.Allocator) void {
        for (self.entries) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(self.entries);
        self.* = undefined;
    }

    pub fn clone(self: MapValue, allocator: std.mem.Allocator) std.mem.Allocator.Error!MapValue {
        const entries = try allocator.alloc(MapEntry, self.entries.len);
        var entries_len: usize = 0;
        errdefer {
            for (entries[0..entries_len]) |*entry| {
                entry.deinit(allocator);
            }
            allocator.free(entries);
        }

        for (self.entries, 0..) |entry, index| {
            entries[index] = try entry.clone(allocator);
            entries_len += 1;
        }

        return .{ .entries = entries };
    }

    pub fn entryByKey(self: MapValue, key: []const u8) ?*const MapEntry {
        const index = self.entryIndexByKey(key) orelse return null;
        return &self.entries[index];
    }

    pub fn setCloned(self: *MapValue, allocator: std.mem.Allocator, key: []const u8, value: Value) MutationError!void {
        if (self.entryIndexByKey(key)) |index| {
            var replacement = try value.clone(allocator);
            errdefer replacement.deinit(allocator);

            var previous = self.entries[index].value;
            self.entries[index].value = replacement;
            previous.deinit(allocator);
            return;
        }

        const owned_key = try allocator.dupe(u8, key);
        errdefer allocator.free(owned_key);
        var owned_value = try value.clone(allocator);
        errdefer owned_value.deinit(allocator);

        const old_len = self.entries.len;
        const new_len = std.math.add(usize, old_len, 1) catch return error.CollectionTooLarge;
        self.entries = try allocator.realloc(self.entries, new_len);
        self.entries[old_len] = .{
            .key = owned_key,
            .value = owned_value,
        };
    }

    fn entryIndexByKey(self: MapValue, key: []const u8) ?usize {
        for (self.entries, 0..) |entry, index| {
            if (std.mem.eql(u8, entry.key, key)) return index;
        }
        return null;
    }
};

pub const Value = union(enum) {
    void,
    integer: IntegerValue,
    float32: f32,
    float64: f64,
    boolean: bool,
    string: []u8,
    bytes: []u8,
    type: types.TypeId,
    @"struct": StructValue,
    list: ListValue,
    map: MapValue,

    pub fn int(value: u64) Value {
        return .{ .integer = IntegerValue.untyped(value) };
    }

    pub fn typedInteger(value: u64, type_id: types.TypeId) Value {
        return .{ .integer = IntegerValue.typed(value, type_id) };
    }

    pub fn deinit(self: *Value, allocator: std.mem.Allocator) void {
        switch (self.*) {
            .void, .integer, .float32, .float64, .boolean, .type => {},
            .string, .bytes => |text| allocator.free(text),
            .@"struct" => |*struct_value| struct_value.deinit(allocator),
            .list => |*list| list.deinit(allocator),
            .map => |*map| map.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn clone(self: Value, allocator: std.mem.Allocator) std.mem.Allocator.Error!Value {
        return switch (self) {
            .void => .void,
            .integer => |value| .{ .integer = value },
            .float32 => |value| .{ .float32 = value },
            .float64 => |value| .{ .float64 = value },
            .boolean => |value| .{ .boolean = value },
            .string => |text| .{ .string = try allocator.dupe(u8, text) },
            .bytes => |data| .{ .bytes = try allocator.dupe(u8, data) },
            .type => |id| .{ .type = id },
            .@"struct" => |struct_value| .{ .@"struct" = try struct_value.clone(allocator) },
            .list => |list| .{ .list = try list.clone(allocator) },
            .map => |map| .{ .map = try map.clone(allocator) },
        };
    }

    pub fn valueType(self: Value) ValueType {
        return switch (self) {
            .void => .void,
            .integer => .integer,
            .float32 => .f32,
            .float64 => .f64,
            .boolean => .boolean,
            .string => .string,
            .bytes => .bytes,
            .type => .type,
            .@"struct" => .@"struct",
            .list => .list,
            .map => .map,
        };
    }

    pub fn expectInteger(self: Value) !u64 {
        return switch (self) {
            .integer => |integer| integer.value,
            .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => error.ExpectedInteger,
        };
    }

    pub fn expectIntegerValue(self: Value) !IntegerValue {
        return switch (self) {
            .integer => |integer| integer,
            .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => error.ExpectedInteger,
        };
    }

    pub fn expectFloat32(self: Value) !f32 {
        return switch (self) {
            .float32 => |value| value,
            .void, .integer, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => error.ExpectedFloat32,
        };
    }

    pub fn expectFloat64(self: Value) !f64 {
        return switch (self) {
            .float64 => |value| value,
            .void, .integer, .float32, .boolean, .string, .bytes, .type, .@"struct", .list, .map => error.ExpectedFloat64,
        };
    }

    pub fn expectBoolean(self: Value) !bool {
        return switch (self) {
            .boolean => |value| value,
            .void, .integer, .float32, .float64, .string, .bytes, .type, .@"struct", .list, .map => error.ExpectedBoolean,
        };
    }

    pub fn expectString(self: Value) ![]const u8 {
        return switch (self) {
            .string => |text| text,
            .void, .integer, .float32, .float64, .boolean, .bytes, .type, .@"struct", .list, .map => error.ExpectedString,
        };
    }

    pub fn expectBytes(self: Value) ![]const u8 {
        return switch (self) {
            .bytes => |data| data,
            .void, .integer, .float32, .float64, .boolean, .string, .type, .@"struct", .list, .map => error.ExpectedBytes,
        };
    }

    pub fn expectType(self: Value) !types.TypeId {
        return switch (self) {
            .type => |id| id,
            .void, .integer, .float32, .float64, .boolean, .string, .bytes, .@"struct", .list, .map => error.ExpectedType,
        };
    }

    pub fn expectStruct(self: Value) !StructValue {
        return switch (self) {
            .@"struct" => |struct_value| struct_value,
            .void, .integer, .float32, .float64, .boolean, .string, .bytes, .type, .list, .map => error.ExpectedStruct,
        };
    }

    pub fn expectList(self: Value) !ListValue {
        return switch (self) {
            .list => |list| list,
            .void, .integer, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .map => error.ExpectedList,
        };
    }

    pub fn expectMap(self: Value) !MapValue {
        return switch (self) {
            .map => |map| map,
            .void, .integer, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list => error.ExpectedMap,
        };
    }
};

pub fn cloneValueSlice(allocator: std.mem.Allocator, values: []const Value) std.mem.Allocator.Error![]Value {
    const cloned = try allocator.alloc(Value, values.len);
    var cloned_len: usize = 0;
    errdefer {
        for (cloned[0..cloned_len]) |*value| {
            value.deinit(allocator);
        }
        allocator.free(cloned);
    }

    for (values, 0..) |value, index| {
        cloned[index] = try value.clone(allocator);
        cloned_len += 1;
    }
    return cloned;
}

pub const PackError = std.mem.Allocator.Error || error{
    ExpectedStruct,
    IntegerOverflow,
    InvalidApiArgument,
    InvalidApiInteger,
    InvalidIntegerBits,
    InvalidType,
    MissingStructFieldValue,
    FragmentTooLarge,
};

pub fn packStructValue(
    allocator: std.mem.Allocator,
    store: *const types.TypeStore,
    struct_value: StructValue,
) PackError![]u8 {
    const layout = try store.layoutOf(struct_value.type_id);
    if (layout.size > std.math.maxInt(usize)) return error.FragmentTooLarge;

    const bytes = try allocator.alloc(u8, @intCast(layout.size));
    errdefer allocator.free(bytes);
    @memset(bytes, 0);

    try packAggregateInto(store, bytes, 0, struct_value);
    return bytes;
}

fn packAggregateInto(
    store: *const types.TypeStore,
    bytes: []u8,
    base_offset: u64,
    aggregate_value: StructValue,
) PackError!void {
    const stored_type = try store.get(aggregate_value.type_id);
    switch (stored_type.*) {
        .@"struct" => |struct_type| {
            if (aggregate_value.fields.len != struct_type.fields.items.len) return error.InvalidApiArgument;
            for (struct_type.fields.items) |field| {
                const field_value = aggregate_value.fieldByName(field.name) orelse return error.MissingStructFieldValue;
                try writeFieldValue(store, bytes, base_offset, field, field_value.value);
            }
        },
        .@"union" => |union_type| {
            if (aggregate_value.fields.len != 1) return error.InvalidApiArgument;
            const active_value = aggregate_value.fields[0];
            const active_field = union_type.fieldByName(active_value.name) orelse return error.InvalidApiArgument;
            try writeFieldValue(store, bytes, base_offset, active_field.*, active_value.value);
        },
        .void, .int, .array, .pointer => return error.ExpectedStruct,
    }
}

fn writeFieldValue(
    store: *const types.TypeStore,
    bytes: []u8,
    base_offset: u64,
    field: types.StructField,
    value: Value,
) PackError!void {
    const ty = try store.get(field.ty);
    return switch (ty.*) {
        .int => |int_type| {
            const integer = switch (value) {
                .integer => |stored| stored.value,
                .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            };
            try writeIntegerField(bytes, base_offset, field, integer, int_type);
        },
        .@"struct", .@"union" => {
            const nested = switch (value) {
                .@"struct" => |stored| stored,
                .void, .integer, .float32, .float64, .boolean, .string, .bytes, .type, .list, .map => return error.InvalidApiArgument,
            };
            if (nested.type_id.index != field.ty.index) return error.InvalidType;
            const nested_offset = std.math.add(u64, base_offset, field.offset) catch return error.IntegerOverflow;
            try packAggregateInto(store, bytes, nested_offset, nested);
        },
        .void, .array, .pointer => error.InvalidType,
    };
}

fn writeIntegerField(
    bytes: []u8,
    base_offset: u64,
    field: types.StructField,
    value: u64,
    int_type: types.IntType,
) PackError!void {
    try validateIntegerForIntType(value, int_type);

    const absolute_offset = std.math.add(u64, base_offset, field.offset) catch return error.IntegerOverflow;
    if (absolute_offset > std.math.maxInt(usize)) return error.FragmentTooLarge;
    const offset: usize = @intCast(absolute_offset);
    switch (int_type.bits) {
        8 => {
            if (offset >= bytes.len) return error.FragmentTooLarge;
            bytes[offset] = @intCast(value);
        },
        16 => {
            if (offset > bytes.len or 2 > bytes.len - offset) return error.FragmentTooLarge;
            std.mem.writeInt(u16, bytes[offset .. offset + 2][0..2], @intCast(value), .little);
        },
        32 => {
            if (offset > bytes.len or 4 > bytes.len - offset) return error.FragmentTooLarge;
            std.mem.writeInt(u32, bytes[offset .. offset + 4][0..4], @intCast(value), .little);
        },
        64 => {
            if (offset > bytes.len or 8 > bytes.len - offset) return error.FragmentTooLarge;
            std.mem.writeInt(u64, bytes[offset .. offset + 8][0..8], value, .little);
        },
        else => return error.InvalidIntegerBits,
    }
}

pub fn validateIntegerForIntType(value: u64, int_type: types.IntType) PackError!void {
    const bits = int_type.bits;
    if (bits == 0) return error.InvalidIntegerBits;
    if (bits > @bitSizeOf(u64)) return error.InvalidIntegerBits;

    const max_value = if (int_type.signedness == .signed)
        if (bits == @bitSizeOf(u64))
            @as(u64, @intCast(std.math.maxInt(i64)))
        else
            (@as(u64, 1) << @intCast(bits - 1)) - 1
    else if (bits == @bitSizeOf(u64))
        std.math.maxInt(u64)
    else
        (@as(u64, 1) << @intCast(bits)) - 1;

    if (value > max_value) return error.InvalidApiInteger;
}

test "value stores integer bindings" {
    const value = Value.int(0x40);
    try std.testing.expectEqual(@as(u64, 0x40), try value.expectInteger());
}

test "value stores typed integer facts without changing integer API" {
    const type_id: types.TypeId = .{ .index = 3 };
    const value = Value.typedInteger(0xff, type_id);
    const integer = try value.expectIntegerValue();

    try std.testing.expectEqual(@as(u64, 0xff), try value.expectInteger());
    try std.testing.expectEqual(@as(u32, 3), integer.type_id.?.index);
    try std.testing.expectEqual(ValueType.integer, value.valueType());
}

test "value stores boolean bindings" {
    const value: Value = .{ .boolean = true };
    try std.testing.expectEqual(true, try value.expectBoolean());
    try std.testing.expectEqual(ValueType.boolean, value.valueType());
}

test "value type names are Meta-only names" {
    try std.testing.expectEqual(ValueType.integer, valueTypeFromName("integer").?);
    try std.testing.expect(valueTypeFromName("u64") == null);
}

test "float formatting remains parseable as a float" {
    const whole = try formatFloatLiteral(std.testing.allocator, @as(f64, 1.0));
    defer std.testing.allocator.free(whole);
    try std.testing.expectEqualStrings("1.0", whole);

    const typed = try formatFloat32Literal(std.testing.allocator, @as(f32, -0.0));
    defer std.testing.allocator.free(typed);
    try std.testing.expectEqualStrings("f32(-0.0)", typed);
}

test "value owns string bindings" {
    var value: Value = .{
        .string = try std.testing.allocator.dupe(u8, "demo"),
    };
    defer value.deinit(std.testing.allocator);

    switch (value) {
        .string => |text| try std.testing.expectEqualStrings("demo", text),
        else => return error.UnexpectedValue,
    }
}

test "value clones owned bytes without aliasing" {
    var value: Value = .{
        .bytes = try std.testing.allocator.dupe(u8, &.{ 0xaa, 0xbb }),
    };
    defer value.deinit(std.testing.allocator);

    var cloned = try value.clone(std.testing.allocator);
    defer cloned.deinit(std.testing.allocator);

    const cloned_bytes = try cloned.expectBytes();
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, cloned_bytes);
    switch (value) {
        .bytes => |original| try std.testing.expect(original.ptr != cloned_bytes.ptr),
        else => return error.UnexpectedValue,
    }
}

test "value owns and clones nested list bindings" {
    var value: Value = .{
        .list = .{
            .items = try std.testing.allocator.dupe(Value, &.{
                Value.int(1),
                .{ .string = try std.testing.allocator.dupe(u8, "item") },
                .{ .bytes = try std.testing.allocator.dupe(u8, &.{ 0xaa, 0xbb }) },
                .{ .list = .{ .items = try std.testing.allocator.dupe(Value, &.{Value.int(2)}) } },
            }),
        },
    };
    defer value.deinit(std.testing.allocator);

    var cloned = try value.clone(std.testing.allocator);
    defer cloned.deinit(std.testing.allocator);

    const original_list = try value.expectList();
    const cloned_list = try cloned.expectList();
    try std.testing.expectEqual(@as(usize, 4), cloned_list.items.len);
    try std.testing.expect(original_list.items.ptr != cloned_list.items.ptr);
    try std.testing.expectEqual(@as(u64, 1), try cloned_list.items[0].expectInteger());
    try std.testing.expectEqualStrings("item", try cloned_list.items[1].expectString());
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, try cloned_list.items[2].expectBytes());

    const original_nested = try original_list.items[3].expectList();
    const cloned_nested = try cloned_list.items[3].expectList();
    try std.testing.expect(original_nested.items.ptr != cloned_nested.items.ptr);
    try std.testing.expectEqual(@as(u64, 2), try cloned_nested.items[0].expectInteger());
}

test "value owns and clones nested map bindings" {
    var value: Value = .{
        .map = .{
            .entries = try std.testing.allocator.dupe(MapEntry, &.{
                .{
                    .key = try std.testing.allocator.dupe(u8, "name"),
                    .value = .{ .string = try std.testing.allocator.dupe(u8, "demo") },
                },
                .{
                    .key = try std.testing.allocator.dupe(u8, "data"),
                    .value = .{ .bytes = try std.testing.allocator.dupe(u8, &.{ 0xaa, 0xbb }) },
                },
                .{
                    .key = try std.testing.allocator.dupe(u8, "nested"),
                    .value = .{
                        .map = .{
                            .entries = try std.testing.allocator.dupe(MapEntry, &.{
                                .{
                                    .key = try std.testing.allocator.dupe(u8, "items"),
                                    .value = .{ .list = .{ .items = try std.testing.allocator.dupe(Value, &.{Value.int(2)}) } },
                                },
                            }),
                        },
                    },
                },
            }),
        },
    };
    defer value.deinit(std.testing.allocator);

    var cloned = try value.clone(std.testing.allocator);
    defer cloned.deinit(std.testing.allocator);

    const original_map = try value.expectMap();
    const cloned_map = try cloned.expectMap();
    try std.testing.expectEqual(@as(usize, 3), cloned_map.entries.len);
    try std.testing.expect(original_map.entries.ptr != cloned_map.entries.ptr);
    try std.testing.expect(original_map.entries[0].key.ptr != cloned_map.entries[0].key.ptr);
    try std.testing.expectEqualStrings("demo", try cloned_map.entries[0].value.expectString());
    try std.testing.expectEqualSlices(u8, &.{ 0xaa, 0xbb }, try cloned_map.entries[1].value.expectBytes());

    const original_nested = try original_map.entries[2].value.expectMap();
    const cloned_nested = try cloned_map.entries[2].value.expectMap();
    try std.testing.expect(original_nested.entries.ptr != cloned_nested.entries.ptr);
    const nested_list = try cloned_nested.entries[0].value.expectList();
    try std.testing.expectEqual(@as(u64, 2), try nested_list.items[0].expectInteger());
}

test "list mutation clones appended and replacement values" {
    var list: ListValue = .{
        .items = try std.testing.allocator.dupe(Value, &.{Value.int(1)}),
    };
    defer list.deinit(std.testing.allocator);

    var nested: Value = .{
        .list = .{ .items = try std.testing.allocator.dupe(Value, &.{Value.int(2)}) },
    };
    defer nested.deinit(std.testing.allocator);

    try list.pushCloned(std.testing.allocator, nested);
    try list.setCloned(std.testing.allocator, 0, nested);
    try std.testing.expectError(error.IndexOutOfBounds, list.setCloned(std.testing.allocator, 2, Value.int(3)));

    nested.list.items[0] = Value.int(9);
    try std.testing.expectEqual(@as(u64, 2), try list.items[0].list.items[0].expectInteger());
    try std.testing.expectEqual(@as(u64, 2), try list.items[1].list.items[0].expectInteger());
}

test "map mutation inserts and replaces cloned values" {
    var map: MapValue = .{ .entries = try std.testing.allocator.alloc(MapEntry, 0) };
    defer map.deinit(std.testing.allocator);

    var nested: Value = .{
        .list = .{ .items = try std.testing.allocator.dupe(Value, &.{Value.int(4)}) },
    };
    defer nested.deinit(std.testing.allocator);

    try map.setCloned(std.testing.allocator, "items", nested);
    try map.setCloned(std.testing.allocator, "items", Value.int(7));
    try map.setCloned(std.testing.allocator, "other", nested);

    try std.testing.expectEqual(@as(usize, 2), map.entries.len);
    try std.testing.expectEqual(@as(u64, 7), try map.entryByKey("items").?.value.expectInteger());
    nested.list.items[0] = Value.int(9);
    try std.testing.expectEqual(@as(u64, 4), try map.entryByKey("other").?.value.list.items[0].expectInteger());
}

fn checkCollectionMutationAllocationFailures(allocator: std.mem.Allocator) !void {
    var list: ListValue = .{
        .items = try allocator.dupe(Value, &.{Value.int(1)}),
    };
    defer list.deinit(allocator);
    var map: MapValue = .{ .entries = try allocator.alloc(MapEntry, 0) };
    defer map.deinit(allocator);
    var nested: Value = .{
        .list = .{ .items = try allocator.dupe(Value, &.{Value.int(2)}) },
    };
    defer nested.deinit(allocator);

    list.pushCloned(allocator, nested) catch |err| {
        try std.testing.expectEqual(@as(usize, 1), list.items.len);
        return err;
    };
    list.setCloned(allocator, 0, nested) catch |err| {
        try std.testing.expectEqual(@as(u64, 1), try list.items[0].expectInteger());
        return err;
    };
    map.setCloned(allocator, "first", nested) catch |err| {
        try std.testing.expectEqual(@as(usize, 0), map.entries.len);
        return err;
    };
    map.setCloned(allocator, "first", nested) catch |err| {
        try std.testing.expectEqual(@as(usize, 1), map.entries.len);
        try std.testing.expectEqual(@as(u64, 2), try map.entries[0].value.list.items[0].expectInteger());
        return err;
    };
}

test "collection mutation handles every allocation failure transactionally" {
    try std.testing.checkAllAllocationFailures(
        std.testing.allocator,
        checkCollectionMutationAllocationFailures,
        .{},
    );
}

test "value stores type bindings" {
    const value: Value = .{ .type = .{ .index = 7 } };
    try std.testing.expectEqual(@as(u32, 7), (try value.expectType()).index);
    try std.testing.expectEqual(ValueType.type, value.valueType());
}

test "value owns and clones struct bindings" {
    const type_id: types.TypeId = .{ .index = 2 };
    var value: Value = .{
        .@"struct" = .{
            .type_id = type_id,
            .fields = try std.testing.allocator.dupe(StructFieldValue, &.{
                .{
                    .name = try std.testing.allocator.dupe(u8, "magic"),
                    .value = Value.typedInteger(0x5a4d, .{ .index = 0 }),
                },
            }),
        },
    };
    defer value.deinit(std.testing.allocator);

    var cloned = try value.clone(std.testing.allocator);
    defer cloned.deinit(std.testing.allocator);

    const original_struct = try value.expectStruct();
    const cloned_struct = try cloned.expectStruct();
    try std.testing.expectEqual(type_id.index, cloned_struct.type_id.index);
    try std.testing.expect(original_struct.fields.ptr != cloned_struct.fields.ptr);
    try std.testing.expect(original_struct.fields[0].name.ptr != cloned_struct.fields[0].name.ptr);
    try std.testing.expectEqual(@as(u64, 0x5a4d), try cloned_struct.fields[0].value.expectInteger());
}

test "packStructValue rejects extra struct fields" {
    var store: types.TypeStore = .{};
    defer store.deinit(std.testing.allocator);

    const byte_ty = try store.addInt(std.testing.allocator, 8, .unsigned);
    const header_ty = try store.addStruct(std.testing.allocator, "Header", &.{
        .{ .name = "tag", .ty = byte_ty },
    }, .@"packed");

    const fields = try std.testing.allocator.alloc(StructFieldValue, 2);
    var fields_len: usize = 0;
    var fields_owned = true;
    errdefer {
        if (fields_owned) {
            for (fields[0..fields_len]) |*field| {
                field.deinit(std.testing.allocator);
            }
            std.testing.allocator.free(fields);
        }
    }

    fields[0] = .{
        .name = try std.testing.allocator.dupe(u8, "tag"),
        .value = Value.typedInteger(1, byte_ty),
    };
    fields_len += 1;
    fields[1] = .{
        .name = try std.testing.allocator.dupe(u8, "extra"),
        .value = Value.typedInteger(2, byte_ty),
    };
    fields_len += 1;

    var struct_value: StructValue = .{
        .type_id = header_ty,
        .fields = fields,
    };
    fields_owned = false;
    defer struct_value.deinit(std.testing.allocator);

    try std.testing.expectError(error.InvalidApiArgument, packStructValue(std.testing.allocator, &store, struct_value));
}
