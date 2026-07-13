const std = @import("std");

const ast = @import("ast.zig");
const expr = @import("expr.zig");

const Allocator = std.mem.Allocator;

pub const StoreError = Allocator.Error || error{
    DuplicateMetaFunction,
    UnknownMetaFunction,
};

pub const Store = struct {
    items: std.ArrayList(ast.MetaFunctionStatement) = .empty,

    pub fn deinit(self: *Store, allocator: Allocator) void {
        for (self.items.items) |*function| {
            function.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn lookupIndex(self: *const Store, name: []const u8) ?usize {
        for (self.items.items, 0..) |function, index| {
            if (std.mem.eql(u8, function.name, name)) return index;
        }
        return null;
    }

    pub fn get(self: *const Store, index: usize) StoreError!*const ast.MetaFunctionStatement {
        if (index >= self.items.items.len) return error.UnknownMetaFunction;
        return &self.items.items[index];
    }

    pub fn define(
        self: *Store,
        allocator: Allocator,
        declaration: ast.MetaFunctionStatement,
    ) StoreError!void {
        if (self.lookupIndex(declaration.name) != null) return error.DuplicateMetaFunction;

        var cloned = try clone(allocator, declaration);
        errdefer cloned.deinit(allocator);
        try self.items.append(allocator, cloned);
    }
};

pub fn clone(
    allocator: Allocator,
    declaration: ast.MetaFunctionStatement,
) Allocator.Error!ast.MetaFunctionStatement {
    const owned_name = try allocator.dupe(u8, declaration.name);
    errdefer allocator.free(owned_name);

    const owned_return_type_name = if (declaration.return_type_name) |type_name|
        try allocator.dupe(u8, type_name)
    else
        null;
    errdefer if (owned_return_type_name) |type_name| allocator.free(type_name);

    const params = try allocator.alloc(ast.MetaFunctionParam, declaration.params.len);
    var params_len: usize = 0;
    errdefer {
        for (params[0..params_len]) |*param| {
            param.deinit(allocator);
        }
        allocator.free(params);
    }
    for (declaration.params, 0..) |param, index| {
        params[index] = try cloneParam(allocator, param);
        params_len += 1;
    }

    const body = try cloneStatementSlice(allocator, declaration.body);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }

    return .{
        .name = owned_name,
        .params = params,
        .return_type_name = owned_return_type_name,
        .body = body,
        .span = declaration.span,
    };
}

fn cloneParam(
    allocator: Allocator,
    param: ast.MetaFunctionParam,
) Allocator.Error!ast.MetaFunctionParam {
    const owned_name = try allocator.dupe(u8, param.name);
    errdefer allocator.free(owned_name);

    const owned_type_name = if (param.type_name) |type_name|
        try allocator.dupe(u8, type_name)
    else
        null;
    errdefer if (owned_type_name) |type_name| allocator.free(type_name);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .span = param.span,
    };
}

pub fn cloneStatement(
    allocator: Allocator,
    statement: ast.Statement,
) Allocator.Error!ast.Statement {
    return switch (statement) {
        .label => |label| .{ .label = .{
            .name = try allocator.dupe(u8, label.name),
            .span = label.span,
        } },
        .isa_instruction => |instruction| .{ .isa_instruction = .{
            .text = try allocator.dupe(u8, instruction.text),
            .span = instruction.span,
        } },
        .value_decl => |declaration| .{ .value_decl = try cloneValueDeclaration(allocator, declaration) },
        .assignment => |assignment| .{ .assignment = try cloneAssignment(allocator, assignment) },
        .struct_decl => |declaration| .{ .struct_decl = try cloneStructDeclaration(allocator, declaration) },
        .api_call => |call| .{ .api_call = try cloneApiCall(allocator, call) },
        .meta_if => |meta_if| .{ .meta_if = try cloneMetaIf(allocator, meta_if) },
        .meta_while => |meta_while| .{ .meta_while = try cloneMetaWhile(allocator, meta_while) },
        .meta_for_range => |meta_for| .{ .meta_for_range = try cloneMetaForRange(allocator, meta_for) },
        .meta_break => |meta_break| .{ .meta_break = meta_break },
        .meta_continue => |meta_continue| .{ .meta_continue = meta_continue },
        .meta_fn => |meta_fn| .{ .meta_fn = try clone(allocator, meta_fn) },
        .meta_return => |meta_return| .{ .meta_return = .{
            .value = try cloneExpression(allocator, meta_return.value),
            .span = meta_return.span,
        } },
        .meta_block => |block| .{ .meta_block = .{
            .body = try cloneStatementSlice(allocator, block.body),
            .span = block.span,
        } },
        .meta_defer => |meta_defer| .{ .meta_defer = .{
            .body = try cloneStatementSlice(allocator, meta_defer.body),
            .span = meta_defer.span,
        } },
        .late_layout => |late_layout| .{ .late_layout = .{
            .body = try cloneStatementSlice(allocator, late_layout.body),
            .span = late_layout.span,
        } },
        .meta_line => |line| .{ .meta_line = .{
            .text = try allocator.dupe(u8, line.text),
            .span = line.span,
        } },
        .meta_block_start => |span| .{ .meta_block_start = span },
        .meta_block_end => |span| .{ .meta_block_end = span },
    };
}

