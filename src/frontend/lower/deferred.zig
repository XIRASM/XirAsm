const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const output_mod = @import("../output/root.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const diagnostic_format = @import("diagnostic_format.zig");
const expression_bridge = @import("expression_bridge.zig");

const Allocator = std.mem.Allocator;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    is_allowed_api: *const fn (callee: []const u8) bool,
};

const lookupLocalValue = context_mod.lookupLocalValue;
const mapExpressionError = expression_bridge.mapExpressionError;
const formatStringLiteral = diagnostic_format.formatStringLiteral;
const formatBytesValue = diagnostic_format.formatBytesValue;

pub fn cloneBlockFromAst(
    allocator: Allocator,
    meta_defer: ast.MetaDeferStatement,
    callbacks: Callbacks,
) LowerError!output_mod.DeferredBlock {
    const body = try cloneStatementSlice(allocator, meta_defer.body, callbacks);
    return .{
        .body = body,
        .span = meta_defer.span,
    };
}

pub fn freezeBlockFromAst(
    allocator: Allocator,
    context: *LowerContext,
    meta_defer: ast.MetaDeferStatement,
    callbacks: Callbacks,
) LowerError!output_mod.DeferredBlock {
    const body = try freezeStatementSlice(allocator, context, meta_defer.body, callbacks);
    return .{
        .body = body,
        .span = meta_defer.span,
    };
}

fn cloneStatementSlice(
    allocator: Allocator,
    statements: []const ast.Statement,
    callbacks: Callbacks,
) LowerError![]output_mod.DeferredStatement {
    const cloned = try allocator.alloc(output_mod.DeferredStatement, statements.len);
    var cloned_len: usize = 0;
    errdefer {
        for (cloned[0..cloned_len]) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(cloned);
    }

    for (statements, 0..) |statement, index| {
        cloned[index] = try cloneStatement(allocator, statement, callbacks);
        cloned_len += 1;
    }
    return cloned;
}

fn freezeStatementSlice(
    allocator: Allocator,
    context: *LowerContext,
    statements: []const ast.Statement,
    callbacks: Callbacks,
) LowerError![]output_mod.DeferredStatement {
    var frozen: std.ArrayList(output_mod.DeferredStatement) = .empty;
    errdefer {
        for (frozen.items) |*statement| {
            statement.deinit(allocator);
        }
        frozen.deinit(allocator);
    }

    for (statements) |statement| {
        try freezeStatementAppend(allocator, context, statement, &frozen, callbacks);
    }

    return frozen.toOwnedSlice(allocator);
}

fn cloneStatement(
    allocator: Allocator,
    statement: ast.Statement,
    callbacks: Callbacks,
) LowerError!output_mod.DeferredStatement {
    return switch (statement) {
        .api_call => |call| .{ .api_call = try cloneApiCall(allocator, call, callbacks) },
        .meta_if => |meta_if| .{ .meta_if = try cloneMetaIf(allocator, meta_if, callbacks) },
        // api-matrix-output: DeferredStatement.value_decl
        .value_decl => |declaration| .{ .value_decl = try cloneValueDeclaration(allocator, declaration) },
        // api-matrix-output: DeferredStatement.assignment
        .assignment => |assignment| .{ .assignment = try cloneAssignment(allocator, assignment) },
        // api-matrix-output: DeferredStatement.meta_while
        .meta_while => |meta_while| .{ .meta_while = try cloneMetaWhile(allocator, meta_while, callbacks) },
        .meta_break => |meta_break| .{ .meta_break = meta_break.span },
        .meta_continue => |meta_continue| .{ .meta_continue = meta_continue.span },
        .label,
        .isa_instruction,
        .struct_decl,
        .legacy_directive,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => error.FinalizerCannotChangeLayout,
    };
}

