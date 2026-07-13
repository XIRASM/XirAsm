const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const fragment = @import("../fragment.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const isa_text = @import("isa_text.zig");
const expression_bridge = @import("expression_bridge.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    value_arg_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError!value_mod.Value,
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
    advance_active_output: *const fn (*ActiveOutput, fragment.Fragment) LowerError!void,
    require_open_output_region: *const fn (ActiveOutput) LowerError!void,
    require_arg_count: *const fn (ast.ApiCallStatement, usize) LowerError!void,
};

pub fn lowerCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!void {
    try callbacks.require_open_output_region(active.*);
    try callbacks.require_arg_count(call, 1);
    var value = try callbacks.value_arg_at_context(module.allocator, module, context, active.*, call, 0);
    defer value.deinit(module.allocator);
    const text = switch (value) {
        .string => |stored| stored,
        .void, .integer, .float32, .float64, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
    };
    if (text.len == 0 or std.mem.indexOfAny(u8, text, "\r\n") != null) return error.InvalidApiArgument;

    const lowered_text = try lowerText(module.allocator, module, context, active.*, text, callbacks);
    defer module.allocator.free(lowered_text);
    const fragment_id = try module.appendIsaInstruction(active.section_id, active.target, lowered_text, call.span);
    try callbacks.advance_active_output(active, module.fragments.items.items[fragment_id.index]);
}

pub fn lowerText(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    text: []const u8,
    callbacks: Callbacks,
) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var cursor: usize = 0;
    while (isa_text.findBuiltinCall(text, cursor)) |call_range| {
        try result.appendSlice(allocator, text[cursor..call_range.start]);
        var expression = expr.parseOwned(allocator, text[call_range.start..call_range.end]) catch |err| return expression_bridge.mapExpressionError(err);
        defer expression.deinit(allocator);
        const value = try callbacks.eval_integer_at_context(module, context, active, &expression);
        const value_text = try std.fmt.allocPrint(allocator, "{}", .{value});
        defer allocator.free(value_text);
        try result.appendSlice(allocator, value_text);
        cursor = call_range.end;
    }

    try result.appendSlice(allocator, text[cursor..]);
    const resolver: IntegerResolver = .{ .module = module, .context = context };
    const lowered = try isa_text.substituteIntegerSymbols(allocator, active.target, result.items, resolver);
    result.deinit(allocator);
    return lowered;
}

const IntegerResolver = struct {
    module: *const module_mod.Module,
    context: *const LowerContext,

    pub fn resolve(self: IntegerResolver, name: []const u8) ?u64 {
        return integerSymbolValue(self.module, self.context, name);
    }
};

fn integerSymbolValue(
    module: *const module_mod.Module,
    context: *const LowerContext,
    name: []const u8,
) ?u64 {
    if (context_mod.lookupLocalValue(context, name)) |local| {
        return switch (local.*) {
            .integer => |integer| integer.value,
            .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => null,
        };
    }

    const id = module.symbols.lookup(name) orelse return null;
    const stored = module.symbols.get(id) catch return null;
    return switch (stored.binding) {
        .value => |binding| switch (binding.value) {
            .integer => |integer| integer.value,
            .void, .float32, .float64, .boolean, .string, .bytes, .type, .@"struct", .list, .map => null,
        },
        .absolute => |absolute| if (absolute < 0) null else @intCast(absolute),
        .label, .unknown => null,
    };
}
