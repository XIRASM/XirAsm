const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const diagnostic_format = @import("diagnostic_format.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    boolean_arg_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError!bool,
    eval_value_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!value_mod.Value,
};

pub fn lowerDiagnostic(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    severity: contracts.DiagnosticSeverity,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len == 0) return error.InvalidApiArity;
    const message = try diagnostic_format.formatDiagnosticMessage(
        allocator,
        module,
        context,
        active,
        call,
        formatCallbacks(callbacks),
    );
    defer allocator.free(message);
    try module.diagnostics.add(allocator, severity, call.span, message);
}

pub fn lowerAssert(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
    if (try callbacks.boolean_arg_at_context(module, context, active, call, 0)) return;

    const message = if (call.args.len == 2)
        try diagnostic_format.formatDiagnosticArgument(allocator, module, context, active, &call.args[1], formatCallbacks(callbacks))
    else
        try allocator.dupe(u8, "assertion failed");
    defer allocator.free(message);

    try module.diagnostics.add(allocator, .err, call.span, message);
    return error.FrontendDiagnostics;
}

fn formatCallbacks(callbacks: Callbacks) diagnostic_format.Callbacks {
    return .{ .eval_value_at_context = callbacks.eval_value_at_context };
}