fn freezeStatementAppend(
    allocator: Allocator,
    context: *LowerContext,
    statement: ast.Statement,
    frozen: *std.ArrayList(output_mod.DeferredStatement),
    callbacks: Callbacks,
) LowerError!void {
    switch (statement) {
        .api_call => |call| {
            var frozen_call = try freezeApiCall(allocator, context, call, callbacks);
            errdefer frozen_call.deinit(allocator);
            try frozen.append(allocator, .{ .api_call = frozen_call });
        },
        // api-matrix-output: DeferredStatement.value_decl
        .value_decl => |declaration| {
            var frozen_declaration = try freezeValueDeclaration(allocator, context, declaration);
            errdefer frozen_declaration.deinit(allocator);
            try frozen.append(allocator, .{ .value_decl = frozen_declaration });
        },
        // api-matrix-output: DeferredStatement.assignment
        .assignment => |assignment| {
            var frozen_assignment = try freezeAssignment(allocator, context, assignment);
            errdefer frozen_assignment.deinit(allocator);
            try frozen.append(allocator, .{ .assignment = frozen_assignment });
        },
        .meta_if => |meta_if| {
            var frozen_if = try freezeMetaIf(allocator, context, meta_if, callbacks);
            errdefer frozen_if.deinit(allocator);
            try frozen.append(allocator, .{ .meta_if = frozen_if });
        },
        // api-matrix-output: DeferredStatement.meta_while
        .meta_while => |meta_while| {
            var frozen_while = try freezeMetaWhile(allocator, context, meta_while, callbacks);
            errdefer frozen_while.deinit(allocator);
            try frozen.append(allocator, .{ .meta_while = frozen_while });
        },
        .meta_break => |meta_break| try frozen.append(allocator, .{ .meta_break = meta_break.span }),
        .meta_continue => |meta_continue| try frozen.append(allocator, .{ .meta_continue = meta_continue.span }),
        .label,
        .isa_instruction,
        .struct_decl,
        .legacy_directive,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => return error.FinalizerCannotChangeLayout,
    }
}

fn cloneApiCall(
    allocator: Allocator,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!output_mod.ApiCall {
    if (!callbacks.is_allowed_api(call.callee)) return error.FinalizerCannotChangeLayout;
    return .{
        .text = try allocator.dupe(u8, call.text),
        .span = call.span,
    };
}

fn cloneValueDeclaration(
    allocator: Allocator,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const cloned = try cloneValueDeclarationWithContext(allocator, null, declaration);
    return .{
        .name = cloned.name,
        .type_name = cloned.type_name,
        .mutability = cloned.mutability,
        .value_text = cloned.value_text,
        .span = declaration.span,
    };
}

fn cloneAssignment(
    allocator: Allocator,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const cloned = try cloneAssignmentWithContext(allocator, null, assignment);
    return .{
        .name = cloned.name,
        .value_text = cloned.value_text,
        .span = assignment.span,
    };
}

fn freezeValueDeclaration(
    allocator: Allocator,
    context: *LowerContext,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const cloned = try cloneValueDeclarationWithContext(allocator, context, declaration);
    return .{
        .name = cloned.name,
        .type_name = cloned.type_name,
        .mutability = cloned.mutability,
        .value_text = cloned.value_text,
        .span = declaration.span,
    };
}

fn freezeAssignment(
    allocator: Allocator,
    context: *LowerContext,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const cloned = try cloneAssignmentWithContext(allocator, context, assignment);
    return .{
        .name = cloned.name,
        .value_text = cloned.value_text,
        .span = assignment.span,
    };
}

fn cloneValueDeclarationWithContext(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const name = try allocator.dupe(u8, declaration.name);
    errdefer allocator.free(name);

    const type_name = if (declaration.type_name) |parsed_type|
        try allocator.dupe(u8, parsed_type)
    else
        null;
    errdefer if (type_name) |owned| allocator.free(owned);

    const value_text = try renderInitializer(allocator, maybe_context, declaration.value);
    return .{
        .name = name,
        .type_name = type_name,
        .mutability = declaration.mutability,
        .value_text = value_text,
        .span = declaration.span,
    };
}

fn cloneAssignmentWithContext(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const name = try allocator.dupe(u8, assignment.name);
    errdefer allocator.free(name);

    const value_text = try renderInitializer(allocator, maybe_context, assignment.value);
    return .{
        .name = name,
        .value_text = value_text,
        .span = assignment.span,
    };
}

fn freezeApiCall(
    allocator: Allocator,
    context: *LowerContext,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!output_mod.ApiCall {
    if (!callbacks.is_allowed_api(call.callee)) return error.FinalizerCannotChangeLayout;

    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);

    try text.appendSlice(allocator, call.callee);
    try text.append(allocator, '(');
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try text.appendSlice(allocator, ", ");
        const rendered = try renderFrozenArgument(allocator, context, arg);
        defer allocator.free(rendered);
        try text.appendSlice(allocator, rendered);
    }
    try text.append(allocator, ')');

    return .{
        .text = try text.toOwnedSlice(allocator),
        .span = call.span,
    };
}

