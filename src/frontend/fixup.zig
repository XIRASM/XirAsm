const std = @import("std");

const expr = @import("expr.zig");
const fragment = @import("fragment.zig");
const module_mod = @import("module.zig");
const source = @import("source.zig");

const Allocator = std.mem.Allocator;

pub const FragmentId = fragment.FragmentId;

pub const FixupId = struct {
    index: u32,
};

pub const FixupKind = enum {
    absolute,
    pc_relative,
};

pub const ResolveError = expr.ExpressionError || error{
    InvalidFixupTarget,
};

pub const ResolvedFixup = struct {
    fixup: FixupId,
    value: u64,
};

pub const ResolveContext = struct {
    module: *module_mod.Module,
    active_section: ?fragment.SectionId = null,
    active_offset: u64 = 0,
};

pub const FixupTarget = union(enum) {
    symbol: []u8,
    expression_text: []u8,

    pub fn deinit(self: *FixupTarget, allocator: Allocator) void {
        switch (self.*) {
            .symbol => |text| allocator.free(text),
            .expression_text => |text| allocator.free(text),
        }
        self.* = undefined;
    }
};

pub const Fixup = struct {
    fragment: FragmentId,
    target: FixupTarget,
    kind: FixupKind,
    offset: u32,
    width_bits: u16,
    span: source.SourceSpan,

    pub fn deinit(self: *Fixup, allocator: Allocator) void {
        self.target.deinit(allocator);
        self.* = undefined;
    }
};

