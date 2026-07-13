const std = @import("std");

const ast = @import("ast.zig");
const expr = @import("expr.zig");
const identifier = @import("identifier.zig");
const lexer = @import("lexer.zig");
const source = @import("source.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const ParseError = Allocator.Error || error{
    SourceTooLarge,
    InvalidLabel,
    InvalidApiCall,
    InvalidApiArgument,
    InvalidExpression,
    InvalidValueDeclaration,
    InvalidStructDeclaration,
    InvalidStructField,
    UnionFieldDefaultNotAllowed,
    InvalidMetaBlock,
    InvalidMetaDefer,
    InvalidLateLayout,
    InvalidMetaFor,
    InvalidMetaFunction,
    InvalidMetaIf,
    InvalidMetaWhile,
    UnexpectedEndOfMetaBlock,
    UnexpectedEndOfMetaDefer,
    UnexpectedEndOfLateLayout,
    UnexpectedEndOfMetaFor,
    UnexpectedEndOfMetaFunction,
    UnexpectedEndOfStruct,
    UnexpectedEndOfMetaIf,
    UnexpectedEndOfMetaWhile,
    TooManyStatements,
    UnexpectedEndOfStatement,
    LegacyDirectiveSyntax,
};

const statement_ws = " \t\r\n";

pub const Parser = struct {
    allocator: Allocator,
    lexer: lexer.Lexer,
    last_error_span: ?source.SourceSpan = null,

    pub fn init(allocator: Allocator, input: []const u8) Parser {
        return .{
            .allocator = allocator,
            .lexer = lexer.Lexer.init(input),
        };
    }

    pub fn initWithSource(allocator: Allocator, source_id: source.SourceId, input: []const u8) Parser {
        return .{
            .allocator = allocator,
            .lexer = lexer.Lexer.initWithSource(source_id, input),
        };
    }

    pub fn parse(self: *Parser) ParseError!ast.StatementList {
        var statements: ast.StatementList = .{};
        errdefer statements.deinit(self.allocator);

        while (!self.lexer.done()) {
            var token = try self.lexer.next();
            var owned_token_text: ?[]u8 = null;
            defer if (owned_token_text) |text| self.allocator.free(text);

            if (statementCanContinue(token)) {
                if (try self.collectContinuedStatement(token)) |continued_text| {
                    owned_token_text = continued_text;
                    token.text = continued_text;
                }
            }

            switch (token.kind) {
                .blank, .comment => {},
                .label => try appendLabel(&statements, self.allocator, token),
                .isa_line => try appendOwnedText(&statements, self.allocator, .isa_line, token),
                .api_call => try appendApiCall(&statements, self.allocator, token),
                .invalid_directive => return self.rejectBareDirective(token),
                .meta_line => {
                    if (looksLikeStructStart(token.text)) {
                        try appendStructDeclaration(self, &statements, token);
                    } else if (looksLikeMetaFunctionStart(token.text)) {
                        try appendMetaFunctionStatement(self, &statements, token);
                    } else if (looksLikeMetaForStart(token.text)) {
                        try appendMetaForStatement(self, &statements, token);
                    } else if (looksLikeMetaWhileStart(token.text)) {
                        try appendMetaWhileStatement(self, &statements, token);
                    } else if (looksLikeLateLayoutStart(token.text)) {
                        try appendLateLayoutStatement(self, &statements, token);
                    } else if (looksLikeMetaDeferStart(token.text)) {
                        try appendMetaDeferStatement(self, &statements, token);
                    } else if (looksLikeMetaIfStart(token.text)) {
                        try appendMetaIfStatement(self, &statements, token);
                    } else if (looksLikeMetaBreak(token.text)) {
                        try statements.append(self.allocator, .{ .meta_break = .{ .span = token.span } });
                    } else if (looksLikeMetaContinue(token.text)) {
                        try statements.append(self.allocator, .{ .meta_continue = .{ .span = token.span } });
                    } else if (looksLikeValueDeclaration(token.text)) {
                        try appendValueDeclaration(&statements, self.allocator, token);
                    } else if (identifier.looksLikeAssignment(token.text)) {
                        try appendAssignment(&statements, self.allocator, token);
                    } else if (looksLikeMetaReturn(token.text)) {
                        try appendMetaReturn(&statements, self.allocator, token);
                    } else {
                        try appendOwnedText(&statements, self.allocator, .meta_line, token);
                    }
                },
                .meta_block_start => {
                    try appendMetaBlockStatement(self, &statements, token);
                },
                .meta_block_end => {
                    try statements.append(self.allocator, .{ .meta_block_end = token.span });
                },
            }
        }

        return statements;
    }

    pub fn errorSpan(self: *const Parser) ?source.SourceSpan {
        return self.last_error_span;
    }

    fn rejectBareDirective(self: *Parser, token: lexer.Token) ParseError {
        self.last_error_span = token.span;
        return error.LegacyDirectiveSyntax;
    }

    fn collectContinuedStatement(self: *Parser, token: lexer.Token) ParseError!?[]u8 {
        var balance = try scanStatementBalance(token.text, .{});
        if (!balance.needsContinuation()) return null;

        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(self.allocator);
        try text.appendSlice(self.allocator, token.text);

        while (balance.needsContinuation()) {
            if (self.lexer.done()) return error.UnexpectedEndOfStatement;
            const next_token = try self.lexer.next();
            if (next_token.kind == .blank or next_token.kind == .comment) continue;

            try text.append(self.allocator, '\n');
            try text.appendSlice(self.allocator, next_token.text);
            balance = try scanStatementBalance(next_token.text, balance);
        }

        return try text.toOwnedSlice(self.allocator);
    }
};

fn statementCanContinue(token: lexer.Token) bool {
    return token.kind == .api_call or
        (token.kind == .meta_line and
            (looksLikeValueDeclaration(token.text) or looksLikeMetaReturn(token.text)));
}

const StatementBalance = struct {
    paren_depth: u32 = 0,
    brace_depth: u32 = 0,
    in_string: ?u8 = null,

    fn needsContinuation(self: StatementBalance) bool {
        return self.paren_depth != 0 or self.brace_depth != 0 or self.in_string != null;
    }
};

fn scanStatementBalance(text: []const u8, initial: StatementBalance) ParseError!StatementBalance {
    var balance = initial;
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const byte = text[index];
        if (balance.in_string) |quote| {
            if (byte == quote) {
                if (index + 1 < text.len and text[index + 1] == quote) {
                    index += 1;
                    continue;
                }
                balance.in_string = null;
            }
            continue;
        }

        switch (byte) {
            '"', '\'' => balance.in_string = byte,
            '(' => balance.paren_depth += 1,
            ')' => {
                if (balance.paren_depth == 0) return error.InvalidExpression;
                balance.paren_depth -= 1;
            },
            '{' => balance.brace_depth += 1,
            '}' => {
                if (balance.brace_depth == 0) return error.InvalidExpression;
                balance.brace_depth -= 1;
            },
            else => {},
        }
    }
    return balance;
}

fn appendLabel(
    statements: *ast.StatementList,
    allocator: Allocator,
    token: lexer.Token,
) ParseError!void {
    if (token.text.len < 2 or token.text[token.text.len - 1] != ':') return error.InvalidLabel;
    const label_name = token.text[0 .. token.text.len - 1];
    const owned_name = try allocator.dupe(u8, label_name);
    errdefer allocator.free(owned_name);

    try statements.append(allocator, .{
        .label = .{
            .name = owned_name,
            .span = token.span,
        },
    });
}