fn cloneMetaIf(
    allocator: Allocator,
    meta_if: ast.MetaIfStatement,
    callbacks: Callbacks,
) LowerError!output_mod.MetaIf {
    const condition = try allocator.dupe(u8, meta_if.condition);
    errdefer allocator.free(condition);
    const body = try cloneStatementSlice(allocator, meta_if.body, callbacks);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }
    const else_body = try cloneStatementSlice(allocator, meta_if.else_body, callbacks);
    return .{
        .condition = condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn cloneMetaWhile(
    allocator: Allocator,
    meta_while: ast.MetaWhileStatement,
    callbacks: Callbacks,
) LowerError!output_mod.MetaWhile {
    const condition = try allocator.dupe(u8, meta_while.condition);
    errdefer allocator.free(condition);
    const body = try cloneStatementSlice(allocator, meta_while.body, callbacks);
    return .{
        .condition = condition,
        .body = body,
        .span = meta_while.span,
    };
}

fn freezeMetaIf(
    allocator: Allocator,
    context: *LowerContext,
    meta_if: ast.MetaIfStatement,
    callbacks: Callbacks,
) LowerError!output_mod.MetaIf {
    const condition = try renderCondition(allocator, context, meta_if.condition);
    errdefer allocator.free(condition);
    const body = try freezeStatementSlice(allocator, context, meta_if.body, callbacks);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }
    const else_body = try freezeStatementSlice(allocator, context, meta_if.else_body, callbacks);
    return .{
        .condition = condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn freezeMetaWhile(
    allocator: Allocator,
    context: *LowerContext,
    meta_while: ast.MetaWhileStatement,
    callbacks: Callbacks,
) LowerError!output_mod.MetaWhile {
    const condition = try renderCondition(allocator, context, meta_while.condition);
    errdefer allocator.free(condition);
    const body = try freezeStatementSlice(allocator, context, meta_while.body, callbacks);
    return .{
        .condition = condition,
        .body = body,
        .span = meta_while.span,
    };
}

pub fn renderFrozenArgument(
    allocator: Allocator,
    context: *LowerContext,
    arg: *const ast.ApiArgument,
) LowerError![]u8 {
    return switch (arg.*) {
        .expression => |*node| renderFrozenExpression(allocator, context, node),
        .string => |text| formatStringLiteral(allocator, text),
        .struct_literal => return error.InvalidApiArgument,
    };
}

pub fn renderCondition(allocator: Allocator, maybe_context: ?*LowerContext, condition: []const u8) LowerError![]u8 {
    const trimmed = std.mem.trim(u8, condition, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidMetaIf;
    const context = maybe_context orelse return allocator.dupe(u8, trimmed);

    var node = expr.parseOwned(allocator, trimmed) catch |err| return mapExpressionError(err);
    defer node.deinit(allocator);
    return renderFrozenExpression(allocator, context, &node);
}

fn renderInitializer(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    initializer: ast.ValueInitializer,
) LowerError![]u8 {
    return switch (initializer) {
        .expression => |*node| if (maybe_context) |context|
            renderFrozenExpression(allocator, context, node)
        else
            renderExpressionSource(allocator, null, node),
        .struct_literal => error.InvalidApiArgument,
    };
}

fn renderFrozenValue(allocator: Allocator, value: value_mod.Value) LowerError![]u8 {
    return switch (value) {
        .integer => |integer| try std.fmt.allocPrint(allocator, "{}", .{integer.value}),
        .boolean => |boolean| try allocator.dupe(u8, if (boolean) "true" else "false"),
        .string => |text| try formatStringLiteral(allocator, text),
        .bytes => |bytes| try formatBytesValue(allocator, bytes),
        .void, .type, .@"struct", .list, .map => error.InvalidApiArgument,
    };
}

fn renderFrozenExpression(
    allocator: Allocator,
    context: *LowerContext,
    node: *const expr.Node,
) LowerError![]u8 {
    switch (node.*) {
        .symbol => |name| {
            if (lookupLocalValue(context, name)) |value| {
                return renderFrozenValue(allocator, value.*);
            }
        },
        else => {},
    }
    return renderExpressionSource(allocator, context, node);
}

fn renderExpressionSource(allocator: Allocator, maybe_context: ?*LowerContext, node: *const expr.Node) LowerError![]u8 {
    return switch (node.*) {
        .integer => |value| std.fmt.allocPrint(allocator, "{}", .{value}),
        .boolean => |value| allocator.dupe(u8, if (value) "true" else "false"),
        .string_literal => |text| formatStringLiteral(allocator, text),
        .bytes_literal => |bytes| formatBytesValue(allocator, bytes),
        .symbol => |name| allocator.dupe(u8, name),
        .field_access => |access| renderFieldAccessSource(allocator, maybe_context, access),
        .builtin_call => |call| renderBuiltinCallSource(allocator, maybe_context, call),
        .unary => |unary| renderUnarySource(allocator, maybe_context, unary),
        .binary => |binary| renderBinarySource(allocator, maybe_context, binary),
    };
}

fn renderFieldAccessSource(allocator: Allocator, maybe_context: ?*LowerContext, access: expr.FieldAccess) LowerError![]u8 {
    const object = if (maybe_context) |context|
        try renderFrozenExpression(allocator, context, access.object)
    else
        try renderExpressionSource(allocator, null, access.object);
    defer allocator.free(object);
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ object, access.field_name });
}

fn renderBuiltinCallSource(allocator: Allocator, maybe_context: ?*LowerContext, call: expr.BuiltinCall) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, call.name);
    try result.append(allocator, '(');
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try result.appendSlice(allocator, ", ");
        const text = try renderBuiltinArgumentSource(allocator, maybe_context, arg);
        defer allocator.free(text);
        try result.appendSlice(allocator, text);
    }
    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

