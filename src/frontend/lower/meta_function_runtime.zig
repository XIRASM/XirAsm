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

    try context.scopes.append(allocator, .{});
    defer context_mod.discardLastScope(context, allocator);

    for (function.params, 0..) |param, index| {
        const annotation = try typecheck.annotationFromName(module, param.type_name);
        if (param.type_name != null and annotation == null) return error.InvalidMetaFunction;
        var value = try callbacks.value_arg_at_context(allocator, module, context, active.*, call, index);
        errdefer value.deinit(allocator);
        try typecheck.coerceValueToAnnotation(module, &value, annotation);
        try context_mod.defineLocalValue(context, allocator, param.name, value, .@"const");
    }

    try callbacks.lower_statement_slice(allocator, module, active, output_stack, function.body, context);
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