fn appendValueDeclaration(
    statements: *ast.StatementList,
    allocator: Allocator,
    token: lexer.Token,
) ParseError!void {
    var declaration = try parseValueDeclaration(allocator, token.text, token.span);
    errdefer declaration.deinit(allocator);

    try statements.append(allocator, .{ .value_decl = declaration });
}

fn appendAssignment(
    statements: *ast.StatementList,
    allocator: Allocator,
    token: lexer.Token,
) ParseError!void {
    var assignment = try parseAssignment(allocator, token.text, token.span);
    errdefer assignment.deinit(allocator);

    try statements.append(allocator, .{ .assignment = assignment });
}

fn appendOwnedText(
    statements: *ast.StatementList,
    allocator: Allocator,
    comptime kind: lexer.TokenKind,
    token: lexer.Token,
) ParseError!void {
    const owned_text = try allocator.dupe(u8, token.text);
    errdefer allocator.free(owned_text);

    switch (kind) {
        .isa_line => {
            try statements.append(allocator, .{
                .isa_instruction = .{
                    .text = owned_text,
                    .span = token.span,
                },
            });
        },
        .meta_line => {
            try statements.append(allocator, .{
                .meta_line = .{
                    .text = owned_text,
                    .span = token.span,
                },
            });
        },
        else => {
            @compileError("appendOwnedText supports only text-like line tokens");
        },
    }
}

fn appendApiCall(
    statements: *ast.StatementList,
    allocator: Allocator,
    token: lexer.Token,
) ParseError!void {
    var parsed = try parseApiCall(allocator, token.text, token.span);
    errdefer parsed.deinit(allocator);

    try statements.append(allocator, .{
        .api_call = parsed,
    });
}

fn appendMetaReturn(
    statements: *ast.StatementList,
    allocator: Allocator,
    token: lexer.Token,
) ParseError!void {
    var statement = try parseMetaReturn(allocator, token.text, token.span);
    errdefer statement.deinit(allocator);

    try statements.append(allocator, .{ .meta_return = statement });
}

fn appendStructDeclaration(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var declaration = try parseStructStart(parser.allocator, start_token.text, start_token.span);
    errdefer declaration.deinit(parser.allocator);

    var fields: std.ArrayList(ast.StructFieldSyntax) = .empty;
    errdefer deinitStructFields(parser.allocator, &fields);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                declaration.fields = try fields.toOwnedSlice(parser.allocator);
                try statements.append(parser.allocator, .{ .struct_decl = declaration });
                return;
            },
            .isa_line, .meta_line => {
                var field = try parseStructField(parser.allocator, token.text, token.span);
                if (declaration.kind == .@"union" and field.default_value != null) {
                    parser.last_error_span = field.span;
                    field.deinit(parser.allocator);
                    return error.UnionFieldDefaultNotAllowed;
                }
                fields.append(parser.allocator, field) catch |err| {
                    field.deinit(parser.allocator);
                    return err;
                };
            },
            .invalid_directive => return parser.rejectBareDirective(token),
            .label, .api_call, .meta_block_start => return error.InvalidStructField,
        }
    }

    return error.UnexpectedEndOfStruct;
}

fn appendMetaIfStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var parsed_if = try parseMetaIfStart(parser.allocator, start_token.text, start_token.span);
    errdefer parsed_if.deinit(parser.allocator);

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);
    var else_body: ast.StatementList = .{};
    errdefer else_body.deinit(parser.allocator);
    var active_body = &body;
    var saw_else = false;

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                parsed_if.body = try body.items.toOwnedSlice(parser.allocator);
                parsed_if.else_body = try else_body.items.toOwnedSlice(parser.allocator);
                try statements.append(parser.allocator, .{ .meta_if = parsed_if });
                return;
            },
            .isa_line => {
                if (try consumeSameLineElse(parser, &else_body, token)) {
                    if (saw_else) return error.InvalidMetaIf;
                    parsed_if.body = try body.items.toOwnedSlice(parser.allocator);
                    parsed_if.else_body = try else_body.items.toOwnedSlice(parser.allocator);
                    try statements.append(parser.allocator, .{ .meta_if = parsed_if });
                    return;
                } else {
                    try appendExecutableStatement(parser, active_body, token);
                }
            },
            .meta_line => {
                if (looksLikeMetaElseStart(token.text) or looksLikeMetaElseIfStart(token.text)) {
                    if (saw_else) return error.InvalidMetaIf;
                    saw_else = true;
                    active_body = &else_body;
                    try appendMetaElseBody(parser, &else_body, token);
                    parsed_if.body = try body.items.toOwnedSlice(parser.allocator);
                    parsed_if.else_body = try else_body.items.toOwnedSlice(parser.allocator);
                    try statements.append(parser.allocator, .{ .meta_if = parsed_if });
                    return;
                }
                try appendExecutableStatement(parser, active_body, token);
            },
            else => try appendExecutableStatement(parser, active_body, token),
        }
    }

    return error.UnexpectedEndOfMetaIf;
}

fn consumeSameLineElse(
    parser: *Parser,
    else_body: *ast.StatementList,
    token: lexer.Token,
) ParseError!bool {
    if (!looksLikeSameLineMetaElseStart(token.text) and !looksLikeSameLineMetaElseIfStart(token.text)) return false;
    try appendMetaElseBody(parser, else_body, token);
    return true;
}

fn appendMetaElseBody(
    parser: *Parser,
    else_body: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    if (looksLikeMetaElseIfStart(start_token.text) or looksLikeSameLineMetaElseIfStart(start_token.text)) {
        try appendMetaElseIf(parser, else_body, start_token);
        return;
    }
    if (!looksLikeMetaElseStart(start_token.text) and !looksLikeSameLineMetaElseStart(start_token.text)) return error.InvalidMetaIf;

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => return,
            else => try appendExecutableStatement(parser, else_body, token),
        }
    }

    return error.UnexpectedEndOfMetaIf;
}

fn appendMetaElseIf(
    parser: *Parser,
    else_body: *ast.StatementList,
    token: lexer.Token,
) ParseError!void {
    const trimmed = std.mem.trim(u8, token.text, " \t");
    const if_text = if (std.mem.startsWith(u8, trimmed, "} else if "))
        trimmed["} else ".len..]
    else
        trimmed["else ".len..];
    const nested_token: lexer.Token = .{
        .kind = .meta_line,
        .text = if_text,
        .span = token.span,
        .line = token.line,
        .column = token.column,
    };
    try appendMetaIfStatement(parser, else_body, nested_token);
}

fn appendMetaWhileStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var parsed_while = try parseMetaWhileStart(parser.allocator, start_token.text, start_token.span);
    errdefer parsed_while.deinit(parser.allocator);

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                parsed_while.body = try body.items.toOwnedSlice(parser.allocator);
                try statements.append(parser.allocator, .{ .meta_while = parsed_while });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfMetaWhile;
}

fn appendMetaForStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var parsed_for = try parseMetaForStart(parser.allocator, start_token.text, start_token.span);
    errdefer parsed_for.deinit(parser.allocator);

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                parsed_for.body = try body.items.toOwnedSlice(parser.allocator);
                try statements.append(parser.allocator, .{ .meta_for_range = parsed_for });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfMetaFor;
}

fn appendMetaFunctionStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var parsed_fn = try parseMetaFunctionStart(parser.allocator, start_token.text, start_token.span);
    errdefer parsed_fn.deinit(parser.allocator);

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                parsed_fn.body = try body.items.toOwnedSlice(parser.allocator);
                try statements.append(parser.allocator, .{ .meta_fn = parsed_fn });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfMetaFunction;
}