pub const FixupStore = struct {
    items: std.ArrayList(Fixup) = .empty,

    pub fn deinit(self: *FixupStore, allocator: Allocator) void {
        for (self.items.items) |*fixup| {
            fixup.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(
        self: *FixupStore,
        allocator: Allocator,
        fragment_id: FragmentId,
        symbol: []const u8,
        kind: FixupKind,
        offset: u32,
        width_bits: u16,
        span: source.SourceSpan,
    ) !FixupId {
        const owned_symbol = try allocator.dupe(u8, symbol);
        errdefer allocator.free(owned_symbol);

        return self.addOwnedTarget(
            allocator,
            fragment_id,
            .{ .symbol = owned_symbol },
            kind,
            offset,
            width_bits,
            span,
        );
    }

    pub fn addExpression(
        self: *FixupStore,
        allocator: Allocator,
        fragment_id: FragmentId,
        expression_text: []const u8,
        kind: FixupKind,
        offset: u32,
        width_bits: u16,
        span: source.SourceSpan,
    ) !FixupId {
        const owned_expression = try allocator.dupe(u8, expression_text);
        errdefer allocator.free(owned_expression);

        return self.addOwnedTarget(
            allocator,
            fragment_id,
            .{ .expression_text = owned_expression },
            kind,
            offset,
            width_bits,
            span,
        );
    }

    fn addOwnedTarget(
        self: *FixupStore,
        allocator: Allocator,
        fragment_id: FragmentId,
        target: FixupTarget,
        kind: FixupKind,
        offset: u32,
        width_bits: u16,
        span: source.SourceSpan,
    ) !FixupId {
        const id = try nextFixupId(self.items.items.len);
        var owned_target = target;
        errdefer owned_target.deinit(allocator);

        try self.items.append(allocator, .{
            .fragment = fragment_id,
            .target = owned_target,
            .kind = kind,
            .offset = offset,
            .width_bits = width_bits,
            .span = span,
        });
        return id;
    }

    pub fn resolveOne(
        self: *const FixupStore,
        allocator: Allocator,
        module: *module_mod.Module,
        id: FixupId,
    ) ResolveError!ResolvedFixup {
        return self.resolveOneWithContext(allocator, .{ .module = module }, id);
    }

    pub fn resolveOneWithContext(
        self: *const FixupStore,
        allocator: Allocator,
        ctx: ResolveContext,
        id: FixupId,
    ) ResolveError!ResolvedFixup {
        if (id.index >= self.items.items.len) return error.InvalidFixupTarget;
        const stored = self.items.items[id.index];
        const value = switch (stored.target) {
            .symbol => |name| try resolveSymbolTarget(ctx.module, name),
            .expression_text => |text| blk: {
                var node = try expr.parseOwned(allocator, text);
                defer node.deinit(allocator);
                var eval_ctx: expr.EvalContext = .{
                    .module = ctx.module,
                    .active_section = ctx.active_section,
                    .active_offset = ctx.active_offset,
                };
                break :blk try expr.evaluateInteger(&node, &eval_ctx);
            },
        };
        return .{
            .fixup = id,
            .value = value,
        };
    }
};

fn resolveSymbolTarget(module: *module_mod.Module, name: []const u8) ResolveError!u64 {
    const id = module.symbols.lookup(name) orelse return error.UndefinedSymbol;
    const stored = module.symbols.get(id) catch return error.UndefinedSymbol;
    return switch (stored.binding) {
        .label => |label| blk: {
            const stored_section = module.sections.get(label.section) catch return error.InvalidOperand;
            break :blk std.math.add(u64, stored_section.origin, label.offset) catch error.InvalidNumber;
        },
        .absolute => |absolute| if (absolute < 0) error.InvalidOperand else @intCast(absolute),
        .value => |binding| switch (binding.value) {
            .integer => |integer| integer.value,
            .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => error.InvalidOperand,
        },
        .unknown => error.UndefinedSymbol,
    };
}

fn nextFixupId(len: usize) error{TooManyFixups}!FixupId {
    if (len > std.math.maxInt(u32)) return error.TooManyFixups;
    return .{ .index = @intCast(len) };
}

test "fixup store records symbol and expression targets" {
    var store: FixupStore = .{};
    defer store.deinit(std.testing.allocator);

    _ = try store.add(
        std.testing.allocator,
        .{ .index = 0 },
        "target",
        .pc_relative,
        1,
        32,
        source.unknown_span,
    );
    _ = try store.addExpression(
        std.testing.allocator,
        .{ .index = 1 },
        "target + 4",
        .absolute,
        0,
        64,
        source.unknown_span,
    );

    try std.testing.expectEqual(@as(usize, 2), store.items.items.len);
    switch (store.items.items[0].target) {
        .symbol => |name| try std.testing.expectEqualStrings("target", name),
        else => return error.UnexpectedFixupTarget,
    }
    switch (store.items.items[1].target) {
        .expression_text => |text| try std.testing.expectEqualStrings("target + 4", text),
        else => return error.UnexpectedFixupTarget,
    }
}

test "fixup store resolves symbol and expression targets" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    _ = try module.defineLabel("target", module.default_section, 8, source.unknown_span);

    var store: FixupStore = .{};
    defer store.deinit(std.testing.allocator);

    const symbol_id = try store.add(
        std.testing.allocator,
        .{ .index = 0 },
        "target",
        .absolute,
        0,
        64,
        source.unknown_span,
    );
    const expression_id = try store.addExpression(
        std.testing.allocator,
        .{ .index = 1 },
        "label_addr(target) + 4",
        .absolute,
        0,
        64,
        source.unknown_span,
    );

    try std.testing.expectEqual(@as(u64, 8), (try store.resolveOne(std.testing.allocator, &module, symbol_id)).value);
    try std.testing.expectEqual(@as(u64, 12), (try store.resolveOne(std.testing.allocator, &module, expression_id)).value);
}

test "fixup expression resolves active output queries from context" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try module.sections.setOrigin(module.default_section, 0x1000);

    var store: FixupStore = .{};
    defer store.deinit(std.testing.allocator);

    const id = try store.addExpression(
        std.testing.allocator,
        .{ .index = 0 },
        "here() + file_offset() - region_base()",
        .absolute,
        0,
        64,
        source.unknown_span,
    );

    const resolved = try store.resolveOneWithContext(
        std.testing.allocator,
        .{
            .module = &module,
            .active_section = module.default_section,
            .active_offset = 12,
        },
        id,
    );
    try std.testing.expectEqual(@as(u64, 24), resolved.value);
}
