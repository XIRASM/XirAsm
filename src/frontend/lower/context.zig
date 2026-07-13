const std = @import("std");

const expr = @import("../expr.zig");
const meta_function = @import("../meta_function.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");

const Allocator = std.mem.Allocator;

pub const LowerContext = struct {
    include_resolver: ?contracts.IncludeResolver = null,
    source_stack: std.ArrayList([]const u8) = .empty,
    imported_sources: std.ArrayList([]u8) = .empty,
    functions: meta_function.Store = .{},
    scopes: std.ArrayList(MetaScope) = .empty,
    call_depth: u32 = 0,
    value_function_depth: u32 = 0,
    in_meta_loop: bool = false,
    return_value: ?value_mod.Value = null,
    unique_symbol_counter: u64 = 0,

    pub fn deinit(self: *LowerContext, allocator: Allocator) void {
        if (self.return_value) |*stored| {
            stored.deinit(allocator);
        }
        for (self.scopes.items) |*scope| {
            scope.deinit(allocator);
        }
        self.scopes.deinit(allocator);
        self.functions.deinit(allocator);
        for (self.imported_sources.items) |path| {
            allocator.free(path);
        }
        self.imported_sources.deinit(allocator);
        self.source_stack.deinit(allocator);
        self.* = undefined;
    }
};

const MetaLocal = struct {
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,

    fn deinit(self: *MetaLocal, allocator: Allocator) void {
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

const MetaScope = struct {
    locals: std.ArrayList(MetaLocal) = .empty,

    fn deinit(self: *MetaScope, allocator: Allocator) void {
        for (self.locals.items) |*local| {
            local.deinit(allocator);
        }
        self.locals.deinit(allocator);
        self.* = undefined;
    }
};

const LocalPosition = struct {
    scope_index: usize,
    local_index: usize,
};

pub fn discardLastScope(context: *LowerContext, allocator: Allocator) void {
    if (context.scopes.items.len == 0) return;
    const last_index = context.scopes.items.len - 1;
    var scope = context.scopes.items[last_index];
    context.scopes.shrinkRetainingCapacity(last_index);
    scope.deinit(allocator);
}

pub fn pushMetaScope(context: *LowerContext, allocator: Allocator) Allocator.Error!void {
    try context.scopes.append(allocator, .{});
}

pub fn popMetaScope(context: *LowerContext, allocator: Allocator) void {
    discardLastScope(context, allocator);
}

pub fn defineFinalLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,
) contracts.LowerError!void {
    try defineLocalValue(context, allocator, name, value, mutability);
}

pub fn setFinalLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
) contracts.LowerError!bool {
    return setLocalValue(context, allocator, name, value);
}

pub fn defineLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,
) contracts.LowerError!void {
    if (context.scopes.items.len == 0) return error.InvalidMetaBlock;
    var scope = &context.scopes.items[context.scopes.items.len - 1];
    for (scope.locals.items) |local| {
        if (std.mem.eql(u8, local.name, name)) return error.DuplicateSymbol;
    }
    try scope.locals.append(allocator, .{
        .name = name,
        .value = value,
        .mutability = mutability,
    });
}

pub fn setLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    new_value: value_mod.Value,
) contracts.LowerError!bool {
    const position = findLocalPosition(context, name) orelse return false;
    const local = &context.scopes.items[position.scope_index].locals.items[position.local_index];
    if (local.mutability != .let) return error.InvalidValueDeclaration;
    local.value.deinit(allocator);
    local.value = new_value;
    return true;
}

pub fn lookupLocalValue(context: *const LowerContext, name: []const u8) ?*const value_mod.Value {
    const position = findLocalPosition(context, name) orelse return null;
    return &context.scopes.items[position.scope_index].locals.items[position.local_index].value;
}

pub fn lookupMutableLocalValue(context: *LowerContext, name: []const u8) value_mod.MutableValueLookup {
    const position = findLocalPosition(context, name) orelse return .missing;
    const local = &context.scopes.items[position.scope_index].locals.items[position.local_index];
    if (local.mutability != .let) return .immutable;
    return .{ .value = &local.value };
}

fn findLocalPosition(context: *const LowerContext, name: []const u8) ?LocalPosition {
    var scope_index = context.scopes.items.len;
    while (scope_index != 0) {
        scope_index -= 1;
        const scope = &context.scopes.items[scope_index];
        var local_index = scope.locals.items.len;
        while (local_index != 0) {
            local_index -= 1;
            if (std.mem.eql(u8, scope.locals.items[local_index].name, name)) {
                return .{
                    .scope_index = scope_index,
                    .local_index = local_index,
                };
            }
        }
    }
    return null;
}

pub fn resolveLocalValue(context: *anyopaque, allocator: Allocator, name: []const u8) expr.ExpressionError!?value_mod.Value {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const local = lookupLocalValue(lower_context, name) orelse return null;
    return try local.clone(allocator);
}

pub fn currentSourcePath(context: *const LowerContext) ?[]const u8 {
    if (context.source_stack.items.len == 0) return null;
    return context.source_stack.items[context.source_stack.items.len - 1];
}

pub fn sourceStackContains(context: *const LowerContext, path: []const u8) bool {
    for (context.source_stack.items) |stored_path| {
        if (std.mem.eql(u8, stored_path, path)) return true;
    }
    return false;
}

pub fn sourceImported(context: *const LowerContext, path: []const u8) bool {
    for (context.imported_sources.items) |stored_path| {
        if (std.mem.eql(u8, stored_path, path)) return true;
    }
    return false;
}

pub fn rememberImportedSource(
    allocator: Allocator,
    context: *LowerContext,
    path: []const u8,
) Allocator.Error!void {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try context.imported_sources.append(allocator, owned_path);
}