pub fn cloneStatementSlice(
    allocator: Allocator,
    statements: []const ast.Statement,
) Allocator.Error![]ast.Statement {
    const cloned = try allocator.alloc(ast.Statement, statements.len);
    var cloned_len: usize = 0;
    errdefer {
        for (cloned[0..cloned_len]) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(cloned);
    }

    for (statements, 0..) |statement, index| {
        cloned[index] = try cloneStatement(allocator, statement);
        cloned_len += 1;
    }
    return cloned;
}

fn deinitClonedStatementSlice(allocator: Allocator, statements: []ast.Statement) void {
    for (statements) |*statement| {
        statement.deinit(allocator);
    }
    allocator.free(statements);
}

fn cloneValueDeclaration(
    allocator: Allocator,
    declaration: ast.ValueDeclarationStatement,
) Allocator.Error!ast.ValueDeclarationStatement {
    const owned_name = try allocator.dupe(u8, declaration.name);
    errdefer allocator.free(owned_name);

    const owned_type_name = if (declaration.type_name) |type_name|
        try allocator.dupe(u8, type_name)
    else
        null;
    errdefer if (owned_type_name) |type_name| allocator.free(type_name);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .mutability = declaration.mutability,
        .value = try cloneValueInitializer(allocator, declaration.value),
        .span = declaration.span,
    };
}

fn cloneAssignment(
    allocator: Allocator,
    assignment: ast.AssignmentStatement,
) Allocator.Error!ast.AssignmentStatement {
    const owned_name = try allocator.dupe(u8, assignment.name);
    errdefer allocator.free(owned_name);

    return .{
        .name = owned_name,
        .value = try cloneValueInitializer(allocator, assignment.value),
        .span = assignment.span,
    };
}

fn cloneValueInitializer(
    allocator: Allocator,
    initializer: ast.ValueInitializer,
) Allocator.Error!ast.ValueInitializer {
    return switch (initializer) {
        .expression => |node| .{ .expression = try cloneExpression(allocator, node) },
        .struct_literal => |literal| .{ .struct_literal = try cloneStructLiteral(allocator, literal) },
    };
}

fn cloneStructDeclaration(
    allocator: Allocator,
    declaration: ast.StructDeclarationStatement,
) Allocator.Error!ast.StructDeclarationStatement {
    const owned_name = try allocator.dupe(u8, declaration.name);
    errdefer allocator.free(owned_name);

    const fields = try allocator.alloc(ast.StructFieldSyntax, declaration.fields.len);
    var fields_len: usize = 0;
    errdefer {
        for (fields[0..fields_len]) |*field| {
            field.deinit(allocator);
        }
        allocator.free(fields);
    }
    for (declaration.fields, 0..) |field, index| {
        fields[index] = try cloneStructField(allocator, field);
        fields_len += 1;
    }

    return .{
        .name = owned_name,
        .kind = declaration.kind,
        .policy = declaration.policy,
        .fields = fields,
        .span = declaration.span,
    };
}

fn cloneStructField(
    allocator: Allocator,
    field: ast.StructFieldSyntax,
) Allocator.Error!ast.StructFieldSyntax {
    const owned_name = try allocator.dupe(u8, field.name);
    errdefer allocator.free(owned_name);

    const owned_type_name = try allocator.dupe(u8, field.type_name);
    errdefer allocator.free(owned_type_name);

    const default_value = if (field.default_value) |value|
        try allocator.dupe(u8, value)
    else
        null;
    errdefer if (default_value) |value| allocator.free(value);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .default_value = default_value,
        .span = field.span,
    };
}

