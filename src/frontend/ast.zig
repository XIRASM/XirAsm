const std = @import("std");

const expr = @import("expr.zig");
const source = @import("source.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const StatementId = struct {
    index: u32,
};

pub const LabelStatement = struct {
    name: []u8,
    span: source.SourceSpan,
};

pub const IsaInstructionStatement = struct {
    text: []u8,
    span: source.SourceSpan,
};

pub const MetaLineStatement = struct {
    text: []u8,
    span: source.SourceSpan,
};

pub const MetaIfStatement = struct {
    condition: []u8,
    body: []Statement,
    else_body: []Statement = &.{},
    span: source.SourceSpan,

    pub fn deinit(self: *MetaIfStatement, allocator: Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        for (self.else_body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.else_body);
        self.* = undefined;
    }
};

pub const MetaWhileStatement = struct {
    condition: []u8,
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaWhileStatement, allocator: Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const MetaBreakStatement = struct {
    span: source.SourceSpan,
};

pub const MetaContinueStatement = struct {
    span: source.SourceSpan,
};

pub const MetaForSource = union(enum) {
    range: struct {
        start: expr.Node,
        end: expr.Node,
    },
    list: expr.Node,

    pub fn deinit(self: *MetaForSource, allocator: Allocator) void {
        switch (self.*) {
            .range => |*range| {
                range.start.deinit(allocator);
                range.end.deinit(allocator);
            },
            .list => |*node| node.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const MetaForRangeStatement = struct {
    name: []u8,
    source: MetaForSource,
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaForRangeStatement, allocator: Allocator) void {
        allocator.free(self.name);
        self.source.deinit(allocator);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const MetaFunctionParam = struct {
    name: []u8,
    type_name: ?[]u8 = null,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaFunctionParam, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.type_name) |type_name| {
            allocator.free(type_name);
        }
        self.* = undefined;
    }
};

pub const MetaFunctionStatement = struct {
    name: []u8,
    params: []MetaFunctionParam,
    return_type_name: ?[]u8 = null,
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaFunctionStatement, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.return_type_name) |type_name| {
            allocator.free(type_name);
        }
        for (self.params) |*param| {
            param.deinit(allocator);
        }
        allocator.free(self.params);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const MetaReturnStatement = struct {
    value: expr.Node,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaReturnStatement, allocator: Allocator) void {
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const MetaBlockStatement = struct {
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaBlockStatement, allocator: Allocator) void {
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const MetaDeferStatement = struct {
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaDeferStatement, allocator: Allocator) void {
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const LateLayoutStatement = struct {
    body: []Statement,
    span: source.SourceSpan,

    pub fn deinit(self: *LateLayoutStatement, allocator: Allocator) void {
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const StructSyntaxPolicy = enum {
    natural,
    @"packed",
};

pub const AggregateSyntaxKind = enum {
    @"struct",
    @"union",
};

pub const StructFieldSyntax = struct {
    name: []u8,
    type_name: []u8,
    default_value: ?[]u8 = null,
    span: source.SourceSpan,

    pub fn deinit(self: *StructFieldSyntax, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.type_name);
        if (self.default_value) |value| {
            allocator.free(value);
        }
        self.* = undefined;
    }
};

pub const StructDeclarationStatement = struct {
    name: []u8,
    kind: AggregateSyntaxKind = .@"struct",
    policy: StructSyntaxPolicy,
    fields: []StructFieldSyntax,
    span: source.SourceSpan,

    pub fn deinit(self: *StructDeclarationStatement, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }
};

pub const ValueDeclarationStatement = struct {
    name: []u8,
    type_name: ?[]u8 = null,
    mutability: value_mod.Mutability,
    value: ValueInitializer,
    span: source.SourceSpan,

    pub fn deinit(self: *ValueDeclarationStatement, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.type_name) |type_name| {
            allocator.free(type_name);
        }
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const AssignmentStatement = struct {
    name: []u8,
    value: ValueInitializer,
    span: source.SourceSpan,

    pub fn deinit(self: *AssignmentStatement, allocator: Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const ValueInitializer = union(enum) {
    expression: expr.Node,
    struct_literal: StructLiteralArgument,

    pub fn deinit(self: *ValueInitializer, allocator: Allocator) void {
        switch (self.*) {
            .expression => |*node| node.deinit(allocator),
            .struct_literal => |*literal| literal.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const ApiArgument = union(enum) {
    expression: expr.Node,
    string: []u8,
    struct_literal: StructLiteralArgument,

    pub fn deinit(self: *ApiArgument, allocator: Allocator) void {
        switch (self.*) {
            .expression => |*node| node.deinit(allocator),
            .string => |text| allocator.free(text),
            .struct_literal => |*literal| literal.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const StructLiteralField = struct {
    name: []u8,
    value: StructLiteralValue,

    pub fn deinit(self: *StructLiteralField, allocator: Allocator) void {
        allocator.free(self.name);
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

pub const StructLiteralValue = union(enum) {
    expression: expr.Node,
    struct_literal: StructLiteralArgument,

    pub fn deinit(self: *StructLiteralValue, allocator: Allocator) void {
        switch (self.*) {
            .expression => |*node| node.deinit(allocator),
            .struct_literal => |*literal| literal.deinit(allocator),
        }
        self.* = undefined;
    }
};

pub const StructLiteralArgument = struct {
    type_name: []u8,
    fields: []StructLiteralField,

    pub fn deinit(self: *StructLiteralArgument, allocator: Allocator) void {
        allocator.free(self.type_name);
        for (self.fields) |*field| {
            field.deinit(allocator);
        }
        allocator.free(self.fields);
        self.* = undefined;
    }
};

pub const ApiCallStatement = struct {
    text: []u8,
    callee: []u8,
    args: []ApiArgument,
    span: source.SourceSpan,

    pub fn deinit(self: *ApiCallStatement, allocator: Allocator) void {
        allocator.free(self.text);
        allocator.free(self.callee);
        for (self.args) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.args);
        self.* = undefined;
    }
};

pub const Statement = union(enum) {
    label: LabelStatement,
    isa_instruction: IsaInstructionStatement,
    value_decl: ValueDeclarationStatement,
    assignment: AssignmentStatement,
    struct_decl: StructDeclarationStatement,
    api_call: ApiCallStatement,
    meta_if: MetaIfStatement,
    meta_while: MetaWhileStatement,
    meta_for_range: MetaForRangeStatement,
    meta_break: MetaBreakStatement,
    meta_continue: MetaContinueStatement,
    meta_fn: MetaFunctionStatement,
    meta_return: MetaReturnStatement,
    meta_block: MetaBlockStatement,
    meta_defer: MetaDeferStatement,
    late_layout: LateLayoutStatement,
    meta_line: MetaLineStatement,
    meta_block_start: source.SourceSpan,
    meta_block_end: source.SourceSpan,

    pub fn deinit(self: *Statement, allocator: Allocator) void {
        switch (self.*) {
            .label => |statement| allocator.free(statement.name),
            .isa_instruction => |statement| allocator.free(statement.text),
            .value_decl => |*statement| statement.deinit(allocator),
            .assignment => |*statement| statement.deinit(allocator),
            .struct_decl => |*statement| statement.deinit(allocator),
            .api_call => |*statement| statement.deinit(allocator),
            .meta_if => |*statement| statement.deinit(allocator),
            .meta_while => |*statement| statement.deinit(allocator),
            .meta_for_range => |*statement| statement.deinit(allocator),
            .meta_break, .meta_continue => {},
            .meta_fn => |*statement| statement.deinit(allocator),
            .meta_return => |*statement| statement.deinit(allocator),
            .meta_block => |*statement| statement.deinit(allocator),
            .meta_defer => |*statement| statement.deinit(allocator),
            .late_layout => |*statement| statement.deinit(allocator),
            .meta_line => |statement| allocator.free(statement.text),
            .meta_block_start, .meta_block_end => {},
        }
        self.* = undefined;
    }

    pub fn span(self: Statement) source.SourceSpan {
        return switch (self) {
            .label => |statement| statement.span,
            .isa_instruction => |statement| statement.span,
            .value_decl => |statement| statement.span,
            .assignment => |statement| statement.span,
            .struct_decl => |statement| statement.span,
            .api_call => |statement| statement.span,
            .meta_if => |statement| statement.span,
            .meta_while => |statement| statement.span,
            .meta_for_range => |statement| statement.span,
            .meta_break => |statement| statement.span,
            .meta_continue => |statement| statement.span,
            .meta_fn => |statement| statement.span,
            .meta_return => |statement| statement.span,
            .meta_block => |statement| statement.span,
            .meta_defer => |statement| statement.span,
            .late_layout => |statement| statement.span,
            .meta_line => |statement| statement.span,
            .meta_block_start => |statement_span| statement_span,
            .meta_block_end => |statement_span| statement_span,
        };
    }
};

pub const StatementList = struct {
    items: std.ArrayList(Statement) = .empty,

    pub fn deinit(self: *StatementList, allocator: Allocator) void {
        for (self.items.items) |*statement| {
            statement.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(self: *StatementList, allocator: Allocator, statement: Statement) !StatementId {
        const id = try nextStatementId(self.items.items.len);
        try self.items.append(allocator, statement);
        return id;
    }

    pub fn append(self: *StatementList, allocator: Allocator, statement: Statement) !void {
        if (self.items.items.len > std.math.maxInt(u32)) return error.TooManyStatements;
        try self.items.append(allocator, statement);
    }
};

fn nextStatementId(len: usize) error{TooManyStatements}!StatementId {
    if (len > std.math.maxInt(u32)) return error.TooManyStatements;
    return .{ .index = @intCast(len) };
}
