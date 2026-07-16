const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const typecheck = @import("../typecheck.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const expression_bridge = @import("expression_bridge.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

const max_call_depth = 128;

pub const Callbacks = struct {
    lower_statement_slice: *const fn (Allocator, *module_mod.Module, *ActiveOutput, *std.ArrayList(ActiveOutput), []const ast.Statement, *LowerContext) LowerError!void,
    value_arg_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError!value_mod.Value,
    call_user_function: *const fn (*anyopaque, Allocator, []const u8, []const expr.BuiltinArgument, *expr.EvalContext) expr.ExpressionError!value_mod.Value,
    evaluate_struct_literal: *const fn (*anyopaque, Allocator, []const u8, *expr.EvalContext) expr.ExpressionError!value_mod.Value,
};

pub fn lowerStatementFunction(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    context: *LowerContext,
    function_index: usize,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!void {
    const function = try context.functions.get(function_index);
    if (function.return_type_name != null) return error.InvalidMetaFunction;
    if (call.args.len != function.params.len) return error.InvalidApiArity;
    if (context.call_depth >= max_call_depth) return error.MetaCallDepthExceeded;

    context.call_depth += 1;
    defer context.call_depth -= 1;
    const caller_in_meta_loop = context.in_meta_loop;
    context.in_meta_loop = false;
    defer context.in_meta_loop = caller_in_meta_loop;

    try validateMutableArguments(module, context, call, function.params);

    try context.scopes.append(allocator, .{});
    defer context_mod.discardLastScope(context, allocator);

    for (function.params, 0..) |param, index| {
        const annotation = try typecheck.annotationFromName(module, param.type_name);
        if (param.type_name != null and annotation == null) return error.InvalidMetaFunction;
        var value = try callbacks.value_arg_at_context(allocator, module, context, active.*, call, index);
        errdefer value.deinit(allocator);
        try typecheck.coerceValueToAnnotation(module, &value, annotation);
        try context_mod.defineLocalValue(context, allocator, param.name, value, param.mutability);
    }

    try callbacks.lower_statement_slice(allocator, module, active, output_stack, function.body, context);
    try writeBackMutableArguments(allocator, module, context, call, function.params);
}

fn validateMutableArguments(
    module: *module_mod.Module,
    context: *LowerContext,
    call: ast.ApiCallStatement,
    params: []const ast.MetaFunctionParam,
) LowerError!void {
    for (params, 0..) |param, index| {
        if (param.mutability != .let) continue;
        const name = directSymbolArgument(call, index) orelse
            return fail(module, call, "mutable function argument must be a direct let binding");

        for (params[0..index], 0..) |previous, previous_index| {
            if (previous.mutability != .let) continue;
            const previous_name = directSymbolArgument(call, previous_index) orelse continue;
            if (std.mem.eql(u8, previous_name, name)) {
                return fail(module, call, "mutable function arguments cannot alias the same binding");
            }
        }

        switch (context_mod.lookupMutableLocalValue(context, name)) {
            .value => {},
            .immutable => return fail(module, call, "mutable function argument must resolve to a let binding"),
            .missing => switch (module.symbols.lookupMutableValue(name)) {
                .value => {},
                .immutable => return fail(module, call, "mutable function argument must resolve to a let binding"),
                .missing => return fail(module, call, "mutable function argument must resolve to a let binding"),
            },
        }
    }
}

fn writeBackMutableArguments(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    call: ast.ApiCallStatement,
    params: []const ast.MetaFunctionParam,
) LowerError!void {
    for (params, 0..) |param, index| {
        if (param.mutability != .let) continue;
        const name = directSymbolArgument(call, index) orelse return error.InvalidMetaFunction;
        const local = context_mod.lookupLocalValue(context, param.name) orelse return error.InvalidMetaFunction;
        var updated = try local.clone(allocator);
        errdefer updated.deinit(allocator);
        if (try context_mod.setCallerLocalValue(context, allocator, name, updated)) continue;
        try module.setValue(name, updated);
    }
}

fn directSymbolArgument(call: ast.ApiCallStatement, index: usize) ?[]const u8 {
    if (index >= call.args.len) return null;
    return switch (call.args[index]) {
        .expression => |node| switch (node) {
            .symbol => |name| name,
            else => null,
        },
        .string, .struct_literal => null,
    };
}

fn fail(module: *module_mod.Module, call: ast.ApiCallStatement, message: []const u8) LowerError {
    module.diagnostics.add(module.allocator, .err, call.span, message) catch return error.OutOfMemory;
    return error.FrontendDiagnostics;
}

pub fn evalValueFunctionAt(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    function_index: usize,
    args: []const expr.BuiltinArgument,
    callbacks: Callbacks,
) LowerError!value_mod.Value {
    const function = try module.value_functions.get(function_index);
    const return_type_name = function.return_type_name orelse return error.InvalidMetaFunction;
    if (args.len != function.params.len) return error.InvalidApiArity;
    if (context.call_depth >= max_call_depth) return error.MetaCallDepthExceeded;

    context.call_depth += 1;
    defer context.call_depth -= 1;
    context.value_function_depth += 1;
    defer context.value_function_depth -= 1;
    const caller_in_meta_loop = context.in_meta_loop;
    context.in_meta_loop = false;
    defer context.in_meta_loop = caller_in_meta_loop;

    const previous_return = context.return_value;
    context.return_value = null;
    defer {
        if (context.return_value) |*stored| {
            stored.deinit(allocator);
        }
        context.return_value = previous_return;
    }

    var scoped_active = active;
    try context.scopes.append(allocator, .{});
    defer context_mod.discardLastScope(context, allocator);

    var eval_ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = expression_bridge.fileResolver(context),
        .source_path = context_mod.currentSourcePath(context),
        .local_context = context,
        .resolve_local = context_mod.resolveLocalValue,
        .next_unique_symbol = nextUniqueSymbol,
        .call_user_function = callbacks.call_user_function,
        .evaluate_struct_literal = callbacks.evaluate_struct_literal,
    };
    for (function.params, 0..) |param, index| {
        const annotation = try typecheck.annotationFromName(module, param.type_name);
        if (param.type_name != null and annotation == null) return error.InvalidMetaFunction;
        var value = expr.evaluateBuiltinValueArg(allocator, args[index], &eval_ctx) catch |err| return expression_bridge.mapExpressionError(err);
        errdefer value.deinit(allocator);
        try typecheck.coerceValueToAnnotation(module, &value, annotation);
        try context_mod.defineLocalValue(context, allocator, param.name, value, .@"const");
    }

    callbacks.lower_statement_slice(allocator, module, &scoped_active, output_stack, function.body, context) catch |err| {
        if (err != error.MetaFunctionReturned) return err;
    };
    var result = context.return_value orelse return error.MissingMetaReturn;
    context.return_value = null;
    errdefer result.deinit(allocator);

    const annotation = (try typecheck.annotationFromName(module, return_type_name)) orelse return error.InvalidMetaFunction;
    try typecheck.coerceValueToAnnotation(module, &result, annotation);
    return result;
}

pub fn nextUniqueSymbol(context: *anyopaque, allocator: Allocator, prefix: []const u8) expr.ExpressionError![]u8 {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const index = lower_context.unique_symbol_counter;
    lower_context.unique_symbol_counter = std.math.add(u64, lower_context.unique_symbol_counter, 1) catch return error.InvalidNumber;
    return std.fmt.allocPrint(allocator, "{s}__{}", .{ prefix, index });
}