fn appendMetaBlockStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                const block_body = try body.items.toOwnedSlice(parser.allocator);
                errdefer deinitStatementSlice(parser.allocator, block_body);
                try statements.append(parser.allocator, .{
                    .meta_block = .{
                        .body = block_body,
                        .span = start_token.span,
                    },
                });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfMetaBlock;
}

fn appendMetaDeferStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    if (!looksLikeMetaDeferStart(start_token.text)) return error.InvalidMetaDefer;

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                const defer_body = try body.items.toOwnedSlice(parser.allocator);
                errdefer deinitStatementSlice(parser.allocator, defer_body);
                try statements.append(parser.allocator, .{
                    .meta_defer = .{
                        .body = defer_body,
                        .span = start_token.span,
                    },
                });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfMetaDefer;
}

fn appendLateLayoutStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    start_token: lexer.Token,
) ParseError!void {
    if (!looksLikeLateLayoutStart(start_token.text)) return error.InvalidLateLayout;

    var body: ast.StatementList = .{};
    errdefer body.deinit(parser.allocator);

    while (!parser.lexer.done()) {
        const token = try parser.lexer.next();
        switch (token.kind) {
            .blank, .comment => {},
            .meta_block_end => {
                const late_body = try body.items.toOwnedSlice(parser.allocator);
                errdefer deinitStatementSlice(parser.allocator, late_body);
                try statements.append(parser.allocator, .{
                    .late_layout = .{
                        .body = late_body,
                        .span = start_token.span,
                    },
                });
                return;
            },
            else => try appendExecutableStatement(parser, &body, token),
        }
    }

    return error.UnexpectedEndOfLateLayout;
}

fn appendExecutableStatement(
    parser: *Parser,
    statements: *ast.StatementList,
    token: lexer.Token,
) ParseError!void {
    var statement_token = token;
    var owned_token_text: ?[]u8 = null;
    defer if (owned_token_text) |text| parser.allocator.free(text);

    if (statementCanContinue(statement_token)) {
        if (try parser.collectContinuedStatement(statement_token)) |continued_text| {
            owned_token_text = continued_text;
            statement_token.text = continued_text;
        }
    }

    switch (statement_token.kind) {
        .blank, .comment => {},
        .label => try appendLabel(statements, parser.allocator, statement_token),
        .isa_line => try appendOwnedText(statements, parser.allocator, .isa_line, statement_token),
        .api_call => try appendApiCall(statements, parser.allocator, statement_token),
        .invalid_directive => return parser.rejectBareDirective(statement_token),
        .meta_line => {
            if (looksLikeStructStart(statement_token.text)) {
                try appendStructDeclaration(parser, statements, statement_token);
            } else if (looksLikeMetaFunctionStart(statement_token.text)) {
                try appendMetaFunctionStatement(parser, statements, statement_token);
            } else if (looksLikeMetaForStart(statement_token.text)) {
                try appendMetaForStatement(parser, statements, statement_token);
            } else if (looksLikeMetaWhileStart(statement_token.text)) {
                try appendMetaWhileStatement(parser, statements, statement_token);
            } else if (looksLikeLateLayoutStart(statement_token.text)) {
                try appendLateLayoutStatement(parser, statements, statement_token);
            } else if (looksLikeMetaDeferStart(statement_token.text)) {
                try appendMetaDeferStatement(parser, statements, statement_token);
            } else if (looksLikeMetaIfStart(statement_token.text)) {
                try appendMetaIfStatement(parser, statements, statement_token);
            } else if (looksLikeMetaBreak(statement_token.text)) {
                try statements.append(parser.allocator, .{ .meta_break = .{ .span = statement_token.span } });
            } else if (looksLikeMetaContinue(statement_token.text)) {
                try statements.append(parser.allocator, .{ .meta_continue = .{ .span = statement_token.span } });
            } else if (looksLikeValueDeclaration(statement_token.text)) {
                try appendValueDeclaration(statements, parser.allocator, statement_token);
            } else if (identifier.looksLikeAssignment(statement_token.text)) {
                try appendAssignment(statements, parser.allocator, statement_token);
            } else if (looksLikeMetaReturn(statement_token.text)) {
                try appendMetaReturn(statements, parser.allocator, statement_token);
            } else {
                try appendOwnedText(statements, parser.allocator, .meta_line, statement_token);
            }
        },
        .meta_block_start => try appendMetaBlockStatement(parser, statements, token),
        .meta_block_end => return error.InvalidMetaBlock,
    }
}

fn parseMetaIfStart(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaIfStatement {
    var rest = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, rest, "if ")) return error.InvalidMetaIf;
    rest = std.mem.trim(u8, rest["if".len..], " \t");
    if (rest.len == 0 or rest[rest.len - 1] != '{') return error.InvalidMetaIf;

    const condition = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    if (condition.len == 0) return error.InvalidMetaIf;

    return .{
        .condition = try allocator.dupe(u8, condition),
        .body = &.{},
        .span = span,
    };
}

fn parseMetaWhileStart(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaWhileStatement {
    var rest = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, rest, "while ")) return error.InvalidMetaWhile;
    rest = std.mem.trim(u8, rest["while".len..], " \t");
    if (rest.len == 0 or rest[rest.len - 1] != '{') return error.InvalidMetaWhile;

    const condition = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    if (condition.len == 0) return error.InvalidMetaWhile;

    return .{
        .condition = try allocator.dupe(u8, condition),
        .body = &.{},
        .span = span,
    };
}

fn parseMetaForStart(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaForRangeStatement {
    var rest = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, rest, "for ")) return error.InvalidMetaFor;
    rest = std.mem.trim(u8, rest["for".len..], " \t");
    if (rest.len == 0 or rest[rest.len - 1] != '{') return error.InvalidMetaFor;

    const header = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    const in_index = std.mem.indexOf(u8, header, " in ") orelse return error.InvalidMetaFor;
    const name = std.mem.trim(u8, header[0..in_index], " \t");
    if (!identifier.isName(name)) return error.InvalidMetaFor;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    const iterable_text = std.mem.trim(u8, header[in_index + " in ".len ..], " \t");
    if (iterable_text.len == 0) return error.InvalidMetaFor;

    var source_node = try parseMetaForSource(allocator, iterable_text);
    errdefer source_node.deinit(allocator);

    return .{
        .name = owned_name,
        .source = source_node,
        .body = &.{},
        .span = span,
    };
}

fn parseMetaForSource(allocator: Allocator, text: []const u8) ParseError!ast.MetaForSource {
    if (std.mem.startsWith(u8, text, "range")) {
        const args_text = std.mem.trim(u8, text["range".len..], " \t");
        if (args_text.len >= 2 and args_text[0] == '(' and args_text[args_text.len - 1] == ')') {
            const range_args = args_text[1 .. args_text.len - 1];
            const comma_index = std.mem.indexOfScalar(u8, range_args, ',') orelse return error.InvalidMetaFor;
            const start_text = std.mem.trim(u8, range_args[0..comma_index], " \t");
            const end_text = std.mem.trim(u8, range_args[comma_index + 1 ..], " \t");
            if (start_text.len == 0 or end_text.len == 0) return error.InvalidMetaFor;

            var start = expr.parseOwned(allocator, start_text) catch |err| return mapMetaForExpressionError(err);
            errdefer start.deinit(allocator);
            var end = expr.parseOwned(allocator, end_text) catch |err| return mapMetaForExpressionError(err);
            errdefer end.deinit(allocator);

            return .{ .range = .{
                .start = start,
                .end = end,
            } };
        }
    }

    return .{ .list = expr.parseOwned(allocator, text) catch |err| return mapMetaForExpressionError(err) };
}