fn cloneApiCall(
    allocator: Allocator,
    call: ast.ApiCallStatement,
) Allocator.Error!ast.ApiCallStatement {
    const owned_text = try allocator.dupe(u8, call.text);
    errdefer allocator.free(owned_text);

    const owned_callee = try allocator.dupe(u8, call.callee);
    errdefer allocator.free(owned_callee);

    const args = try allocator.alloc(ast.ApiArgument, call.args.len);
    var args_len: usize = 0;
    errdefer {
        for (args[0..args_len]) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(args);
    }
    for (call.args, 0..) |arg, index| {
        args[index] = try cloneApiArgument(allocator, arg);
        args_len += 1;
    }

    return .{
        .text = owned_text,
        .callee = owned_callee,
        .args = args,
        .span = call.span,
    };
}

fn cloneApiArgument(
    allocator: Allocator,
    arg: ast.ApiArgument,
) Allocator.Error!ast.ApiArgument {
    return switch (arg) {
        .expression => |node| .{ .expression = try cloneExpression(allocator, node) },
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .struct_literal => |literal| .{ .struct_literal = try cloneStructLiteral(allocator, literal) },
    };
}

fn cloneStructLiteral(
    allocator: Allocator,
    literal: ast.StructLiteralArgument,
) Allocator.Error!ast.StructLiteralArgument {
    const owned_type_name = try allocator.dupe(u8, literal.type_name);
    errdefer allocator.free(owned_type_name);

    const fields = try allocator.alloc(ast.StructLiteralField, literal.fields.len);
    var fields_len: usize = 0;
    errdefer {
        for (fields[0..fields_len]) |*field| {
            field.deinit(allocator);
        }
        allocator.free(fields);
    }
    for (literal.fields, 0..) |field, index| {
        fields[index] = try cloneStructLiteralField(allocator, field);
        fields_len += 1;
    }

    return .{
        .type_name = owned_type_name,
        .fields = fields,
    };
}

fn cloneStructLiteralField(
    allocator: Allocator,
    field: ast.StructLiteralField,
) Allocator.Error!ast.StructLiteralField {
    const owned_name = try allocator.dupe(u8, field.name);
    errdefer allocator.free(owned_name);

    return .{
        .name = owned_name,
        .value = try cloneStructLiteralValue(allocator, field.value),
    };
}

fn cloneStructLiteralValue(
    allocator: Allocator,
    value: ast.StructLiteralValue,
) Allocator.Error!ast.StructLiteralValue {
    return switch (value) {
        .expression => |node| .{ .expression = try cloneExpression(allocator, node) },
        .struct_literal => |literal| .{ .struct_literal = try cloneStructLiteral(allocator, literal) },
    };
}

