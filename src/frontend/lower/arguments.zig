const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const aggregate_literal = @import("aggregate_literal.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
    eval_value_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!value_mod.Value,
};

pub fn integerAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!u64 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| callbacks.eval_integer_at_context(module, context, active, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

pub fn valueAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!value_mod.Value {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| callbacks.eval_value_at_context(allocator, module, context, active, node),
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .struct_literal => |literal| .{
            .@"struct" = try aggregate_literal.structValueFromLiteral(
                allocator,
                module,
                context,
                active,
                literal,
                aggregateCallbacks(callbacks),
            ),
        },
    };
}

pub fn booleanAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!bool {
    var value = try valueAtContext(module.allocator, module, context, active, call, index, callbacks);
    defer value.deinit(module.allocator);
    return value.expectBoolean() catch error.InvalidApiArgument;
}

pub fn sourcePathAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError![]u8 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .string => |text| allocator.dupe(u8, text),
        .expression, .struct_literal => {
            var value = try valueAtContext(allocator, module, context, active, call, index, callbacks);
            defer value.deinit(allocator);
            const text = switch (value) {
                .string => |stored| stored,
                .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            };
            return allocator.dupe(u8, text);
        },
    };
}

fn aggregateCallbacks(callbacks: Callbacks) aggregate_literal.Callbacks {
    return .{
        .eval_integer_at_context = callbacks.eval_integer_at_context,
        .eval_value_at_context = callbacks.eval_value_at_context,
    };
}
