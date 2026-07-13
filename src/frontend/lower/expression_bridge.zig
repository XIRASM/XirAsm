const std = @import("std");

const expr = @import("../expr.zig");
const meta_io = @import("../meta_io.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const LowerContext = context_mod.LowerContext;

pub const ActiveExpressionContext = struct {
    target: @import("../target.zig").Target,
    section_id: @import("../fragment.zig").SectionId,
    offset: u64,
    file_offset: u64,
};

pub const Callbacks = struct {
    next_unique_symbol: *const fn (context: *anyopaque, allocator: Allocator, prefix: []const u8) expr.ExpressionError![]u8,
    call_user_function: *const fn (
        context: *anyopaque,
        allocator: Allocator,
        name: []const u8,
        args: []const expr.BuiltinArgument,
        eval_ctx: *expr.EvalContext,
    ) expr.ExpressionError!value_mod.Value,
    evaluate_struct_literal: *const fn (
        context: *anyopaque,
        allocator: Allocator,
        text: []const u8,
        eval_ctx: *expr.EvalContext,
    ) expr.ExpressionError!value_mod.Value,
};

pub fn evalBooleanAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveExpressionContext,
    callbacks: Callbacks,
    node: *const expr.Node,
) contracts.LowerError!bool {
    var ctx = evalContext(module, context, active, callbacks);
    return expr.evaluateBoolean(node, &ctx) catch |err| return mapExpressionError(err);
}

pub fn evalInteger(module: *module_mod.Module, node: *const expr.Node) contracts.LowerError!u64 {
    var ctx: expr.EvalContext = .{ .module = module };
    return expr.evaluateInteger(node, &ctx) catch |err| return mapExpressionError(err);
}

pub fn evalIntegerAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveExpressionContext,
    callbacks: Callbacks,
    node: *const expr.Node,
) contracts.LowerError!u64 {
    var ctx = evalContext(module, context, active, callbacks);
    return expr.evaluateInteger(node, &ctx) catch |err| return mapExpressionError(err);
}

pub fn evalValueAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveExpressionContext,
    callbacks: Callbacks,
    node: *const expr.Node,
) contracts.LowerError!value_mod.Value {
    var ctx = evalContext(module, context, active, callbacks);
    return expr.evaluateValue(allocator, node, &ctx) catch |err| return mapExpressionError(err);
}

fn evalContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveExpressionContext,
    callbacks: Callbacks,
) expr.EvalContext {
    return .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = fileResolver(context),
        .source_path = context_mod.currentSourcePath(context),
        .local_context = context,
        .resolve_local = context_mod.resolveLocalValue,
        .next_unique_symbol = callbacks.next_unique_symbol,
        .call_user_function = callbacks.call_user_function,
        .evaluate_struct_literal = callbacks.evaluate_struct_literal,
    };
}

pub fn mapLowerErrorToExpression(err: contracts.LowerError) expr.ExpressionError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnknownTypeName => error.UnknownTypeName,
        error.UnknownField => error.UnknownField,
        error.DivisionByZero => error.DivisionByZero,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.InvalidIntegerBits => error.InvalidIntegerBits,
        error.InvalidType => error.InvalidType,
        error.InvalidSection => error.InvalidSection,
        error.MissingStructFieldValue => error.MissingStructFieldValue,
        error.OffsetOverflow => error.OffsetOverflow,
        error.FileNotAvailable => error.FileNotAvailable,
        error.InvalidValueDeclaration,
        error.InvalidExpression,
        error.InvalidApiArity,
        error.InvalidMetaFunction,
        error.MissingMetaReturn,
        error.SideEffectInValueFunction,
        => error.InvalidOperand,
        else => error.InvalidOperand,
    };
}

pub fn mapExpressionError(err: expr.ExpressionError) contracts.LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnknownTypeName => error.UnknownTypeName,
        error.UnknownField => error.UnknownField,
        error.DivisionByZero => error.DivisionByZero,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.InvalidIntegerBits => error.InvalidIntegerBits,
        error.InvalidType => error.InvalidType,
        error.InvalidFragment => error.InvalidApiArgument,
        error.InvalidSection => error.InvalidSection,
        error.MissingStructFieldValue => error.MissingStructFieldValue,
        error.OffsetOverflow => error.OffsetOverflow,
        error.FileNotAvailable => error.FileNotAvailable,
        error.TypeMismatch => error.InvalidExpression,
        error.InvalidArgument,
        error.InvalidCharacter,
        error.InvalidNumber,
        error.InvalidOperand,
        error.InvalidToken,
        error.MissingEvaluationContext,
        error.UndefinedSymbol,
        error.UnexpectedEof,
        => error.InvalidExpression,
    };
}

pub fn fileResolver(context: *LowerContext) ?meta_io.FileResolver {
    if (context.include_resolver == null) return null;
    return .{
        .context = @ptrCast(context),
        .read = readResolvedMetaFile,
        .exists = metaFileExists,
    };
}

fn readResolvedMetaFile(
    raw_context: *anyopaque,
    allocator: Allocator,
    request: meta_io.FileReadRequest,
) meta_io.Error!meta_io.FileReadResult {
    const context: *LowerContext = @ptrCast(@alignCast(raw_context));
    const include_resolver = context.include_resolver orelse return error.FileNotAvailable;
    var include_source = include_resolver.resolve(include_resolver.context, allocator, .{
        .path = request.path,
        .parent_path = request.parent_path,
        .span = request.span,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.FileNotAvailable,
    };
    errdefer include_source.deinit(allocator);

    if (include_source.identity) |identity| {
        allocator.free(identity);
        include_source.identity = null;
    }

    return .{
        .path = include_source.path,
        .bytes = include_source.bytes,
    };
}

fn metaFileExists(
    raw_context: *anyopaque,
    allocator: Allocator,
    request: meta_io.FileReadRequest,
) Allocator.Error!bool {
    var result = readResolvedMetaFile(raw_context, allocator, request) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotAvailable => return false,
    };
    result.deinit(allocator);
    return true;
}

test "expression error mapping preserves file availability" {
    try std.testing.expectEqual(error.FileNotAvailable, mapExpressionError(error.FileNotAvailable));
}
