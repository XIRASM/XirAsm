const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const source = @import("../source.zig");
const typecheck = @import("../typecheck.zig");
const value_mod = @import("../value.zig");
const aggregate_literal = @import("aggregate_literal.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const deferred = @import("deferred.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
    eval_value_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!value_mod.Value,
};

pub fn lowerDeclaration(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    declaration: ast.ValueDeclarationStatement,
    callbacks: Callbacks,
) LowerError!void {
    var evaluated = try lowerInitializerReporting(module, context, active, declaration.value, declaration.span, callbacks);
    errdefer evaluated.deinit(module.allocator);
    const annotation = try typecheck.annotationFromName(module, declaration.type_name);
    if (declaration.type_name != null and annotation == null) return error.InvalidValueDeclaration;
    try typecheck.coerceValueToAnnotation(module, &evaluated, annotation);

    if (context.scopes.items.len != 0) {
        try context_mod.defineLocalValue(context, module.allocator, declaration.name, evaluated, declaration.mutability);
        return;
    }

    const symbol_id = try module.defineValue(declaration.name, evaluated, declaration.mutability, declaration.span);
    if (symbol_id.index >= module.symbols.items.items.len) return error.InvalidSymbol;
}

pub fn lowerAssignment(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    assignment: ast.AssignmentStatement,
    callbacks: Callbacks,
) LowerError!void {
    var evaluated = try lowerInitializerReporting(module, context, active, assignment.value, assignment.span, callbacks);
    errdefer evaluated.deinit(module.allocator);

    if (try context_mod.setLocalValue(context, module.allocator, assignment.name, evaluated)) return;
    if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
    try module.setValue(assignment.name, evaluated);
}

/// Evaluate an initializer and, when it fails because a name is not declared,
/// say which expression carried the name. The error alone cannot carry it, and
/// the location only points at the line.
fn lowerInitializerReporting(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    initializer: ast.ValueInitializer,
    statement_span: source.SourceSpan,
    callbacks: Callbacks,
) LowerError!value_mod.Value {
    return lowerInitializer(module, context, active, initializer, callbacks) catch |err| switch (err) {
        error.UndefinedSymbol => {
            const text = switch (initializer) {
                .expression => |*node| try deferred.renderExpressionText(module.allocator, node),
                .struct_literal => try module.allocator.dupe(u8, "struct literal"),
            };
            defer module.allocator.free(text);
            try reportUndefinedSymbol(module, statement_span, text);
            return error.FrontendDiagnostics;
        },
        else => return err,
    };
}

fn reportUndefinedSymbol(module: *module_mod.Module, span: source.SourceSpan, text: []const u8) LowerError!void {
    // A late-layout block can be lowered again while it converges, so one
    // location must not collect the same message twice.
    for (module.diagnostics.items.items) |item| {
        if (sameLocation(item.span, span)) return;
    }

    const message = try std.fmt.allocPrint(
        module.allocator,
        "undefined name in this expression: {s}",
        .{shorten(text)},
    );
    defer module.allocator.free(message);
    try module.diagnostics.add(module.allocator, .err, span, message);
}

fn sameLocation(left: source.SourceSpan, right: source.SourceSpan) bool {
    if (left.start != right.start) return false;
    const left_source = left.source orelse return right.source == null;
    const right_source = right.source orelse return false;
    return left_source.index == right_source.index;
}

/// Long expressions still have to read as a message.
fn shorten(text: []const u8) []const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const limit: usize = 120;
    return if (trimmed.len <= limit) trimmed else trimmed[0..limit];
}

fn lowerInitializer(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    initializer: ast.ValueInitializer,
    callbacks: Callbacks,
) LowerError!value_mod.Value {
    return switch (initializer) {
        .expression => |*node| callbacks.eval_value_at_context(module.allocator, module, context, active, node),
        .struct_literal => |literal| .{
            .@"struct" = try aggregate_literal.structValueFromLiteral(
                module.allocator,
                module,
                context,
                active,
                literal,
                aggregateCallbacks(callbacks),
            ),
        },
    };
}

fn aggregateCallbacks(callbacks: Callbacks) aggregate_literal.Callbacks {
    return .{
        .eval_integer_at_context = callbacks.eval_integer_at_context,
        .eval_value_at_context = callbacks.eval_value_at_context,
    };
}