fn cloneMetaIf(allocator: Allocator, meta_if: ast.MetaIfStatement) Allocator.Error!ast.MetaIfStatement {
    const owned_condition = try allocator.dupe(u8, meta_if.condition);
    errdefer allocator.free(owned_condition);

    const body = try cloneStatementSlice(allocator, meta_if.body);
    errdefer deinitClonedStatementSlice(allocator, body);

    const else_body = try cloneStatementSlice(allocator, meta_if.else_body);
    errdefer deinitClonedStatementSlice(allocator, else_body);

    return .{
        .condition = owned_condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn cloneMetaWhile(allocator: Allocator, meta_while: ast.MetaWhileStatement) Allocator.Error!ast.MetaWhileStatement {
    const owned_condition = try allocator.dupe(u8, meta_while.condition);
    errdefer allocator.free(owned_condition);

    return .{
        .condition = owned_condition,
        .body = try cloneStatementSlice(allocator, meta_while.body),
        .span = meta_while.span,
    };
}

fn cloneMetaForRange(allocator: Allocator, meta_for: ast.MetaForRangeStatement) Allocator.Error!ast.MetaForRangeStatement {
    const owned_name = try allocator.dupe(u8, meta_for.name);
    errdefer allocator.free(owned_name);

    var source = try cloneMetaForSource(allocator, meta_for.source);
    errdefer source.deinit(allocator);

    return .{
        .name = owned_name,
        .source = source,
        .body = try cloneStatementSlice(allocator, meta_for.body),
        .span = meta_for.span,
    };
}

fn cloneMetaForSource(allocator: Allocator, source_node: ast.MetaForSource) Allocator.Error!ast.MetaForSource {
    return switch (source_node) {
        .range => |range| range_node: {
            var start = try cloneExpression(allocator, range.start);
            errdefer start.deinit(allocator);

            var end = try cloneExpression(allocator, range.end);
            errdefer end.deinit(allocator);

            break :range_node .{ .range = .{
                .start = start,
                .end = end,
            } };
        },
        .list => |node| .{ .list = try cloneExpression(allocator, node) },
    };
}

fn cloneExpression(allocator: Allocator, node: expr.Node) Allocator.Error!expr.Node {
    return switch (node) {
        .integer => |value| .{ .integer = value },
        .float64 => |value| .{ .float64 = value },
        .boolean => |value| .{ .boolean = value },
        .string_literal => |text| .{ .string_literal = try allocator.dupe(u8, text) },
        .bytes_literal => |bytes| .{ .bytes_literal = try allocator.dupe(u8, bytes) },
        .symbol => |name| .{ .symbol = try allocator.dupe(u8, name) },
        .builtin_call => |call| .{ .builtin_call = try cloneBuiltinCall(allocator, call) },
        .field_access => |field| blk: {
            var object = try cloneExpression(allocator, field.object.*);
            errdefer object.deinit(allocator);
            const owned_field = try allocator.dupe(u8, field.field_name);
            errdefer allocator.free(owned_field);
            const object_ptr = try allocator.create(expr.Node);
            object_ptr.* = object;
            break :blk .{ .field_access = .{
                .object = object_ptr,
                .field_name = owned_field,
            } };
        },
        .unary => |unary| blk: {
            var operand = try cloneExpression(allocator, unary.operand.*);
            errdefer operand.deinit(allocator);
            const operand_ptr = try allocator.create(expr.Node);
            operand_ptr.* = operand;
            break :blk .{ .unary = .{
                .op = unary.op,
                .operand = operand_ptr,
            } };
        },
        .binary => |binary| blk: {
            var left = try cloneExpression(allocator, binary.left.*);
            errdefer left.deinit(allocator);
            var right = try cloneExpression(allocator, binary.right.*);
            errdefer right.deinit(allocator);
            const left_ptr = try allocator.create(expr.Node);
            errdefer allocator.destroy(left_ptr);
            const right_ptr = try allocator.create(expr.Node);
            left_ptr.* = left;
            right_ptr.* = right;
            break :blk .{ .binary = .{
                .left = left_ptr,
                .op = binary.op,
                .right = right_ptr,
            } };
        },
    };
}

fn cloneBuiltinCall(allocator: Allocator, call: expr.BuiltinCall) Allocator.Error!expr.BuiltinCall {
    const owned_name = try allocator.dupe(u8, call.name);
    errdefer allocator.free(owned_name);

    const args = try allocator.alloc(expr.BuiltinArgument, call.args.len);
    var args_len: usize = 0;
    errdefer {
        for (args[0..args_len]) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(args);
    }
    for (call.args, 0..) |arg, index| {
        args[index] = switch (arg) {
            .expression => |node| .{ .expression = try cloneExpression(allocator, node) },
            .identifier => |name| .{ .identifier = try allocator.dupe(u8, name) },
            .struct_literal => |text| .{ .struct_literal = try allocator.dupe(u8, text) },
        };
        args_len += 1;
    }

    return .{
        .name = owned_name,
        .args = args,
    };
}

test "Meta function statement clone deep-copies Meta line text" {
    const allocator = std.testing.allocator;

    const original_text = try allocator.dupe(u8, "let x = 1");
    var original: ast.Statement = .{ .meta_line = .{
        .text = original_text,
        .span = .{},
    } };
    defer original.deinit(allocator);

    var cloned = try cloneStatement(allocator, original);
    defer cloned.deinit(allocator);

    try std.testing.expectEqualStrings(original.meta_line.text, cloned.meta_line.text);
    try std.testing.expect(original.meta_line.text.ptr != cloned.meta_line.text.ptr);
}