fn renderBuiltinArgumentSource(allocator: Allocator, maybe_context: ?*LowerContext, arg: *const expr.BuiltinArgument) LowerError![]u8 {
    return switch (arg.*) {
        .expression => |*node| if (maybe_context) |context|
            renderFrozenExpression(allocator, context, node)
        else
            renderExpressionSource(allocator, null, node),
        .identifier => |name| {
            if (maybe_context) |context| {
                if (lookupLocalValue(context, name)) |value| {
                    return renderFrozenValue(allocator, value.*);
                }
            }
            return allocator.dupe(u8, name);
        },
        .struct_literal => return error.InvalidApiArgument,
    };
}

fn renderUnarySource(allocator: Allocator, maybe_context: ?*LowerContext, unary: expr.Unary) LowerError![]u8 {
    const operand = if (maybe_context) |context|
        try renderFrozenExpression(allocator, context, unary.operand)
    else
        try renderExpressionSource(allocator, null, unary.operand);
    defer allocator.free(operand);
    return switch (unary.op) {
        .plus => std.fmt.allocPrint(allocator, "(+{s})", .{operand}),
        .neg => std.fmt.allocPrint(allocator, "(-{s})", .{operand}),
        .bit_not => std.fmt.allocPrint(allocator, "(~{s})", .{operand}),
        .logical_not => std.fmt.allocPrint(allocator, "(!{s})", .{operand}),
        .lengthof => std.fmt.allocPrint(allocator, "(lengthof {s})", .{operand}),
    };
}

fn renderBinarySource(allocator: Allocator, maybe_context: ?*LowerContext, binary: expr.Binary) LowerError![]u8 {
    const left = if (maybe_context) |context|
        try renderFrozenExpression(allocator, context, binary.left)
    else
        try renderExpressionSource(allocator, null, binary.left);
    defer allocator.free(left);
    const right = if (maybe_context) |context|
        try renderFrozenExpression(allocator, context, binary.right)
    else
        try renderExpressionSource(allocator, null, binary.right);
    defer allocator.free(right);
    return std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, binaryOperatorText(binary.op), right });
}

fn binaryOperatorText(op: expr.BinaryOp) []const u8 {
    return switch (op) {
        .logical_or => "||",
        .logical_and => "&&",
        .equal => "==",
        .not_equal => "!=",
        .less_than => "<",
        .less_equal => "<=",
        .greater_than => ">",
        .greater_equal => ">=",
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .shl => "<<",
        .shr => ">>",
        .bit_and => "&",
        .bit_or => "|",
        .bit_xor => "^",
    };
}
