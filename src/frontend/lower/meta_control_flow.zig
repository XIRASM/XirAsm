const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const max_iterations = 1_000_000;

pub const Callbacks = struct {
    eval_condition: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, []const u8) LowerError!bool,
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
    eval_value_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!value_mod.Value,
    lower_statement_slice: *const fn (Allocator, *module_mod.Module, *ActiveOutput, *std.ArrayList(ActiveOutput), []const ast.Statement, *LowerContext) LowerError!void,
    lower_scoped_statement_slice: *const fn (Allocator, *module_mod.Module, *ActiveOutput, *std.ArrayList(ActiveOutput), []const ast.Statement, *LowerContext) LowerError!void,
};

pub fn lowerWhile(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    meta_while: ast.MetaWhileStatement,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    const previous_in_meta_loop = context.in_meta_loop;
    context.in_meta_loop = true;
    defer context.in_meta_loop = previous_in_meta_loop;

    var iterations: usize = 0;
    while (try callbacks.eval_condition(module, context, active.*, meta_while.condition)) {
        if (iterations >= max_iterations) return error.MetaLoopLimitExceeded;
        callbacks.lower_scoped_statement_slice(allocator, module, active, output_stack, meta_while.body, context) catch |err| switch (err) {
            error.MetaLoopBreak => return,
            error.MetaLoopContinue => {},
            else => return err,
        };
        iterations += 1;
    }
}

pub fn lowerForRange(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    meta_for: ast.MetaForRangeStatement,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    const previous_in_meta_loop = context.in_meta_loop;
    context.in_meta_loop = true;
    defer context.in_meta_loop = previous_in_meta_loop;

    switch (meta_for.source) {
        .range => |*range| try lowerIntegerRange(allocator, module, active, output_stack, meta_for.name, range.start, range.end, meta_for.body, context, callbacks),
        .list => |*node| try lowerList(allocator, module, active, output_stack, meta_for.name, node, meta_for.body, context, callbacks),
    }
}

fn lowerIntegerRange(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    name: []const u8,
    start_node: expr.Node,
    end_node: expr.Node,
    body: []const ast.Statement,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    const start = try callbacks.eval_integer_at_context(module, context, active.*, &start_node);
    const end = try callbacks.eval_integer_at_context(module, context, active.*, &end_node);
    if (end < start) return error.InvalidMetaFor;

    const iteration_count = end - start;
    if (iteration_count > max_iterations) return error.MetaLoopLimitExceeded;

    var value = start;
    while (value < end) : (value += 1) {
        try context.scopes.append(allocator, .{});
        defer context_mod.discardLastScope(context, allocator);
        try context_mod.defineLocalValue(context, allocator, name, value_mod.Value.int(value), .@"const");
        callbacks.lower_statement_slice(allocator, module, active, output_stack, body, context) catch |err| switch (err) {
            error.MetaLoopBreak => return,
            error.MetaLoopContinue => continue,
            else => return err,
        };
    }
}

fn lowerList(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    name: []const u8,
    node: *const expr.Node,
    body: []const ast.Statement,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    var value = try callbacks.eval_value_at_context(allocator, module, context, active.*, node);
    defer value.deinit(allocator);
    const list = value.expectList() catch return error.InvalidMetaFor;
    if (list.items.len > max_iterations) return error.MetaLoopLimitExceeded;

    for (list.items) |item| {
        try context.scopes.append(allocator, .{});
        defer context_mod.discardLastScope(context, allocator);
        var local_value = try item.clone(allocator);
        var local_owned_by_scope = false;
        errdefer if (!local_owned_by_scope) local_value.deinit(allocator);
        try context_mod.defineLocalValue(context, allocator, name, local_value, .@"const");
        local_owned_by_scope = true;
        callbacks.lower_statement_slice(allocator, module, active, output_stack, body, context) catch |err| switch (err) {
            error.MetaLoopBreak => return,
            error.MetaLoopContinue => continue,
            else => return err,
        };
    }
}