fn mapMetaForExpressionError(err: expr.ExpressionError) ParseError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidMetaFor,
    };
}

fn parseMetaFunctionStart(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaFunctionStatement {
    var rest = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, rest, "fn ")) return error.InvalidMetaFunction;
    rest = std.mem.trim(u8, rest["fn".len..], " \t");
    if (rest.len == 0 or rest[rest.len - 1] != '{') return error.InvalidMetaFunction;

    const signature = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    const open_index = std.mem.indexOfScalar(u8, signature, '(') orelse return error.InvalidMetaFunction;
    const close_index = std.mem.lastIndexOfScalar(u8, signature, ')') orelse return error.InvalidMetaFunction;
    if (close_index < open_index) return error.InvalidMetaFunction;

    const trailing = std.mem.trim(u8, signature[close_index + 1 ..], " \t");
    const return_type_name = if (trailing.len == 0)
        null
    else return_type: {
        if (!std.mem.startsWith(u8, trailing, "->")) return error.InvalidMetaFunction;
        const parsed_type = std.mem.trim(u8, trailing["->".len..], " \t");
        if (!identifier.isName(parsed_type)) return error.InvalidMetaFunction;
        break :return_type parsed_type;
    };

    const name = std.mem.trim(u8, signature[0..open_index], " \t");
    if (!identifier.isName(name)) return error.InvalidMetaFunction;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    const owned_return_type_name = if (return_type_name) |parsed_type|
        try allocator.dupe(u8, parsed_type)
    else
        null;
    errdefer if (owned_return_type_name) |owned| allocator.free(owned);

    const params = try parseMetaFunctionParams(allocator, signature[open_index + 1 .. close_index], span);
    errdefer deinitMetaFunctionParams(allocator, params);

    return .{
        .name = owned_name,
        .params = params,
        .return_type_name = owned_return_type_name,
        .body = &.{},
        .span = span,
    };
}

fn parseMetaReturn(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaReturnStatement {
    var rest = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, rest, "return")) return error.InvalidExpression;
    rest = std.mem.trim(u8, rest["return".len..], " \t;");
    if (rest.len == 0) return error.InvalidExpression;

    var parsed = expr.parseOwned(allocator, rest) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidExpression,
    };
    errdefer parsed.deinit(allocator);

    return .{
        .value = parsed,
        .span = span,
    };
}

fn parseMetaFunctionParams(
    allocator: Allocator,
    params_text: []const u8,
    span: source.SourceSpan,
) ParseError![]ast.MetaFunctionParam {
    const trimmed = std.mem.trim(u8, params_text, " \t");
    if (trimmed.len == 0) return allocator.alloc(ast.MetaFunctionParam, 0);

    var params: std.ArrayList(ast.MetaFunctionParam) = .empty;
    errdefer {
        for (params.items) |*param| {
            param.deinit(allocator);
        }
        params.deinit(allocator);
    }

    var start: usize = 0;
    var index: usize = 0;
    while (index <= params_text.len) : (index += 1) {
        if (index == params_text.len or params_text[index] == ',') {
            const raw_param = std.mem.trim(u8, params_text[start..index], " \t");
            if (raw_param.len == 0) return error.InvalidMetaFunction;
            var param = try parseMetaFunctionParam(allocator, raw_param, span);
            if (metaParamNameExists(params.items, param.name)) {
                param.deinit(allocator);
                return error.InvalidMetaFunction;
            }
            params.append(allocator, param) catch |err| {
                param.deinit(allocator);
                return err;
            };
            start = index + 1;
        }
    }

    return params.toOwnedSlice(allocator);
}

fn metaParamNameExists(params: []const ast.MetaFunctionParam, name: []const u8) bool {
    for (params) |param| {
        if (std.mem.eql(u8, param.name, name)) return true;
    }
    return false;
}

fn parseMetaFunctionParam(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.MetaFunctionParam {
    const colon_index = std.mem.indexOfScalar(u8, text, ':');
    const name = if (colon_index) |index|
        std.mem.trim(u8, text[0..index], " \t")
    else
        text;
    if (!identifier.isName(name)) return error.InvalidMetaFunction;

    const type_name = if (colon_index) |index| type_name: {
        const parsed_type = std.mem.trim(u8, text[index + 1 ..], " \t");
        if (!identifier.isName(parsed_type)) return error.InvalidMetaFunction;
        break :type_name parsed_type;
    } else null;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    const owned_type_name = if (type_name) |parsed_type|
        try allocator.dupe(u8, parsed_type)
    else
        null;
    errdefer if (owned_type_name) |owned| allocator.free(owned);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .span = span,
    };
}

fn parseStructStart(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.StructDeclarationStatement {
    var kind: ast.AggregateSyntaxKind = .@"struct";
    var policy: ast.StructSyntaxPolicy = .natural;
    var rest = std.mem.trim(u8, text, " \t");

    if (std.mem.startsWith(u8, rest, "packed struct")) {
        kind = .@"struct";
        policy = .@"packed";
        rest = std.mem.trim(u8, rest["packed struct".len..], " \t");
    } else if (std.mem.startsWith(u8, rest, "packed union")) {
        kind = .@"union";
        policy = .@"packed";
        rest = std.mem.trim(u8, rest["packed union".len..], " \t");
    } else if (std.mem.startsWith(u8, rest, "struct")) {
        kind = .@"struct";
        rest = std.mem.trim(u8, rest["struct".len..], " \t");
    } else if (std.mem.startsWith(u8, rest, "union")) {
        kind = .@"union";
        rest = std.mem.trim(u8, rest["union".len..], " \t");
    } else {
        return error.InvalidStructDeclaration;
    }

    if (rest.len == 0 or rest[rest.len - 1] != '{') return error.InvalidStructDeclaration;
    const name = std.mem.trim(u8, rest[0 .. rest.len - 1], " \t");
    if (!identifier.isName(name)) return error.InvalidStructDeclaration;

    return .{
        .name = try allocator.dupe(u8, name),
        .kind = kind,
        .policy = policy,
        .fields = &.{},
        .span = span,
    };
}

fn parseStructField(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.StructFieldSyntax {
    var field_text = std.mem.trim(u8, text, " \t");
    if (field_text.len == 0) return error.InvalidStructField;
    if (field_text[field_text.len - 1] == ',') {
        field_text = std.mem.trim(u8, field_text[0 .. field_text.len - 1], " \t");
    }

    const colon_index = std.mem.indexOfScalar(u8, field_text, ':') orelse return error.InvalidStructField;
    const name = std.mem.trim(u8, field_text[0..colon_index], " \t");
    if (!identifier.isName(name)) return error.InvalidStructField;

    const type_and_default = std.mem.trim(u8, field_text[colon_index + 1 ..], " \t");
    if (type_and_default.len == 0) return error.InvalidStructField;

    const default_index = std.mem.indexOfScalar(u8, type_and_default, '=');
    const type_name = if (default_index) |index|
        std.mem.trim(u8, type_and_default[0..index], " \t")
    else
        type_and_default;
    if (!identifier.isName(type_name)) return error.InvalidStructField;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    const owned_type_name = try allocator.dupe(u8, type_name);
    errdefer allocator.free(owned_type_name);

    const owned_default = if (default_index) |index| default: {
        const default_text = std.mem.trim(u8, type_and_default[index + 1 ..], " \t");
        if (default_text.len == 0) return error.InvalidStructField;
        break :default try allocator.dupe(u8, default_text);
    } else null;
    errdefer if (owned_default) |value| allocator.free(value);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .default_value = owned_default,
        .span = span,
    };
}

fn looksLikeStructStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "struct ") or
        std.mem.startsWith(u8, trimmed, "packed struct ") or
        std.mem.startsWith(u8, trimmed, "union ") or
        std.mem.startsWith(u8, trimmed, "packed union ");
}

