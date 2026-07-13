const std = @import("std");

const fragment = @import("fragment.zig");
const source = @import("source.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const SectionId = fragment.SectionId;

pub const SymbolId = struct {
    index: u32,
};

pub const Binding = union(enum) {
    unknown,
    absolute: i64,
    value: ValueBinding,
    label: LabelBinding,
};

pub const ValueBinding = struct {
    value: value_mod.Value,
    mutability: value_mod.Mutability,
};

pub const LabelBinding = struct {
    section: SectionId,
    offset: u64,
    fragment_position: ?u32 = null,
};

pub const Symbol = struct {
    name: []u8,
    binding: Binding,
    span: source.SourceSpan,

    pub fn deinit(self: *Symbol, allocator: Allocator) void {
        switch (self.binding) {
            .value => |*binding| binding.value.deinit(allocator),
            .unknown, .absolute, .label => {},
        }
        allocator.free(self.name);
        self.* = undefined;
    }
};

pub const SymbolStore = struct {
    items: std.ArrayList(Symbol) = .empty,

    pub fn deinit(self: *SymbolStore, allocator: Allocator) void {
        for (self.items.items) |*symbol| {
            symbol.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn defineLabel(
        self: *SymbolStore,
        allocator: Allocator,
        name: []const u8,
        section: SectionId,
        offset: u64,
        span: source.SourceSpan,
    ) !SymbolId {
        return self.defineLabelWithAnchor(allocator, name, section, offset, null, span);
    }

    pub fn defineAnchoredLabel(
        self: *SymbolStore,
        allocator: Allocator,
        name: []const u8,
        section: SectionId,
        offset: u64,
        fragment_position: u32,
        span: source.SourceSpan,
    ) !SymbolId {
        return self.defineLabelWithAnchor(allocator, name, section, offset, fragment_position, span);
    }

    fn defineLabelWithAnchor(
        self: *SymbolStore,
        allocator: Allocator,
        name: []const u8,
        section: SectionId,
        offset: u64,
        fragment_position: ?u32,
        span: source.SourceSpan,
    ) !SymbolId {
        if (self.lookup(name) != null) return error.DuplicateSymbol;

        const id = try nextSymbolId(self.items.items.len);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        try self.items.append(allocator, .{
            .name = owned_name,
            .binding = .{
                .label = .{
                    .section = section,
                    .offset = offset,
                    .fragment_position = fragment_position,
                },
            },
            .span = span,
        });
        return id;
    }

    pub fn defineValue(
        self: *SymbolStore,
        allocator: Allocator,
        name: []const u8,
        value: value_mod.Value,
        mutability: value_mod.Mutability,
        span: source.SourceSpan,
    ) !SymbolId {
        if (self.lookup(name) != null) return error.DuplicateSymbol;

        const id = try nextSymbolId(self.items.items.len);
        const owned_name = try allocator.dupe(u8, name);
        errdefer allocator.free(owned_name);

        try self.items.append(allocator, .{
            .name = owned_name,
            .binding = .{
                .value = .{
                    .value = value,
                    .mutability = mutability,
                },
            },
            .span = span,
        });
        return id;
    }

    pub fn setValue(
        self: *SymbolStore,
        allocator: Allocator,
        name: []const u8,
        new_value: value_mod.Value,
    ) !void {
        const id = self.lookup(name) orelse return error.InvalidValueDeclaration;
        const symbol = try self.getMutable(id);
        switch (symbol.binding) {
            .value => |*binding| {
                if (binding.mutability != .let) return error.InvalidValueDeclaration;
                binding.value.deinit(allocator);
                binding.value = new_value;
            },
            .unknown, .absolute, .label => return error.InvalidValueDeclaration,
        }
    }

    pub fn lookupMutableValue(self: *SymbolStore, name: []const u8) value_mod.MutableValueLookup {
        const id = self.lookup(name) orelse return .missing;
        const stored = &self.items.items[id.index];
        return switch (stored.binding) {
            .value => |*binding| if (binding.mutability == .let)
                .{ .value = &binding.value }
            else
                .immutable,
            .unknown, .absolute, .label => .missing,
        };
    }

    pub fn lookup(self: *const SymbolStore, name: []const u8) ?SymbolId {
        for (self.items.items, 0..) |symbol, index| {
            if (std.mem.eql(u8, symbol.name, name)) {
                if (index > std.math.maxInt(u32)) return null;
                return .{ .index = @intCast(index) };
            }
        }
        return null;
    }

    pub fn get(self: *const SymbolStore, id: SymbolId) !*const Symbol {
        if (id.index >= self.items.items.len) return error.InvalidSymbol;
        return &self.items.items[id.index];
    }

    pub fn getMutable(self: *SymbolStore, id: SymbolId) !*Symbol {
        if (id.index >= self.items.items.len) return error.InvalidSymbol;
        return &self.items.items[id.index];
    }
};

fn nextSymbolId(len: usize) error{TooManySymbols}!SymbolId {
    if (len > std.math.maxInt(u32)) return error.TooManySymbols;
    return .{ .index = @intCast(len) };
}

test "symbol store updates let value bindings" {
    var store: SymbolStore = .{};
    defer store.deinit(std.testing.allocator);

    const id = try store.defineValue(
        std.testing.allocator,
        "page",
        value_mod.Value.int(4096),
        .let,
        source.unknown_span,
    );

    try store.setValue(std.testing.allocator, "page", value_mod.Value.int(8192));
    const symbol = try store.get(id);
    switch (symbol.binding) {
        .value => |binding| {
            try std.testing.expectEqual(value_mod.Mutability.let, binding.mutability);
            try std.testing.expectEqual(@as(u64, 8192), try binding.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }
}

test "symbol store rejects const value updates" {
    var store: SymbolStore = .{};
    defer store.deinit(std.testing.allocator);

    _ = try store.defineValue(
        std.testing.allocator,
        "page",
        value_mod.Value.int(4096),
        .@"const",
        source.unknown_span,
    );

    var replacement = value_mod.Value.int(8192);
    defer replacement.deinit(std.testing.allocator);
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        store.setValue(std.testing.allocator, "page", replacement),
    );
}

test "symbol store records value bindings" {
    var store: SymbolStore = .{};
    defer store.deinit(std.testing.allocator);

    const id = try store.defineValue(
        std.testing.allocator,
        "page",
        value_mod.Value.int(4096),
        .@"const",
        source.unknown_span,
    );
    const symbol = try store.get(id);
    switch (symbol.binding) {
        .value => |binding| {
            try std.testing.expectEqual(value_mod.Mutability.@"const", binding.mutability);
            try std.testing.expectEqual(@as(u64, 4096), try binding.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }
}
