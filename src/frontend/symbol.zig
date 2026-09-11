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
    /// Name lookup index. It borrows the names owned by `items` (it must never free
    /// them) and it covers every entry: `lookup` consults it only while that holds,
    /// and falls back to scanning otherwise, which keeps the store correct whatever
    /// happens to the index. Declaring symbols was quadratic before this index
    /// existed, because every declaration scanned the whole store.
    names: std.StringHashMapUnmanaged(SymbolId) = .empty,

    pub fn deinit(self: *SymbolStore, allocator: Allocator) void {
        self.names.deinit(allocator);
        for (self.items.items) |*symbol| {
            symbol.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    /// Adds a name to the lookup index. The index has to take every entry: an
    /// allocation failure is a real failure here and propagates to the caller,
    /// which already reports allocation errors from the name duplication above.
    fn indexName(self: *SymbolStore, allocator: Allocator, name: []const u8, id: SymbolId) !void {
        try self.names.put(allocator, name, id);
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
        // If the index cannot take the name, the store must not keep an entry that
        // points at it: drop the entry before the name is freed.
        errdefer {
            _ = self.items.pop();
        }
        try self.indexName(allocator, owned_name, id);
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
        // If the index cannot take the name, the store must not keep an entry that
        // points at it: drop the entry before the name is freed.
        errdefer {
            _ = self.items.pop();
        }
        try self.indexName(allocator, owned_name, id);
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
        if (self.names.count() == self.items.items.len) {
            return self.names.get(name);
        }
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

test "symbol lookup answers the same with and without the name index" {
    var store: SymbolStore = .{};
    defer store.deinit(std.testing.allocator);

    var buffer: [32]u8 = undefined;
    for (0..512) |index| {
        const name = try std.fmt.bufPrint(&buffer, "value_{d}", .{index});
        _ = try store.defineValue(
            std.testing.allocator,
            name,
            value_mod.Value.int(@intCast(index)),
            .let,
            source.unknown_span,
        );
    }
    try std.testing.expectEqual(@as(usize, 512), store.names.count());

    // Indexed path: the map covers every entry.
    const found = store.lookup("value_100");
    try std.testing.expect(found != null);
    try std.testing.expectEqual(@as(u32, 100), found.?.index);
    try std.testing.expect(store.lookup("value_missing") == null);

    // Fallback path: an index that does not cover every entry must not change
    // any answer, so the scan is exercised deliberately.
    store.names.clearRetainingCapacity();
    try std.testing.expect(store.names.count() != store.items.items.len);
    const scanned = store.lookup("value_100");
    try std.testing.expect(scanned != null);
    try std.testing.expectEqual(@as(u32, 100), scanned.?.index);
    try std.testing.expect(store.lookup("value_missing") == null);

    // A duplicate is still refused while scanning.
    try std.testing.expectError(error.DuplicateSymbol, store.defineValue(
        std.testing.allocator,
        "value_7",
        value_mod.Value.int(7),
        .let,
        source.unknown_span,
    ));
}