fn looksLikeMetaIfStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "if ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeMetaElseStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.eql(u8, trimmed, "else {");
}

fn looksLikeMetaElseIfStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "else if ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeSameLineMetaElseStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.eql(u8, trimmed, "} else {");
}

fn looksLikeSameLineMetaElseIfStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "} else if ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeMetaWhileStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "while ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeMetaDeferStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.eql(u8, trimmed, "defer {");
}

fn looksLikeLateLayoutStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.eql(u8, trimmed, "late_layout {");
}

fn looksLikeMetaForStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "for ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeMetaFunctionStart(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "fn ") and std.mem.endsWith(u8, trimmed, "{");
}

fn looksLikeMetaReturn(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    if (!std.mem.startsWith(u8, trimmed, "return")) return false;
    if (trimmed.len == "return".len) return true;
    return trimmed["return".len] == ' ' or trimmed["return".len] == '\t';
}

fn looksLikeMetaBreak(text: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, text, " \t;"), "break");
}

fn looksLikeMetaContinue(text: []const u8) bool {
    return std.mem.eql(u8, std.mem.trim(u8, text, " \t;"), "continue");
}

fn looksLikeValueDeclaration(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t");
    return std.mem.startsWith(u8, trimmed, "const ") or
        std.mem.startsWith(u8, trimmed, "let ");
}

