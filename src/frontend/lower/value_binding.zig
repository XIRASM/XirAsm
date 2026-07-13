const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const typecheck = @import("../typecheck.zig");
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

pub fn lowerDeclaration(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    declaration: ast.ValueDeclarationStatement,
    callbacks: Callbacks,
) LowerError!void {
    var evaluated = try lowerInitializer(module, context, active, declaration.value, callbacks);
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
    var evaluated = try lowerInitializer(module, context, active, assignment.value, callbacks);
    errdefer evaluated.deinit(module.allocator);

    if (try context_mod.setLocalValue(context, module.allocator, assignment.name, evaluated)) return;
    if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
    try module.setValue(assignment.name, evaluated);
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