fn parseValueDeclaration(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.ValueDeclarationStatement {
    var rest = std.mem.trim(u8, text, " \t;");
    const mutability: value_mod.Mutability = if (std.mem.startsWith(u8, rest, "const ")) blk: {
        rest = std.mem.trim(u8, rest["const".len..], " \t");
        break :blk .@"const";
    } else if (std.mem.startsWith(u8, rest, "let ")) blk: {
        rest = std.mem.trim(u8, rest["let".len..], " \t");
        break :blk .let;
    } else {
        return error.InvalidValueDeclaration;
    };

    const equals_index = std.mem.indexOfScalar(u8, rest, '=') orelse return error.InvalidValueDeclaration;
    const name_and_type = std.mem.trim(u8, rest[0..equals_index], " \t");
    const value_text = std.mem.trim(u8, rest[equals_index + 1 ..], " \t");
    if (name_and_type.len == 0 or value_text.len == 0) return error.InvalidValueDeclaration;

    const colon_index = std.mem.indexOfScalar(u8, name_and_type, ':');
    const name = if (colon_index) |index|
        std.mem.trim(u8, name_and_type[0..index], " \t")
    else
        name_and_type;
    if (!identifier.isName(name)) return error.InvalidValueDeclaration;

    const type_name = if (colon_index) |index| type_name: {
        const parsed_type = std.mem.trim(u8, name_and_type[index + 1 ..], " \t");
        if (!identifier.isName(parsed_type)) return error.InvalidValueDeclaration;
        break :type_name parsed_type;
    } else null;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    const owned_type_name = if (type_name) |parsed_type|
        try allocator.dupe(u8, parsed_type)
    else
        null;
    errdefer if (owned_type_name) |owned| allocator.free(owned);

    var parsed_value = try parseValueInitializer(allocator, value_text);
    errdefer parsed_value.deinit(allocator);

    return .{
        .name = owned_name,
        .type_name = owned_type_name,
        .mutability = mutability,
        .value = parsed_value,
        .span = span,
    };
}

fn parseAssignment(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.AssignmentStatement {
    const trimmed = std.mem.trim(u8, text, " \t;");
    const equals_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse return error.InvalidValueDeclaration;
    const name = std.mem.trim(u8, trimmed[0..equals_index], " \t");
    const value_text = std.mem.trim(u8, trimmed[equals_index + 1 ..], " \t");
    if (!identifier.isName(name) or value_text.len == 0) return error.InvalidValueDeclaration;

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    var parsed_value = try parseValueInitializer(allocator, value_text);
    errdefer parsed_value.deinit(allocator);

    return .{
        .name = owned_name,
        .value = parsed_value,
        .span = span,
    };
}

fn parseValueInitializer(allocator: Allocator, value_text: []const u8) ParseError!ast.ValueInitializer {
    if (parseStructLiteralArgument(allocator, value_text)) |arg| {
        return switch (arg) {
            .struct_literal => |literal| .{ .struct_literal = literal },
            .expression, .string => error.InvalidValueDeclaration,
        };
    } else |err| switch (err) {
        error.InvalidApiArgument => {},
        error.OutOfMemory => return error.OutOfMemory,
    }

    return .{ .expression = expr.parseOwned(allocator, value_text) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidExpression,
    } };
}

fn deinitStructFields(allocator: Allocator, fields: *std.ArrayList(ast.StructFieldSyntax)) void {
    for (fields.items) |*field| {
        field.deinit(allocator);
    }
    fields.deinit(allocator);
}

fn deinitMetaFunctionParams(allocator: Allocator, params: []ast.MetaFunctionParam) void {
    for (params) |*param| {
        param.deinit(allocator);
    }
    allocator.free(params);
}

fn deinitStatementSlice(allocator: Allocator, statements: []ast.Statement) void {
    for (statements) |*statement| {
        statement.deinit(allocator);
    }
    allocator.free(statements);
}

fn parseApiCall(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.ApiCallStatement {
    const open_index = std.mem.indexOfScalar(u8, text, '(') orelse return error.InvalidApiCall;
    const close_index = std.mem.lastIndexOfScalar(u8, text, ')') orelse return error.InvalidApiCall;
    if (close_index < open_index) return error.InvalidApiCall;

    const trailing = std.mem.trim(u8, text[close_index + 1 ..], " \t;");
    if (trailing.len != 0) return error.InvalidApiCall;

    const callee_text = std.mem.trim(u8, text[0..open_index], " \t");
    if (callee_text.len == 0) return error.InvalidApiCall;

    const owned_text = try allocator.dupe(u8, text);
    errdefer allocator.free(owned_text);

    const owned_callee = try allocator.dupe(u8, callee_text);
    errdefer allocator.free(owned_callee);

    const args_text = text[open_index + 1 .. close_index];
    const args = try parseApiArguments(allocator, args_text);
    errdefer deinitApiArguments(allocator, args);

    return .{
        .text = owned_text,
        .callee = owned_callee,
        .args = args,
        .span = span,
    };
}

pub fn parseApiCallText(
    allocator: Allocator,
    text: []const u8,
    span: source.SourceSpan,
) ParseError!ast.ApiCallStatement {
    return parseApiCall(allocator, text, span);
}

fn parseApiArguments(allocator: Allocator, args_text: []const u8) ParseError![]ast.ApiArgument {
    const trimmed = std.mem.trim(u8, args_text, statement_ws);
    if (trimmed.len == 0) return allocator.alloc(ast.ApiArgument, 0);

    var args: std.ArrayList(ast.ApiArgument) = .empty;
    errdefer {
        for (args.items) |*arg| {
            arg.deinit(allocator);
        }
        args.deinit(allocator);
    }

    var start: usize = 0;
    var index: usize = 0;
    var paren_depth: u32 = 0;
    var brace_depth: u32 = 0;
    var in_string = false;
    while (index <= args_text.len) : (index += 1) {
        if (index < args_text.len) {
            const byte = args_text[index];
            if (byte == '"') {
                if (in_string and index + 1 < args_text.len and args_text[index + 1] == '"') {
                    index += 1;
                    continue;
                }
                in_string = !in_string;
            } else if (!in_string) {
                if (byte == '(') paren_depth += 1;
                if (byte == ')') {
                    if (paren_depth == 0) return error.InvalidApiArgument;
                    paren_depth -= 1;
                }
                if (byte == '{') brace_depth += 1;
                if (byte == '}') {
                    if (brace_depth == 0) return error.InvalidApiArgument;
                    brace_depth -= 1;
                }
            }
        }

        if (index == args_text.len or (!in_string and paren_depth == 0 and brace_depth == 0 and args_text[index] == ',')) {
            const raw_arg = std.mem.trim(u8, args_text[start..index], statement_ws);
            if (raw_arg.len == 0) return error.InvalidApiArgument;
            var arg = try parseApiArgument(allocator, raw_arg);
            args.append(allocator, arg) catch |err| {
                arg.deinit(allocator);
                return err;
            };
            start = index + 1;
        }
    }

    return args.toOwnedSlice(allocator);
}

fn parseApiArgument(allocator: Allocator, text: []const u8) ParseError!ast.ApiArgument {
    if (text.len >= 2 and text[0] == '"' and text[text.len - 1] == '"') {
        return .{ .string = try parseQuotedText(allocator, text) };
    }

    if (parseStructLiteralArgument(allocator, text)) |arg| {
        return arg;
    } else |err| switch (err) {
        error.InvalidApiArgument => {},
        error.OutOfMemory => return error.OutOfMemory,
    }

    return .{ .expression = expr.parseOwned(allocator, text) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.InvalidExpression,
    } };
}

fn parseQuotedText(allocator: Allocator, text: []const u8) ParseError![]u8 {
    if (text.len < 2 or text[0] != '"' or text[text.len - 1] != '"') return error.InvalidApiArgument;

    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var index: usize = 1;
    while (index < text.len - 1) : (index += 1) {
        const byte = text[index];
        if (byte == '"') {
            if (index + 1 < text.len - 1 and text[index + 1] == '"') {
                try result.append(allocator, '"');
                index += 1;
                continue;
            }
            return error.InvalidApiArgument;
        }
        try result.append(allocator, byte);
    }

    return result.toOwnedSlice(allocator);
}

fn parseStructLiteralArgument(allocator: Allocator, text: []const u8) error{ InvalidApiArgument, OutOfMemory }!ast.ApiArgument {
    const open_index = std.mem.indexOfScalar(u8, text, '{') orelse return error.InvalidApiArgument;
    if (text[text.len - 1] != '}') return error.InvalidApiArgument;

    const type_name = std.mem.trim(u8, text[0..open_index], statement_ws);
    if (!identifier.isName(type_name)) return error.InvalidApiArgument;

    const owned_type_name = try allocator.dupe(u8, type_name);
    errdefer allocator.free(owned_type_name);

    var fields: std.ArrayList(ast.StructLiteralField) = .empty;
    errdefer deinitStructLiteralFields(allocator, &fields);

    const fields_text = text[open_index + 1 .. text.len - 1];
    var start: usize = 0;
    var index: usize = 0;
    var paren_depth: u32 = 0;
    var brace_depth: u32 = 0;
    var in_string = false;
    while (index <= fields_text.len) : (index += 1) {
        if (index < fields_text.len) {
            const byte = fields_text[index];
            if (byte == '"') {
                if (in_string and index + 1 < fields_text.len and fields_text[index + 1] == '"') {
                    index += 1;
                    continue;
                }
                in_string = !in_string;
            } else if (!in_string) {
                if (byte == '(') paren_depth += 1;
                if (byte == ')') {
                    if (paren_depth == 0) return error.InvalidApiArgument;
                    paren_depth -= 1;
                }
                if (byte == '{') brace_depth += 1;
                if (byte == '}') {
                    if (brace_depth == 0) return error.InvalidApiArgument;
                    brace_depth -= 1;
                }
            }
        }

        if (index == fields_text.len or (!in_string and paren_depth == 0 and brace_depth == 0 and fields_text[index] == ',')) {
            const raw_field = std.mem.trim(u8, fields_text[start..index], statement_ws);
            if (raw_field.len != 0) {
                var field = try parseStructLiteralField(allocator, raw_field);
                fields.append(allocator, field) catch |err| {
                    field.deinit(allocator);
                    return err;
                };
            }
            start = index + 1;
        }
    }
    if (in_string or paren_depth != 0 or brace_depth != 0) return error.InvalidApiArgument;

    const owned_fields = try fields.toOwnedSlice(allocator);
    errdefer deinitStructLiteralFieldSlice(allocator, owned_fields);

    return .{
        .struct_literal = .{
            .type_name = owned_type_name,
            .fields = owned_fields,
        },
    };
}

fn parseStructLiteralField(
    allocator: Allocator,
    text: []const u8,
) error{ InvalidApiArgument, OutOfMemory }!ast.StructLiteralField {
    const colon_index = std.mem.indexOfScalar(u8, text, ':') orelse return error.InvalidApiArgument;
    const name = std.mem.trim(u8, text[0..colon_index], statement_ws);
    if (!identifier.isName(name)) return error.InvalidApiArgument;

    const value_text = std.mem.trim(u8, text[colon_index + 1 ..], statement_ws);
    if (value_text.len == 0) return error.InvalidApiArgument;

    var value: ast.StructLiteralValue = if (parseStructLiteralArgument(allocator, value_text)) |arg| switch (arg) {
        .struct_literal => |literal| .{ .struct_literal = literal },
        .expression, .string => return error.InvalidApiArgument,
    } else |err| switch (err) {
        error.InvalidApiArgument => .{ .expression = expr.parseOwned(allocator, value_text) catch |parse_err| switch (parse_err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => return error.InvalidApiArgument,
        } },
        error.OutOfMemory => return error.OutOfMemory,
    };
    errdefer value.deinit(allocator);

    const owned_name = try allocator.dupe(u8, name);
    errdefer allocator.free(owned_name);

    return .{
        .name = owned_name,
        .value = value,
    };
}

fn deinitStructLiteralFields(allocator: Allocator, fields: *std.ArrayList(ast.StructLiteralField)) void {
    for (fields.items) |*field| {
        field.deinit(allocator);
    }
    fields.deinit(allocator);
}

fn deinitStructLiteralFieldSlice(allocator: Allocator, fields: []ast.StructLiteralField) void {
    for (fields) |*field| {
        field.deinit(allocator);
    }
    allocator.free(fields);
}

fn deinitApiArguments(allocator: Allocator, args: []ast.ApiArgument) void {
    for (args) |*arg| {
        arg.deinit(allocator);
    }
    allocator.free(args);
}

pub fn parseSource(allocator: Allocator, input: []const u8) ParseError!ast.StatementList {
    var parser = Parser.init(allocator, input);
    return parser.parse();
}

pub fn parseSourceWithId(
    allocator: Allocator,
    source_id: source.SourceId,
    input: []const u8,
) ParseError!ast.StatementList {
    var parser = Parser.initWithSource(allocator, source_id, input);
    return parser.parse();
}

pub fn parseStructLiteralText(allocator: Allocator, text: []const u8) ParseError!ast.StructLiteralArgument {
    var arg = parseStructLiteralArgument(allocator, std.mem.trim(u8, text, " \t\r\n")) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidApiArgument => return error.InvalidApiArgument,
    };
    errdefer arg.deinit(allocator);
    return switch (arg) {
        .struct_literal => |literal| literal,
        .expression, .string => error.InvalidApiArgument,
    };
}

test "parser keeps labels ISA statements and Meta statements separate" {
    var statements = try parseSource(std.testing.allocator,
        \\loop:
        \\    mov rax, 0
        \\origin(0x7c00);
        \\emit.u16(0xaa55);
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32,
        \\}
        \\let count = 4
        \\count = count + 1
        \\for i in range(0, count) {
        \\    add rax, i
        \\}
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 8), statements.items.items.len);

    switch (statements.items.items[0]) {
        .label => |statement| try std.testing.expectEqualStrings("loop", statement.name),
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[1]) {
        .isa_instruction => |statement| try std.testing.expectEqualStrings("mov rax, 0", statement.text),
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[2]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("origin(0x7c00);", statement.text);
            try std.testing.expectEqualStrings("origin", statement.callee);
            try std.testing.expectEqual(@as(usize, 1), statement.args.len);
            switch (statement.args[0]) {
                .expression => |node| switch (node) {
                    .integer => |value| try std.testing.expectEqual(@as(u64, 0x7c00), value),
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[3]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("emit.u16(0xaa55);", statement.text);
            try std.testing.expectEqualStrings("emit.u16", statement.callee);
            try std.testing.expectEqual(@as(usize, 1), statement.args.len);
            switch (statement.args[0]) {
                .expression => |node| switch (node) {
                    .integer => |value| try std.testing.expectEqual(@as(u64, 0xaa55), value),
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[4]) {
        .struct_decl => |statement| {
            try std.testing.expectEqualStrings("DosHeader", statement.name);
            try std.testing.expectEqual(ast.StructSyntaxPolicy.@"packed", statement.policy);
            try std.testing.expectEqual(@as(usize, 2), statement.fields.len);
            try std.testing.expectEqualStrings("magic", statement.fields[0].name);
            try std.testing.expectEqualStrings("u16", statement.fields[0].type_name);
            try std.testing.expectEqualStrings("0x5a4d", statement.fields[0].default_value.?);
            try std.testing.expectEqualStrings("lfanew", statement.fields[1].name);
            try std.testing.expectEqualStrings("u32", statement.fields[1].type_name);
            try std.testing.expect(statement.fields[1].default_value == null);
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[5]) {
        .value_decl => |statement| {
            try std.testing.expectEqualStrings("count", statement.name);
            try std.testing.expectEqual(value_mod.Mutability.let, statement.mutability);
            switch (statement.value) {
                .expression => |node| switch (node) {
                    .integer => |stored_value| try std.testing.expectEqual(@as(u64, 4), stored_value),
                    else => return error.UnexpectedValueExpression,
                },
                .struct_literal => return error.UnexpectedValueExpression,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[6]) {
        .assignment => |statement| {
            try std.testing.expectEqualStrings("count", statement.name);
            switch (statement.value) {
                .expression => |node| switch (node) {
                    .binary => {},
                    else => return error.UnexpectedValueExpression,
                },
                .struct_literal => return error.UnexpectedValueExpression,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[7]) {
        .meta_for_range => |statement| {
            try std.testing.expectEqualStrings("i", statement.name);
            try std.testing.expectEqual(@as(usize, 1), statement.body.len);
            switch (statement.body[0]) {
                .isa_instruction => |body_statement| try std.testing.expectEqualStrings("add rax, i", body_statement.text),
                else => return error.UnexpectedStatement,
            }
        },
        else => return error.UnexpectedStatement,
    }
}

test "parser rejects bare directives with their source span" {
    const input =
        \\emit.u8(1);
        \\  db 0xff
        \\
    ;
    const source_id: source.SourceId = .{ .index = 7 };
    var parser = Parser.initWithSource(std.testing.allocator, source_id, input);

    try std.testing.expectError(error.LegacyDirectiveSyntax, parser.parse());
    const error_span = parser.errorSpan() orelse return error.MissingErrorSpan;
    const start = std.mem.indexOf(u8, input, "db 0xff") orelse return error.MissingDirective;
    const span_source = error_span.source orelse return error.MissingSource;
    try std.testing.expectEqual(source_id.index, span_source.index);
    try std.testing.expectEqual(@as(u32, @intCast(start)), error_span.start);
    try std.testing.expectEqual(@as(u32, @intCast(start + "db 0xff".len)), error_span.end);
}

test "parser accepts struct literals as value initializers" {
    var statements = try parseSource(std.testing.allocator,
        \\const hdr: DosHeader = DosHeader { magic: 0x5a4d, lfanew: 0x80 }
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), statements.items.items.len);
    switch (statements.items.items[0]) {
        .value_decl => |statement| {
            try std.testing.expectEqualStrings("hdr", statement.name);
            try std.testing.expectEqualStrings("DosHeader", statement.type_name.?);
            switch (statement.value) {
                .struct_literal => |literal| {
                    try std.testing.expectEqualStrings("DosHeader", literal.type_name);
                    try std.testing.expectEqual(@as(usize, 2), literal.fields.len);
                },
                else => return error.UnexpectedValueExpression,
            }
        },
        else => return error.UnexpectedStatement,
    }
}

test "parser rejects union field defaults" {
    var parser = Parser.init(std.testing.allocator,
        \\union Value {
        \\    raw: u32 = 1
        \\}
        \\const value: Value = Value { raw: 2 }
        \\
    );

    try std.testing.expectError(error.UnionFieldDefaultNotAllowed, parser.parse());
    try std.testing.expect(parser.errorSpan() != null);
}

test "parser accepts sizeof type query as API argument" {
    var statements = try parseSource(std.testing.allocator,
        \\pad(sizeof(SaveArea), 0);
        \\emit.u8(lengthof("AB"));
        \\emit.struct(DosHeader { magic: 0x5a4d, lfanew: 0x80 });
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), statements.items.items.len);
    switch (statements.items.items[0]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("pad", statement.callee);
            try std.testing.expectEqual(@as(usize, 2), statement.args.len);
            switch (statement.args[0]) {
                .expression => |node| switch (node) {
                    .builtin_call => |call| {
                        try std.testing.expectEqualStrings("sizeof", call.name);
                        try std.testing.expectEqual(@as(usize, 1), call.args.len);
                        switch (call.args[0]) {
                            .identifier => |name| try std.testing.expectEqualStrings("SaveArea", name),
                            else => return error.UnexpectedApiArgument,
                        }
                    },
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
            switch (statement.args[1]) {
                .expression => |node| switch (node) {
                    .integer => |value| try std.testing.expectEqual(@as(u64, 0), value),
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[1]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("emit.u8", statement.callee);
            switch (statement.args[0]) {
                .expression => |node| switch (node) {
                    .builtin_call => |call| {
                        try std.testing.expectEqualStrings("lengthof", call.name);
                        try std.testing.expectEqual(@as(usize, 1), call.args.len);
                    },
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }

    switch (statements.items.items[2]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("emit.struct", statement.callee);
            try std.testing.expectEqualStrings("DosHeader", statement.args[0].struct_literal.type_name);
            try std.testing.expectEqual(@as(usize, 2), statement.args[0].struct_literal.fields.len);
            try std.testing.expectEqualStrings("magic", statement.args[0].struct_literal.fields[0].name);
            switch (statement.args[0].struct_literal.fields[0].value) {
                .expression => |node| switch (node) {
                    .integer => |value| try std.testing.expectEqual(@as(u64, 0x5a4d), value),
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }
}

test "parser accepts multiline value return and API expression arguments" {
    var statements = try parseSource(std.testing.allocator,
        \\const cfg: map = map.set(
        \\    map.new(),
        \\    "name",
        \\    replace(
        \\        lower("KERNEL32.DLL"),
        \\        ".",
        \\        "_"
        \\    )
        \\)
        \\fn make_name(value: string) -> string {
        \\    return sym.join(
        \\        "prefix_",
        \\        replace(value, ".", "_")
        \\    )
        \\}
        \\emit.bytes(pack(
        \\    Pair {
        \\        lo: 3,
        \\        hi: 4,
        \\    }
        \\));
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), statements.items.items.len);
    switch (statements.items.items[0]) {
        .value_decl => |statement| {
            try std.testing.expectEqualStrings("cfg", statement.name);
            switch (statement.value) {
                .expression => |node| switch (node) {
                    .builtin_call => |call| {
                        try std.testing.expectEqualStrings("map.set", call.name);
                        try std.testing.expectEqual(@as(usize, 3), call.args.len);
                    },
                    else => return error.UnexpectedValueExpression,
                },
                .struct_literal => return error.UnexpectedValueExpression,
            }
        },
        else => return error.UnexpectedStatement,
    }
    switch (statements.items.items[1]) {
        .meta_fn => |function| {
            try std.testing.expectEqualStrings("make_name", function.name);
            try std.testing.expectEqual(@as(usize, 1), function.body.len);
            switch (function.body[0]) {
                .meta_return => |statement| switch (statement.value) {
                    .builtin_call => |call| {
                        try std.testing.expectEqualStrings("sym.join", call.name);
                        try std.testing.expectEqual(@as(usize, 2), call.args.len);
                    },
                    else => return error.UnexpectedValueExpression,
                },
                else => return error.UnexpectedStatement,
            }
        },
        else => return error.UnexpectedStatement,
    }
    switch (statements.items.items[2]) {
        .api_call => |statement| {
            try std.testing.expectEqualStrings("emit.bytes", statement.callee);
            switch (statement.args[0]) {
                .expression => |node| switch (node) {
                    .builtin_call => |call| try std.testing.expectEqualStrings("pack", call.name),
                    else => return error.UnexpectedApiArgument,
                },
                else => return error.UnexpectedApiArgument,
            }
        },
        else => return error.UnexpectedStatement,
    }
}

test "parser builds structured Meta functions and scoped blocks" {
    var statements = try parseSource(std.testing.allocator,
        \\fn emit_pair(value: u64) {
        \\    emit.u8(value);
        \\    {
        \\        let inner = value + 1
        \\        emit.u8(inner);
        \\    }
        \\}
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), statements.items.items.len);

    switch (statements.items.items[0]) {
        .meta_fn => |function| {
            try std.testing.expectEqualStrings("emit_pair", function.name);
            try std.testing.expectEqual(@as(usize, 1), function.params.len);
            try std.testing.expectEqualStrings("value", function.params[0].name);
            const type_name = function.params[0].type_name orelse return error.MissingMetaParameterType;
            try std.testing.expectEqualStrings("u64", type_name);
            try std.testing.expectEqual(@as(usize, 2), function.body.len);

            switch (function.body[0]) {
                .api_call => |call| try std.testing.expectEqualStrings("emit.u8", call.callee),
                else => return error.UnexpectedStatement,
            }

            switch (function.body[1]) {
                .meta_block => |block| {
                    try std.testing.expectEqual(@as(usize, 2), block.body.len);
                    switch (block.body[0]) {
                        .value_decl => |declaration| {
                            try std.testing.expectEqualStrings("inner", declaration.name);
                            switch (declaration.value) {
                                .expression => |node| switch (node) {
                                    .binary => {},
                                    else => return error.UnexpectedValueExpression,
                                },
                                .struct_literal => return error.UnexpectedValueExpression,
                            }
                        },
                        else => return error.UnexpectedStatement,
                    }
                    switch (block.body[1]) {
                        .api_call => |call| try std.testing.expectEqualStrings("emit.u8", call.callee),
                        else => return error.UnexpectedStatement,
                    }
                },
                else => return error.UnexpectedStatement,
            }
        },
        else => return error.UnexpectedStatement,
    }
}

test "parser preserves nested Meta if inside else body" {
    var statements = try parseSource(std.testing.allocator,
        \\fn dispatch(kind: string) {
        \\    if kind == "read" {
        \\        emit_read();
        \\    } else {
        \\        if kind == "write" {
        \\            emit_write();
        \\        } else {
        \\            emit_poison();
        \\        }
        \\    }
        \\}
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), statements.items.items.len);
    const function = switch (statements.items.items[0]) {
        .meta_fn => |function| function,
        else => return error.UnexpectedStatement,
    };
    try std.testing.expectEqual(@as(usize, 1), function.body.len);
    const outer_if = switch (function.body[0]) {
        .meta_if => |meta_if| meta_if,
        else => return error.UnexpectedStatement,
    };
    try std.testing.expectEqual(@as(usize, 1), outer_if.body.len);
    try std.testing.expectEqual(@as(usize, 1), outer_if.else_body.len);
    const nested_if = switch (outer_if.else_body[0]) {
        .meta_if => |meta_if| meta_if,
        else => return error.UnexpectedStatement,
    };
    try std.testing.expectEqual(@as(usize, 1), nested_if.body.len);
    try std.testing.expectEqual(@as(usize, 1), nested_if.else_body.len);
}

test "parser expands else if and recognizes loop control statements" {
    var statements = try parseSource(std.testing.allocator,
        \\if false {
        \\    emit.u8(0);
        \\} else if true {
        \\    continue;
        \\} else {
        \\    break;
        \\}
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), statements.items.items.len);
    const outer_if = switch (statements.items.items[0]) {
        .meta_if => |meta_if| meta_if,
        else => return error.UnexpectedStatement,
    };
    try std.testing.expectEqual(@as(usize, 1), outer_if.else_body.len);
    const nested_if = switch (outer_if.else_body[0]) {
        .meta_if => |meta_if| meta_if,
        else => return error.UnexpectedStatement,
    };
    try std.testing.expectEqualStrings("true", nested_if.condition);
    try std.testing.expectEqual(@as(usize, 1), nested_if.body.len);
    try std.testing.expectEqual(@as(usize, 1), nested_if.else_body.len);
    switch (nested_if.body[0]) {
        .meta_continue => {},
        else => return error.UnexpectedStatement,
    }
    switch (nested_if.else_body[0]) {
        .meta_break => {},
        else => return error.UnexpectedStatement,
    }
}

test "parser builds structured Meta loops" {
    var statements = try parseSource(std.testing.allocator,
        \\for i in range(0, 4) {
        \\    emit.u8(i);
        \\}
        \\while false {
        \\    emit.u8(0xff);
        \\}
        \\
    );
    defer statements.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), statements.items.items.len);
    switch (statements.items.items[0]) {
        .meta_for_range => |statement| {
            try std.testing.expectEqualStrings("i", statement.name);
            try std.testing.expectEqual(@as(usize, 1), statement.body.len);
            switch (statement.body[0]) {
                .api_call => |call| try std.testing.expectEqualStrings("emit.u8", call.callee),
                else => return error.UnexpectedStatement,
            }
        },
        else => return error.UnexpectedStatement,
    }
    switch (statements.items.items[1]) {
        .meta_while => |statement| {
            try std.testing.expectEqualStrings("false", statement.condition);
            try std.testing.expectEqual(@as(usize, 1), statement.body.len);
        },
        else => return error.UnexpectedStatement,
    }
}
