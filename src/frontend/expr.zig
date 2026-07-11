const std = @import("std");

const fragment = @import("fragment.zig");
const identifier = @import("identifier.zig");
const meta_data = @import("meta_data.zig");
const meta_io = @import("meta_io.zig");
const meta_std = @import("meta_std.zig");
const module_mod = @import("module.zig");
const output_mod = @import("output/root.zig");
const source = @import("source.zig");
const target_mod = @import("target.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const ExpressionError = Allocator.Error || error{
    DivisionByZero,
    FragmentTooLarge,
    InvalidArgument,
    InvalidCharacter,
    InvalidApiArgument,
    InvalidApiInteger,
    InvalidIntegerBits,
    InvalidNumber,
    InvalidOperand,
    InvalidFragment,
    InvalidSection,
    InvalidToken,
    InvalidType,
    FileNotAvailable,
    MissingEvaluationContext,
    MissingStructFieldValue,
    TypeMismatch,
    UndefinedSymbol,
    UnknownTypeName,
    UnknownField,
    OffsetOverflow,
    UnexpectedEof,
};

pub const Precedence = enum(u8) {
    logical_or = 1,
    logical_and = 2,
    equality = 3,
    comparison = 4,
    bit_or = 5,
    bit_xor = 6,
    bit_and = 7,
    add_sub = 8,
    shl_shr = 9,
    mul_div_mod = 10,
    unary_high = 11,

    fn next(self: Precedence) Precedence {
        return switch (self) {
            .logical_or => .logical_and,
            .logical_and => .equality,
            .equality => .comparison,
            .comparison => .bit_or,
            .bit_or => .bit_xor,
            .bit_xor => .bit_and,
            .bit_and => .add_sub,
            .add_sub => .shl_shr,
            .shl_shr => .mul_div_mod,
            .mul_div_mod, .unary_high => .unary_high,
        };
    }
};

pub const BinaryOp = enum {
    logical_or,
    logical_and,
    equal,
    not_equal,
    less_than,
    less_equal,
    greater_than,
    greater_equal,
    add,
    sub,
    mul,
    div,
    mod,
    shl,
    shr,
    bit_and,
    bit_or,
    bit_xor,

    fn precedence(self: BinaryOp) Precedence {
        return switch (self) {
            .logical_or => .logical_or,
            .logical_and => .logical_and,
            .equal, .not_equal => .equality,
            .less_than, .less_equal, .greater_than, .greater_equal => .comparison,
            .add, .sub => .add_sub,
            .mul, .div, .mod => .mul_div_mod,
            .shl, .shr => .shl_shr,
            .bit_and => .bit_and,
            .bit_xor => .bit_xor,
            .bit_or => .bit_or,
        };
    }
};

pub const UnaryOp = enum {
    plus,
    neg,
    bit_not,
    logical_not,
    lengthof,
};

pub const Node = union(enum) {
    integer: u64,
    boolean: bool,
    string_literal: []u8,
    bytes_literal: []u8,
    symbol: []u8,
    field_access: FieldAccess,
    builtin_call: BuiltinCall,
    unary: Unary,
    binary: Binary,

    pub fn deinit(self: *Node, allocator: Allocator) void {
        switch (self.*) {
            .string_literal, .bytes_literal => |text| allocator.free(text),
            .symbol => |name| allocator.free(name),
            .field_access => |*payload| payload.deinit(allocator),
            .builtin_call => |*payload| payload.deinit(allocator),
            .unary => |*payload| payload.deinit(allocator),
            .binary => |*payload| payload.deinit(allocator),
            .integer, .boolean => {},
        }
        self.* = undefined;
    }
};

pub const FieldAccess = struct {
    object: *Node,
    field_name: []u8,

    pub fn deinit(self: *FieldAccess, allocator: Allocator) void {
        self.object.deinit(allocator);
        allocator.destroy(self.object);
        allocator.free(self.field_name);
        self.* = undefined;
    }
};

pub const BuiltinArgument = union(enum) {
    expression: Node,
    identifier: []u8,
    struct_literal: []u8,

    pub fn deinit(self: *BuiltinArgument, allocator: Allocator) void {
        switch (self.*) {
            .expression => |*node| node.deinit(allocator),
            .identifier => |name| allocator.free(name),
            .struct_literal => |text| allocator.free(text),
        }
        self.* = undefined;
    }
};

pub const BuiltinCall = struct {
    name: []u8,
    args: []BuiltinArgument,

    pub fn deinit(self: *BuiltinCall, allocator: Allocator) void {
        allocator.free(self.name);
        for (self.args) |*arg| {
            arg.deinit(allocator);
        }
        allocator.free(self.args);
        self.* = undefined;
    }
};

pub const Unary = struct {
    op: UnaryOp,
    operand: *Node,

    pub fn deinit(self: *Unary, allocator: Allocator) void {
        self.operand.deinit(allocator);
        allocator.destroy(self.operand);
        self.* = undefined;
    }
};

pub const Binary = struct {
    op: BinaryOp,
    left: *Node,
    right: *Node,

    pub fn deinit(self: *Binary, allocator: Allocator) void {
        self.left.deinit(allocator);
        allocator.destroy(self.left);
        self.right.deinit(allocator);
        allocator.destroy(self.right);
        self.* = undefined;
    }
};

pub const EvalContext = struct {
    module: *module_mod.Module,
    active_target: ?target_mod.Target = null,
    active_section: ?fragment.SectionId = null,
    active_offset: u64 = 0,
    active_file_offset: ?u64 = null,
    output_image: ?output_mod.Image = null,
    file_resolver: ?meta_io.FileResolver = null,
    source_path: ?[]const u8 = null,
    local_context: ?*anyopaque = null,
    resolve_local: ?*const fn (context: *anyopaque, allocator: Allocator, name: []const u8) ExpressionError!?value_mod.Value = null,
    next_unique_symbol: ?*const fn (context: *anyopaque, allocator: Allocator, prefix: []const u8) ExpressionError![]u8 = null,
    call_user_function: ?*const fn (context: *anyopaque, allocator: Allocator, name: []const u8, args: []const BuiltinArgument, eval_ctx: *EvalContext) ExpressionError!value_mod.Value = null,
    evaluate_struct_literal: ?*const fn (context: *anyopaque, allocator: Allocator, text: []const u8, eval_ctx: *EvalContext) ExpressionError!value_mod.Value = null,
};

pub fn parseOwned(allocator: Allocator, input: []const u8) ExpressionError!Node {
    var parser = ExpressionParser.init(allocator, input);
    return parser.parse();
}

pub fn evaluateInteger(node: *const Node, ctx: *EvalContext) ExpressionError!u64 {
    var value = try evaluateValue(ctx.module.allocator, node, ctx);
    defer value.deinit(ctx.module.allocator);
    return expectIntegerValue(value);
}

pub fn evaluateBoolean(node: *const Node, ctx: *EvalContext) ExpressionError!bool {
    var value = try evaluateValue(ctx.module.allocator, node, ctx);
    defer value.deinit(ctx.module.allocator);
    return expectBooleanValue(value);
}

pub fn evaluateValue(allocator: Allocator, node: *const Node, ctx: *EvalContext) ExpressionError!value_mod.Value {
    return switch (node.*) {
        .integer => |value| value_mod.Value.int(value),
        .boolean => |value| .{ .boolean = value },
        .string_literal => |text| .{ .string = try allocator.dupe(u8, text) },
        .bytes_literal => |bytes| .{ .bytes = try allocator.dupe(u8, bytes) },
        .symbol => |name| resolveSymbolValue(allocator, ctx, name),
        .field_access => |payload| evalFieldAccess(allocator, payload, ctx),
        .builtin_call => |payload| evalBuiltinCall(allocator, payload, ctx),
        .unary => |payload| evalUnary(payload.op, payload.operand, ctx),
        .binary => |payload| evalBinary(payload.op, payload.left, payload.right, ctx),
    };
}

const ExpressionParser = struct {
    allocator: Allocator,
    input: []const u8,
    pos: usize = 0,

    fn init(allocator: Allocator, input: []const u8) ExpressionParser {
        return .{
            .allocator = allocator,
            .input = std.mem.trim(u8, input, " \t\r\n"),
        };
    }

    fn parse(self: *ExpressionParser) ExpressionError!Node {
        const expr = try self.parseExpression(.logical_or);
        errdefer {
            var mutable = expr;
            mutable.deinit(self.allocator);
        }

        self.skipWhitespace();
        if (self.peekByte() != null) return error.InvalidToken;
        return expr;
    }

    fn allocNode(self: *ExpressionParser, value: Node) ExpressionError!*Node {
        const node = try self.allocator.create(Node);
        node.* = value;
        return node;
    }

    fn peekByte(self: *const ExpressionParser) ?u8 {
        if (self.pos >= self.input.len) return null;
        return self.input[self.pos];
    }

    fn consumeByte(self: *ExpressionParser) ?u8 {
        const byte = self.peekByte() orelse return null;
        self.pos += 1;
        return byte;
    }

    fn requireByte(self: *ExpressionParser) ExpressionError!u8 {
        return self.consumeByte() orelse error.UnexpectedEof;
    }

    fn consumeExpectedByte(self: *ExpressionParser, expected: u8) ExpressionError!void {
        const byte = try self.requireByte();
        if (byte != expected) return error.InvalidToken;
    }

    fn skipWhitespace(self: *ExpressionParser) void {
        while (self.peekByte()) |byte| {
            if (!std.ascii.isWhitespace(byte)) break;
            self.pos += 1;
        }
    }

    fn parseExpression(self: *ExpressionParser, min_precedence: Precedence) ExpressionError!Node {
        var left = try self.parseUnary();
        errdefer left.deinit(self.allocator);

        while (self.peekOperator()) |op| {
            const precedence = op.precedence();
            if (@intFromEnum(precedence) < @intFromEnum(min_precedence)) break;

            self.consumeOperator(op);
            var right = try self.parseExpression(precedence.next());
            errdefer right.deinit(self.allocator);

            const left_node = try self.allocNode(left);
            errdefer {
                left_node.deinit(self.allocator);
                self.allocator.destroy(left_node);
            }
            const right_node = try self.allocNode(right);
            errdefer {
                right_node.deinit(self.allocator);
                self.allocator.destroy(right_node);
            }

            left = .{
                .binary = .{
                    .op = op,
                    .left = left_node,
                    .right = right_node,
                },
            };
        }

        return left;
    }

    fn parsePostfix(self: *ExpressionParser, base: Node) ExpressionError!Node {
        var result = base;
        errdefer result.deinit(self.allocator);

        while (true) {
            self.skipWhitespace();
            if (self.peekByte() != '.') break;
            try self.consumeExpectedByte('.');
            result = try self.parseFieldAccess(result);
        }

        return result;
    }

    fn parseFieldAccess(self: *ExpressionParser, base: Node) ExpressionError!Node {
        const field_start = self.pos;
        const first = self.peekByte() orelse return error.UnexpectedEof;
        if (!isFieldNameStart(first)) return error.InvalidToken;
        while (self.peekByte()) |byte| {
            if (!isFieldNameContinue(byte)) break;
            self.pos += 1;
        }

        const field_name = try self.allocator.dupe(u8, self.input[field_start..self.pos]);
        errdefer self.allocator.free(field_name);

        const object = try self.allocator.create(Node);
        errdefer self.allocator.destroy(object);
        object.* = base;

        return .{
            .field_access = .{
                .object = object,
                .field_name = field_name,
            },
        };
    }

    fn parseUnary(self: *ExpressionParser) ExpressionError!Node {
        self.skipWhitespace();
        const byte = self.peekByte() orelse return try self.parsePrimary();
        return switch (byte) {
            '!' => blk: {
                try self.consumeExpectedByte('!');
                var operand = try self.parseUnary();
                errdefer operand.deinit(self.allocator);
                break :blk .{
                    .unary = .{
                        .op = .logical_not,
                        .operand = try self.allocNode(operand),
                    },
                };
            },
            '+' => blk: {
                try self.consumeExpectedByte('+');
                var operand = try self.parseUnary();
                errdefer operand.deinit(self.allocator);
                break :blk .{
                    .unary = .{
                        .op = .plus,
                        .operand = try self.allocNode(operand),
                    },
                };
            },
            '-' => blk: {
                try self.consumeExpectedByte('-');
                var operand = try self.parseUnary();
                errdefer operand.deinit(self.allocator);
                break :blk .{
                    .unary = .{
                        .op = .neg,
                        .operand = try self.allocNode(operand),
                    },
                };
            },
            '~' => blk: {
                try self.consumeExpectedByte('~');
                var operand = try self.parseUnary();
                errdefer operand.deinit(self.allocator);
                break :blk .{
                    .unary = .{
                        .op = .bit_not,
                        .operand = try self.allocNode(operand),
                    },
                };
            },
            else => try self.parsePrimary(),
        };
    }

    fn parsePrimary(self: *ExpressionParser) ExpressionError!Node {
        self.skipWhitespace();
        const byte = self.peekByte() orelse return error.UnexpectedEof;

        if (std.ascii.isDigit(byte)) return self.parsePostfix(try self.parseNumber());
        if (byte == '"' or byte == '\'') return self.parsePostfix(try self.parseStringLiteral());
        if (identifier.isStart(byte)) return self.parsePostfix(try self.parseIdentifierOrBuiltin());
        if (byte == '(') {
            try self.consumeExpectedByte('(');
            var expr = try self.parseExpression(.logical_or);
            errdefer expr.deinit(self.allocator);
            self.skipWhitespace();
            try self.consumeExpectedByte(')');
            return self.parsePostfix(expr);
        }

        return error.InvalidCharacter;
    }

    fn parseNumber(self: *ExpressionParser) ExpressionError!Node {
        var token: std.ArrayList(u8) = .empty;
        defer token.deinit(self.allocator);

        while (self.peekByte()) |byte| {
            if (std.ascii.isAlphanumeric(byte) or byte == '_') {
                try token.append(self.allocator, try self.requireByte());
            } else {
                break;
            }
        }

        return .{ .integer = try parseIntegerLiteral(self.allocator, token.items) };
    }

    fn parseStringLiteral(self: *ExpressionParser) ExpressionError!Node {
        const quote = try self.requireByte();
        var text: std.ArrayList(u8) = .empty;
        errdefer text.deinit(self.allocator);

        while (self.consumeByte()) |byte| {
            if (byte == quote) {
                if (self.peekByte() == quote) {
                    try self.consumeExpectedByte(quote);
                    try text.append(self.allocator, quote);
                    continue;
                }
                return .{ .string_literal = try text.toOwnedSlice(self.allocator) };
            }

            try text.append(self.allocator, byte);
        }

        return error.InvalidToken;
    }

    fn parseIdentifierOrBuiltin(self: *ExpressionParser) ExpressionError!Node {
        var token: std.ArrayList(u8) = .empty;
        defer token.deinit(self.allocator);

        while (self.peekByte()) |byte| {
            if (isExpressionIdentifierContinue(byte)) {
                try token.append(self.allocator, try self.requireByte());
            } else {
                break;
            }
        }
        if (token.items.len == 0) return error.InvalidToken;
        try self.appendDottedBuiltinSuffix(&token);

        if (std.mem.eql(u8, token.items, "true")) {
            return .{ .boolean = true };
        }
        if (std.mem.eql(u8, token.items, "false")) {
            return .{ .boolean = false };
        }
        if (std.mem.eql(u8, token.items, "b") and self.peekByte() == '"') {
            const literal = try self.parseStringLiteral();
            switch (literal) {
                .string_literal => |text| return .{ .bytes_literal = text },
                else => return error.InvalidToken,
            }
        }

        if (self.peekByte() == '(') {
            return self.parseBuiltinCall(token.items);
        }

        return .{ .symbol = try self.allocator.dupe(u8, token.items) };
    }

    fn appendDottedBuiltinSuffix(self: *ExpressionParser, token: *std.ArrayList(u8)) ExpressionError!void {
        if (!std.mem.eql(u8, token.items, "load") and
            !std.mem.eql(u8, token.items, "fs") and
            !std.mem.eql(u8, token.items, "toml") and
            !std.mem.eql(u8, token.items, "json") and
            !std.mem.eql(u8, token.items, "bytes") and
            !std.mem.eql(u8, token.items, "list") and
            !std.mem.eql(u8, token.items, "map") and
            !std.mem.eql(u8, token.items, "sym") and
            !std.mem.eql(u8, token.items, "tokens") and
            !std.mem.eql(u8, token.items, "match"))
        {
            return;
        }
        if (self.peekByte() != '.') return;

        const saved_pos = self.pos;
        const saved_len = token.items.len;

        try token.append(self.allocator, try self.requireByte());
        while (self.peekByte()) |byte| {
            if (!isFieldNameContinue(byte)) break;
            try token.append(self.allocator, try self.requireByte());
        }

        if ((std.mem.eql(u8, token.items, "load.bytes") or loadByteCount(token.items) != null or meta_std.isBuiltinName(token.items) or meta_data.isBuiltinName(token.items) or std.mem.eql(u8, token.items, "sym.unique")) and self.peekByte() == '(') return;

        self.pos = saved_pos;
        token.shrinkRetainingCapacity(saved_len);
    }

    fn parseBuiltinCall(self: *ExpressionParser, name: []const u8) ExpressionError!Node {
        const owned_name = try self.allocator.dupe(u8, name);
        errdefer self.allocator.free(owned_name);

        self.skipWhitespace();
        try self.consumeExpectedByte('(');

        var args: std.ArrayList(BuiltinArgument) = .empty;
        errdefer deinitBuiltinArguments(&args, self.allocator);

        self.skipWhitespace();
        if (self.peekByte() == ')') {
            try self.consumeExpectedByte(')');
            const owned_args = try args.toOwnedSlice(self.allocator);
            errdefer deinitBuiltinArgumentSlice(owned_args, self.allocator);
            return .{
                .builtin_call = .{
                    .name = owned_name,
                    .args = owned_args,
                },
            };
        }

        while (true) {
            var arg = try self.parseBuiltinArgument(name, args.items.len);
            args.append(self.allocator, arg) catch |err| {
                arg.deinit(self.allocator);
                return err;
            };
            self.skipWhitespace();
            const byte = self.peekByte() orelse return error.UnexpectedEof;
            if (byte == ',') {
                try self.consumeExpectedByte(',');
                continue;
            }
            if (byte == ')') {
                try self.consumeExpectedByte(')');
                break;
            }
            return error.InvalidToken;
        }

        const owned_args = try args.toOwnedSlice(self.allocator);
        errdefer deinitBuiltinArgumentSlice(owned_args, self.allocator);

        return .{
            .builtin_call = .{
                .name = owned_name,
                .args = owned_args,
            },
        };
    }

    fn parseBuiltinArgument(self: *ExpressionParser, builtin_name: []const u8, arg_index: usize) ExpressionError!BuiltinArgument {
        self.skipWhitespace();
        const start = self.pos;
        if (try self.parseStructLiteralArgumentText()) |text| {
            return .{ .struct_literal = text };
        }
        if (self.peekByte()) |byte| {
            if (identifier.isStart(byte)) {
                var saw_field_separator = false;
                while (self.peekByte()) |ident_byte| {
                    if (!identifier.isContinue(ident_byte)) break;
                    if (ident_byte == '.') saw_field_separator = true;
                    self.pos += 1;
                }
                const ident_end = self.pos;
                self.skipWhitespace();
                const next = self.peekByte();
                const is_boolean_literal =
                    std.mem.eql(u8, self.input[start..ident_end], "true") or
                    std.mem.eql(u8, self.input[start..ident_end], "false");
                const allow_dotted_identifier = saw_field_separator and
                    arg_index == 1 and
                    std.mem.eql(u8, builtin_name, "offset_of");
                if (!is_boolean_literal and
                    (!saw_field_separator or allow_dotted_identifier) and
                    (next == ',' or next == ')'))
                {
                    return .{ .identifier = try self.allocator.dupe(u8, self.input[start..ident_end]) };
                }
                self.pos = start;
            }
        }

        return .{ .expression = try self.parseExpression(.logical_or) };
    }

    fn parseStructLiteralArgumentText(self: *ExpressionParser) ExpressionError!?[]u8 {
        const start = self.pos;
        const first = self.peekByte() orelse return null;
        if (!identifier.isStart(first)) return null;

        while (self.peekByte()) |byte| {
            if (!identifier.isContinue(byte)) break;
            self.pos += 1;
        }
        self.skipWhitespace();
        if (self.peekByte() != '{') {
            self.pos = start;
            return null;
        }

        var depth: usize = 0;
        while (self.peekByte()) |byte| {
            if (byte == '"' or byte == '\'') {
                self.pos = skipQuotedText(self.input, self.pos) orelse return error.InvalidToken;
                continue;
            }
            self.pos += 1;
            if (byte == '{') {
                depth += 1;
            } else if (byte == '}') {
                if (depth == 0) return error.InvalidToken;
                depth -= 1;
                if (depth == 0) {
                    return try self.allocator.dupe(u8, std.mem.trim(u8, self.input[start..self.pos], " \t\r\n"));
                }
            }
        }

        return error.UnexpectedEof;
    }

    fn peekOperator(self: *ExpressionParser) ?BinaryOp {
        self.skipWhitespace();
        const rest = self.input[self.pos..];
        if (rest.len == 0) return null;

        if (std.mem.startsWith(u8, rest, "<<")) return .shl;
        if (std.mem.startsWith(u8, rest, ">>")) return .shr;
        if (std.mem.startsWith(u8, rest, "&&")) return .logical_and;
        if (std.mem.startsWith(u8, rest, "||")) return .logical_or;
        if (std.mem.startsWith(u8, rest, "==")) return .equal;
        if (std.mem.startsWith(u8, rest, "!=")) return .not_equal;
        if (std.mem.startsWith(u8, rest, "<=")) return .less_equal;
        if (std.mem.startsWith(u8, rest, ">=")) return .greater_equal;

        return switch (rest[0]) {
            '<' => .less_than,
            '>' => .greater_than,
            '+' => .add,
            '-' => .sub,
            '*' => .mul,
            '/' => .div,
            '%' => .mod,
            '&' => .bit_and,
            '|' => .bit_or,
            '^' => .bit_xor,
            else => null,
        };
    }

    fn consumeOperator(self: *ExpressionParser, op: BinaryOp) void {
        switch (op) {
            .shl,
            .shr,
            .logical_and,
            .logical_or,
            .equal,
            .not_equal,
            .less_equal,
            .greater_equal,
            => self.pos += 2,
            .less_than,
            .greater_than,
            .add,
            .sub,
            .mul,
            .div,
            .mod,
            .bit_and,
            .bit_or,
            .bit_xor,
            => self.pos += 1,
        }
        self.skipWhitespace();
    }
};

fn isExpressionIdentifierContinue(byte: u8) bool {
    return byte != '.' and identifier.isContinue(byte);
}

fn isFieldNameStart(byte: u8) bool {
    return byte != '.' and identifier.isStart(byte);
}

fn isFieldNameContinue(byte: u8) bool {
    return byte != '.' and identifier.isContinue(byte);
}

fn deinitBuiltinArguments(args: *std.ArrayList(BuiltinArgument), allocator: Allocator) void {
    for (args.items) |*arg| {
        arg.deinit(allocator);
    }
    args.deinit(allocator);
}

fn deinitBuiltinArgumentSlice(args: []BuiltinArgument, allocator: Allocator) void {
    for (args) |*arg| {
        arg.deinit(allocator);
    }
    allocator.free(args);
}

fn skipQuotedText(text: []const u8, quote_index: usize) ?usize {
    const quote = text[quote_index];
    var index = quote_index + 1;
    while (index < text.len) : (index += 1) {
        if (text[index] == quote) return index + 1;
    }
    return null;
}

fn evalUnary(op: UnaryOp, operand: *const Node, ctx: *EvalContext) ExpressionError!value_mod.Value {
    return switch (op) {
        .plus => value_mod.Value.int(try evaluateInteger(operand, ctx)),
        .neg => value_mod.Value.int(0 -% try evaluateInteger(operand, ctx)),
        .bit_not => value_mod.Value.int(~try evaluateInteger(operand, ctx)),
        .logical_not => .{ .boolean = !try evaluateBoolean(operand, ctx) },
        .lengthof => switch (operand.*) {
            .string_literal => |text| value_mod.Value.int(text.len),
            .bytes_literal => |bytes| value_mod.Value.int(bytes.len),
            else => value_mod.Value.int(countDecimalDigits(try evaluateInteger(operand, ctx))),
        },
    };
}

fn evalBinary(
    op: BinaryOp,
    left: *const Node,
    right: *const Node,
    ctx: *EvalContext,
) ExpressionError!value_mod.Value {
    return switch (op) {
        .logical_or => blk: {
            if (try evaluateBoolean(left, ctx)) break :blk .{ .boolean = true };
            break :blk .{ .boolean = try evaluateBoolean(right, ctx) };
        },
        .logical_and => blk: {
            if (!(try evaluateBoolean(left, ctx))) break :blk .{ .boolean = false };
            break :blk .{ .boolean = try evaluateBoolean(right, ctx) };
        },
        .equal => .{ .boolean = try valuesEqual(left, right, ctx) },
        .not_equal => .{ .boolean = !try valuesEqual(left, right, ctx) },
        .less_than => .{ .boolean = try evaluateInteger(left, ctx) < try evaluateInteger(right, ctx) },
        .less_equal => .{ .boolean = try evaluateInteger(left, ctx) <= try evaluateInteger(right, ctx) },
        .greater_than => .{ .boolean = try evaluateInteger(left, ctx) > try evaluateInteger(right, ctx) },
        .greater_equal => .{ .boolean = try evaluateInteger(left, ctx) >= try evaluateInteger(right, ctx) },
        .add => blk: {
            const value = std.math.add(u64, try evaluateInteger(left, ctx), try evaluateInteger(right, ctx)) catch return error.InvalidNumber;
            break :blk value_mod.Value.int(value);
        },
        .sub => blk: {
            const value = std.math.sub(u64, try evaluateInteger(left, ctx), try evaluateInteger(right, ctx)) catch return error.InvalidNumber;
            break :blk value_mod.Value.int(value);
        },
        .mul => blk: {
            const value = std.math.mul(u64, try evaluateInteger(left, ctx), try evaluateInteger(right, ctx)) catch return error.InvalidNumber;
            break :blk value_mod.Value.int(value);
        },
        .div => blk: {
            const divisor = try evaluateInteger(right, ctx);
            if (divisor == 0) return error.DivisionByZero;
            break :blk value_mod.Value.int(@divTrunc(try evaluateInteger(left, ctx), divisor));
        },
        .mod => blk: {
            const divisor = try evaluateInteger(right, ctx);
            if (divisor == 0) return error.DivisionByZero;
            break :blk value_mod.Value.int(@mod(try evaluateInteger(left, ctx), divisor));
        },
        .shl => blk: {
            const amount = try evaluateInteger(right, ctx);
            if (amount >= @bitSizeOf(u64)) return value_mod.Value.int(0);
            const shift: std.math.Log2Int(u64) = @intCast(amount);
            break :blk value_mod.Value.int((try evaluateInteger(left, ctx)) << shift);
        },
        .shr => blk: {
            const amount = try evaluateInteger(right, ctx);
            if (amount >= @bitSizeOf(u64)) return value_mod.Value.int(0);
            const shift: std.math.Log2Int(u64) = @intCast(amount);
            break :blk value_mod.Value.int((try evaluateInteger(left, ctx)) >> shift);
        },
        .bit_and => value_mod.Value.int((try evaluateInteger(left, ctx)) & (try evaluateInteger(right, ctx))),
        .bit_or => value_mod.Value.int((try evaluateInteger(left, ctx)) | (try evaluateInteger(right, ctx))),
        .bit_xor => value_mod.Value.int((try evaluateInteger(left, ctx)) ^ (try evaluateInteger(right, ctx))),
    };
}

fn evalBuiltinCall(allocator: Allocator, call: BuiltinCall, ctx: *EvalContext) ExpressionError!value_mod.Value {
    if (meta_std.isBuiltinName(call.name)) {
        return evalMetaStdBuiltin(allocator, call, ctx);
    }
    if (meta_data.isBuiltinName(call.name)) {
        return evalMetaDataBuiltin(allocator, call, ctx);
    }
    if (!isBuiltinName(call.name)) {
        const local_context = ctx.local_context orelse return error.InvalidOperand;
        const callback = ctx.call_user_function orelse return error.InvalidOperand;
        return callback(local_context, allocator, call.name, call.args, ctx);
    }
    if (std.mem.eql(u8, call.name, "sym.unique")) {
        if (call.args.len != 1) return error.InvalidArgument;
        const prefix = try builtinStringArg(allocator, call, 0, ctx);
        defer allocator.free(prefix);
        const local_context = ctx.local_context orelse return error.MissingEvaluationContext;
        const next_unique_symbol = ctx.next_unique_symbol orelse return error.MissingEvaluationContext;
        return .{ .string = try next_unique_symbol(local_context, allocator, prefix) };
    }
    if (std.mem.eql(u8, call.name, "sizeof")) {
        if (call.args.len != 1) return error.InvalidArgument;
        return value_mod.Value.int(try sizeofType(ctx, try builtinIdentifierArg(call, 0)));
    }
    if (std.mem.eql(u8, call.name, "offset_of")) {
        if (call.args.len != 2) return error.InvalidArgument;
        return value_mod.Value.int(try offsetOf(ctx, try builtinIdentifierArg(call, 0), try builtinIdentifierArg(call, 1)));
    }
    if (std.mem.eql(u8, call.name, "lengthof")) {
        if (call.args.len != 1) return error.InvalidArgument;
        return value_mod.Value.int(switch (call.args[0]) {
            .expression => |*node| switch (node.*) {
                .string_literal => |text| text.len,
                .bytes_literal => |bytes| bytes.len,
                else => blk: {
                    var value = try evaluateValue(allocator, node, ctx);
                    defer value.deinit(allocator);
                    break :blk switch (value) {
                        .string => |text| text.len,
                        .bytes => |bytes| bytes.len,
                        else => countDecimalDigits(value.expectInteger() catch return error.TypeMismatch),
                    };
                },
            },
            .identifier => |name| blk: {
                var value = try resolveSymbolValue(allocator, ctx, name);
                defer value.deinit(allocator);
                break :blk switch (value) {
                    .string => |text| text.len,
                    .bytes => |bytes| bytes.len,
                    else => countDecimalDigits(value.expectInteger() catch return error.TypeMismatch),
                };
            },
            .struct_literal => |literal| blk: {
                var value = try evaluateStructLiteralArg(allocator, literal, ctx);
                defer value.deinit(allocator);
                break :blk countDecimalDigits(value.expectInteger() catch return error.TypeMismatch);
            },
        });
    }
    if (std.mem.eql(u8, call.name, "pack")) {
        if (call.args.len != 1) return error.InvalidArgument;
        var value = try evaluateBuiltinValueArg(allocator, call.args[0], ctx);
        defer value.deinit(allocator);
        const struct_value = value.expectStruct() catch return error.TypeMismatch;
        const packed_bytes = value_mod.packStructValue(allocator, &ctx.module.types, struct_value) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.ExpectedStruct => return error.TypeMismatch,
            error.IntegerOverflow => return error.InvalidNumber,
            error.FragmentTooLarge => return error.FragmentTooLarge,
            error.InvalidApiArgument => return error.InvalidApiArgument,
            error.InvalidApiInteger => return error.InvalidApiInteger,
            error.InvalidIntegerBits => return error.InvalidIntegerBits,
            error.InvalidType => return error.InvalidType,
            error.MissingStructFieldValue => return error.MissingStructFieldValue,
        };
        return .{ .bytes = packed_bytes };
    }
    if (std.mem.eql(u8, call.name, "here")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const active_section = ctx.active_section orelse return error.MissingEvaluationContext;
        const section = ctx.module.sections.get(active_section) catch return error.InvalidOperand;
        return value_mod.Value.int(std.math.add(u64, section.origin, ctx.active_offset) catch return error.InvalidNumber);
    }
    if (std.mem.eql(u8, call.name, "region_base")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const active_section = ctx.active_section orelse return error.MissingEvaluationContext;
        const section = ctx.module.sections.get(active_section) catch return error.InvalidOperand;
        return value_mod.Value.int(section.origin);
    }
    if (std.mem.eql(u8, call.name, "file_offset")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const active_section = ctx.active_section orelse return error.MissingEvaluationContext;
        const section = ctx.module.sections.get(active_section) catch return error.InvalidOperand;
        const region_offset = ctx.active_file_offset orelse ctx.active_offset;
        return value_mod.Value.int(std.math.add(u64, section.file_offset, region_offset) catch return error.InvalidNumber);
    }
    if (std.mem.eql(u8, call.name, "file_cursor_real")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const active_section = ctx.active_section orelse return error.MissingEvaluationContext;
        const section = ctx.module.sections.get(active_section) catch return error.InvalidOperand;
        const region_offset = ctx.active_file_offset orelse ctx.active_offset;
        return value_mod.Value.int(std.math.add(u64, section.file_offset, region_offset) catch return error.InvalidNumber);
    }
    if (std.mem.eql(u8, call.name, "file_cursor_potential")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const active_section = ctx.active_section orelse return error.MissingEvaluationContext;
        const section = ctx.module.sections.get(active_section) catch return error.InvalidOperand;
        return value_mod.Value.int(std.math.add(u64, section.file_offset, ctx.active_offset) catch return error.InvalidNumber);
    }
    if (std.mem.eql(u8, call.name, "tail_reserve_size")) {
        if (call.args.len != 0) return error.InvalidArgument;
        const region_file_offset = ctx.active_file_offset orelse ctx.active_offset;
        if (ctx.active_offset <= region_file_offset) return value_mod.Value.int(0);
        return value_mod.Value.int(ctx.active_offset - region_file_offset);
    }
    if (std.mem.eql(u8, call.name, "region_file_offset") or
        std.mem.eql(u8, call.name, "region_file_size") or
        std.mem.eql(u8, call.name, "region_logical_size"))
    {
        if (call.args.len != 1) return error.InvalidArgument;
        const output_image = ctx.output_image orelse return error.MissingEvaluationContext;
        const target = try outputLoadTarget(allocator, ctx, call.args[0]);
        const facts = if (target.explicit_section)
            output_mod.regionFactsForSection(output_image, target.section, target.address) catch |err| return mapOutputImageError(err)
        else
            output_mod.regionFactsForAddress(output_image, target.address) catch |err| return mapOutputImageError(err);
        if (std.mem.eql(u8, call.name, "region_file_offset")) return value_mod.Value.int(facts.file_offset);
        if (std.mem.eql(u8, call.name, "region_file_size")) return value_mod.Value.int(facts.file_size);
        return value_mod.Value.int(facts.logical_size);
    }
    if (std.mem.eql(u8, call.name, "label_addr")) {
        if (call.args.len != 1) return error.InvalidArgument;
        const name = try builtinLabelNameArg(allocator, call, 0, ctx);
        defer allocator.free(name);
        return value_mod.Value.int(try labelAddress(ctx, name));
    }
    if (std.mem.eql(u8, call.name, "load.bytes")) {
        if (call.args.len != 2) return error.InvalidArgument;
        const load_target = try outputLoadTarget(allocator, ctx, call.args[0]);
        const byte_count = try evaluateBuiltinIntegerArg(allocator, call.args[1], ctx);
        if (byte_count > std.math.maxInt(usize)) return error.FragmentTooLarge;
        const bytes = try allocator.alloc(u8, @intCast(byte_count));
        errdefer allocator.free(bytes);
        if (ctx.output_image) |image| {
            if (load_target.explicit_section)
                image.loadBytesInSection(load_target.section, load_target.address, bytes) catch |err| return mapOutputImageError(err)
            else
                image.loadBytes(load_target.address, bytes) catch |err| return mapOutputImageError(err);
        } else {
            try ctx.module.loadBytesAt(load_target.section, load_target.address, bytes);
        }
        return .{ .bytes = bytes };
    }
    if (std.mem.eql(u8, call.name, "load.u8") or
        std.mem.eql(u8, call.name, "load.u16") or
        std.mem.eql(u8, call.name, "load.u32") or
        std.mem.eql(u8, call.name, "load.u64"))
    {
        const byte_count = loadByteCount(call.name) orelse return error.InvalidOperand;
        if (call.args.len != 1) return error.InvalidArgument;
        const load_target = try outputLoadTarget(allocator, ctx, call.args[0]);
        if (ctx.output_image) |image| {
            const integer = if (load_target.explicit_section)
                image.loadIntegerInSection(load_target.section, load_target.address, byte_count) catch |err| return mapOutputImageError(err)
            else
                image.loadInteger(load_target.address, byte_count) catch |err| return mapOutputImageError(err);
            return value_mod.Value.int(integer);
        }
        return value_mod.Value.int(try ctx.module.loadIntegerAt(load_target.section, load_target.address, byte_count));
    }
    return error.InvalidOperand;
}

fn evalMetaStdBuiltin(allocator: Allocator, call: BuiltinCall, ctx: *EvalContext) ExpressionError!value_mod.Value {
    var args = try allocator.alloc(value_mod.Value, call.args.len);
    errdefer allocator.free(args);
    var initialized: usize = 0;
    errdefer {
        for (args[0..initialized]) |*arg| {
            arg.deinit(allocator);
        }
    }

    for (call.args, 0..) |arg, index| {
        args[index] = try evaluateBuiltinValueArg(allocator, arg, ctx);
        initialized += 1;
    }

    const result = meta_std.evalBuiltin(allocator, call.name, args) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArgument => return error.InvalidArgument,
        error.InvalidApiInteger => return error.InvalidApiInteger,
        error.OutputTooLarge => return error.FragmentTooLarge,
        error.TypeMismatch => return error.TypeMismatch,
    };

    for (args[0..initialized]) |*arg| {
        arg.deinit(allocator);
    }
    allocator.free(args);
    return result;
}

fn evalMetaDataBuiltin(allocator: Allocator, call: BuiltinCall, ctx: *EvalContext) ExpressionError!value_mod.Value {
    var args = try allocator.alloc(value_mod.Value, call.args.len);
    errdefer allocator.free(args);
    var initialized: usize = 0;
    errdefer {
        for (args[0..initialized]) |*arg| {
            arg.deinit(allocator);
        }
    }

    for (call.args, 0..) |arg, index| {
        args[index] = try evaluateBuiltinValueArg(allocator, arg, ctx);
        initialized += 1;
    }

    const result = meta_data.evalBuiltin(allocator, call.name, args, ctx.file_resolver, ctx.source_path) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.InvalidArgument => return error.InvalidArgument,
        error.InvalidApiInteger => return error.InvalidApiInteger,
        error.TypeMismatch => return error.TypeMismatch,
        error.FileNotAvailable => return error.FileNotAvailable,
        error.Syntax,
        error.InvalidUtf8,
        error.Overflow,
        error.DuplicateKey,
        => return error.InvalidApiArgument,
    };

    for (args[0..initialized]) |*arg| {
        arg.deinit(allocator);
    }
    allocator.free(args);
    return result;
}

pub fn evaluateBuiltinValueArg(allocator: Allocator, arg: BuiltinArgument, ctx: *EvalContext) ExpressionError!value_mod.Value {
    return switch (arg) {
        .expression => |*node| evaluateValue(allocator, node, ctx),
        .identifier => |name| resolveSymbolValue(allocator, ctx, name),
        .struct_literal => |literal| evaluateStructLiteralArg(allocator, literal, ctx),
    };
}

fn evaluateStructLiteralArg(allocator: Allocator, text: []const u8, ctx: *EvalContext) ExpressionError!value_mod.Value {
    const local_context = ctx.local_context orelse return error.MissingEvaluationContext;
    const callback = ctx.evaluate_struct_literal orelse return error.MissingEvaluationContext;
    return callback(local_context, allocator, text, ctx);
}

fn evalFieldAccess(allocator: Allocator, access: FieldAccess, ctx: *EvalContext) ExpressionError!value_mod.Value {
    switch (access.object.*) {
        .symbol => |name| {
            if (std.mem.eql(u8, name, "target")) {
                const active_target = ctx.active_target orelse ctx.module.target;
                if (std.mem.eql(u8, access.field_name, "bits") or
                    std.mem.eql(u8, access.field_name, "xlen"))
                {
                    return value_mod.Value.int(active_target.bits() orelse return error.InvalidOperand);
                }
                return error.UnknownField;
            }
        },
        else => {},
    }

    var object = try evaluateValue(allocator, access.object, ctx);
    defer object.deinit(allocator);

    const struct_value = switch (object) {
        .@"struct" => |stored| stored,
        .void, .integer, .boolean, .string, .bytes, .type, .list, .map => return error.TypeMismatch,
    };

    return (try struct_value.fieldValueByName(allocator, access.field_name)) orelse error.UnknownField;
}

fn builtinIdentifierArg(call: BuiltinCall, index: usize) ExpressionError![]const u8 {
    if (index >= call.args.len) return error.InvalidArgument;
    return switch (call.args[index]) {
        .identifier => |name| name,
        .expression, .struct_literal => error.InvalidArgument,
    };
}

fn builtinStringArg(allocator: Allocator, call: BuiltinCall, index: usize, ctx: *EvalContext) ExpressionError![]u8 {
    if (index >= call.args.len) return error.InvalidArgument;
    var value = try evaluateBuiltinValueArg(allocator, call.args[index], ctx);
    defer value.deinit(allocator);
    const text = value.expectString() catch return error.TypeMismatch;
    return try allocator.dupe(u8, text);
}

fn builtinLabelNameArg(allocator: Allocator, call: BuiltinCall, index: usize, ctx: *EvalContext) ExpressionError![]u8 {
    if (index >= call.args.len) return error.InvalidArgument;
    return switch (call.args[index]) {
        .identifier => |name| blk: {
            var resolved = resolveSymbolValue(allocator, ctx, name) catch |err| switch (err) {
                error.UndefinedSymbol => break :blk try allocator.dupe(u8, name),
                else => return err,
            };
            defer resolved.deinit(allocator);
            break :blk switch (resolved) {
                .string => |text| try allocator.dupe(u8, text),
                .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => try allocator.dupe(u8, name),
            };
        },
        .expression => builtinStringArg(allocator, call, index, ctx),
        .struct_literal => error.InvalidArgument,
    };
}

fn sizeofType(ctx: *EvalContext, name: []const u8) ExpressionError!u64 {
    const id = ctx.module.lookupTypeName(name) orelse return error.UnknownTypeName;
    return (ctx.module.typeLayout(id) catch return error.InvalidOperand).size;
}

fn offsetOf(ctx: *EvalContext, type_name: []const u8, field_name: []const u8) ExpressionError!u64 {
    var current_id = ctx.module.lookupTypeName(type_name) orelse return error.UnknownTypeName;
    var total_offset: u64 = 0;
    var rest = field_name;

    while (true) {
        if (rest.len == 0) return error.InvalidArgument;
        const dot_index = std.mem.indexOfScalar(u8, rest, '.');
        const segment = if (dot_index) |index| rest[0..index] else rest;
        if (segment.len == 0) return error.InvalidArgument;

        const field = ctx.module.types.aggregateField(current_id, segment) catch |err| switch (err) {
            error.UnknownField => return error.UnknownField,
            error.ExpectedStruct,
            error.InvalidType,
            => return error.InvalidOperand,
        };
        total_offset = std.math.add(u64, total_offset, field.offset) catch return error.InvalidNumber;

        const next_dot = dot_index orelse return total_offset;

        const field_type = ctx.module.types.get(field.ty) catch return error.InvalidOperand;
        switch (field_type.*) {
            .@"struct", .@"union" => current_id = field.ty,
            .void, .int, .array, .pointer => return error.InvalidOperand,
        }
        rest = rest[next_dot + 1 ..];
    }
}

fn labelAddress(ctx: *EvalContext, name: []const u8) ExpressionError!u64 {
    const id = ctx.module.symbols.lookup(name) orelse return error.UndefinedSymbol;
    const stored = ctx.module.symbols.get(id) catch return error.UndefinedSymbol;
    return switch (stored.binding) {
        .label => |label| blk: {
            const label_section = ctx.module.sections.get(label.section) catch return error.InvalidOperand;
            break :blk std.math.add(u64, label_section.origin, label.offset) catch return error.InvalidNumber;
        },
        .absolute => |absolute| if (absolute < 0) error.InvalidOperand else @intCast(absolute),
        .value, .unknown => error.InvalidOperand,
    };
}

pub const OutputExpressionTarget = struct {
    section: fragment.SectionId,
    address: u64,
    explicit_section: bool,
};

fn outputLoadTarget(allocator: Allocator, ctx: *EvalContext, arg: BuiltinArgument) ExpressionError!OutputExpressionTarget {
    return switch (arg) {
        .identifier => |name| identifierLoadTarget(allocator, ctx, name),
        .expression => |*node| resolveOutputExpressionTarget(allocator, ctx, node),
        .struct_literal => error.InvalidArgument,
    };
}

pub fn resolveOutputExpressionTarget(
    allocator: Allocator,
    ctx: *EvalContext,
    node: *const Node,
) ExpressionError!OutputExpressionTarget {
    return switch (node.*) {
        .symbol => |name| identifierLoadTarget(allocator, ctx, name),
        else => blk: {
            const label_section = try outputLoadLabelSection(allocator, ctx, node);
            break :blk .{
                .section = label_section orelse ctx.active_section orelse return error.MissingEvaluationContext,
                .address = try evaluateInteger(node, ctx),
                .explicit_section = label_section != null,
            };
        },
    };
}

fn identifierLoadTarget(allocator: Allocator, ctx: *EvalContext, name: []const u8) ExpressionError!OutputExpressionTarget {
    if (ctx.resolve_local) |resolve_local| {
        if (ctx.local_context) |local_context| {
            if (try resolve_local(local_context, allocator, name)) |value| {
                var resolved = value;
                defer resolved.deinit(allocator);
                return .{
                    .section = ctx.active_section orelse return error.MissingEvaluationContext,
                    .address = resolved.expectInteger() catch return error.TypeMismatch,
                    .explicit_section = false,
                };
            }
        }
    }
    return labelLoadTarget(ctx, name);
}

fn outputLoadLabelSection(
    allocator: Allocator,
    ctx: *EvalContext,
    node: *const Node,
) ExpressionError!?fragment.SectionId {
    return switch (node.*) {
        .symbol => |name| blk: {
            if (ctx.resolve_local) |resolve_local| {
                if (ctx.local_context) |local_context| {
                    if (try resolve_local(local_context, allocator, name)) |value| {
                        var resolved = value;
                        resolved.deinit(allocator);
                        break :blk null;
                    }
                }
            }
            break :blk labelSectionOrNull(ctx, name);
        },
        .unary => |unary| outputLoadLabelSection(allocator, ctx, unary.operand),
        .binary => |binary| blk: {
            const left = try outputLoadLabelSection(allocator, ctx, binary.left);
            const right = try outputLoadLabelSection(allocator, ctx, binary.right);
            if (left) |left_section| {
                if (right) |right_section| {
                    if (left_section.index != right_section.index) return error.InvalidOperand;
                }
                break :blk left_section;
            }
            break :blk right;
        },
        .field_access => |access| outputLoadLabelSection(allocator, ctx, access.object),
        .builtin_call, .integer, .boolean, .string_literal, .bytes_literal => null,
    };
}

fn labelSectionOrNull(ctx: *EvalContext, name: []const u8) ExpressionError!?fragment.SectionId {
    const id = ctx.module.symbols.lookup(name) orelse return null;
    const stored = ctx.module.symbols.get(id) catch return error.UndefinedSymbol;
    return switch (stored.binding) {
        .label => |label| label.section,
        .absolute, .value, .unknown => null,
    };
}

fn labelLoadTarget(ctx: *EvalContext, name: []const u8) ExpressionError!OutputExpressionTarget {
    const id = ctx.module.symbols.lookup(name) orelse return error.UndefinedSymbol;
    const stored = ctx.module.symbols.get(id) catch return error.UndefinedSymbol;
    return switch (stored.binding) {
        .label => |label| blk: {
            const label_section = ctx.module.sections.get(label.section) catch return error.InvalidOperand;
            break :blk .{
                .section = label.section,
                .address = std.math.add(u64, label_section.origin, label.offset) catch return error.InvalidNumber,
                .explicit_section = true,
            };
        },
        .absolute => |absolute| .{
            .section = ctx.active_section orelse return error.MissingEvaluationContext,
            .address = if (absolute < 0) return error.InvalidOperand else @intCast(absolute),
            .explicit_section = false,
        },
        .value, .unknown => return error.InvalidOperand,
    };
}

pub fn usesOutputLoad(node: *const Node) bool {
    return switch (node.*) {
        .builtin_call => |call| std.mem.eql(u8, call.name, "load.bytes") or loadByteCount(call.name) != null or builtinArgsUseOutputLoad(call.args),
        .field_access => |access| usesOutputLoad(access.object),
        .unary => |unary| usesOutputLoad(unary.operand),
        .binary => |binary| usesOutputLoad(binary.left) or usesOutputLoad(binary.right),
        .integer, .boolean, .string_literal, .bytes_literal, .symbol => false,
    };
}

fn builtinArgsUseOutputLoad(args: []const BuiltinArgument) bool {
    for (args) |arg| {
        switch (arg) {
            .expression => |*node| if (usesOutputLoad(node)) return true,
            .identifier => {},
            .struct_literal => {},
        }
    }
    return false;
}

fn evaluateBuiltinIntegerArg(allocator: Allocator, arg: BuiltinArgument, ctx: *EvalContext) ExpressionError!u64 {
    var value = try evaluateBuiltinValueArg(allocator, arg, ctx);
    defer value.deinit(allocator);
    return value.expectInteger() catch error.TypeMismatch;
}

fn mapOutputImageError(err: output_mod.Error) ExpressionError {
    return switch (err) {
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.OffsetOverflow => error.OffsetOverflow,
    };
}

fn loadByteCount(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "load.u8")) return 1;
    if (std.mem.eql(u8, name, "load.u16")) return 2;
    if (std.mem.eql(u8, name, "load.u32")) return 4;
    if (std.mem.eql(u8, name, "load.u64")) return 8;
    return null;
}

fn resolveSymbolValue(allocator: Allocator, ctx: *EvalContext, name: []const u8) ExpressionError!value_mod.Value {
    if (ctx.resolve_local) |resolve_local| {
        if (ctx.local_context) |local_context| {
            if (try resolve_local(local_context, allocator, name)) |value| return value;
        }
    }

    if (try resolveTypeName(ctx.module, name)) |type_id| return .{ .type = type_id };

    const id = ctx.module.symbols.lookup(name) orelse return error.UndefinedSymbol;
    const stored = ctx.module.symbols.get(id) catch return error.UndefinedSymbol;
    return switch (stored.binding) {
        .value => |binding| try binding.value.clone(allocator),
        .absolute => |absolute| if (absolute < 0) error.InvalidOperand else value_mod.Value.int(@intCast(absolute)),
        .label => |label| blk: {
            const label_section = ctx.module.sections.get(label.section) catch return error.InvalidOperand;
            break :blk value_mod.Value.int(std.math.add(u64, label_section.origin, label.offset) catch return error.InvalidNumber);
        },
        .unknown => error.UndefinedSymbol,
    };
}

fn resolveTypeName(module: *module_mod.Module, name: []const u8) ExpressionError!?@import("types.zig").TypeId {
    if (module.lookupTypeName(name)) |type_id| return type_id;
    if (std.mem.eql(u8, name, "u8")) return try getOrAddBuiltinType(module, "u8", 8, .unsigned);
    if (std.mem.eql(u8, name, "u16")) return try getOrAddBuiltinType(module, "u16", 16, .unsigned);
    if (std.mem.eql(u8, name, "u32")) return try getOrAddBuiltinType(module, "u32", 32, .unsigned);
    if (std.mem.eql(u8, name, "u64")) return try getOrAddBuiltinType(module, "u64", 64, .unsigned);
    if (std.mem.eql(u8, name, "i8")) return try getOrAddBuiltinType(module, "i8", 8, .signed);
    if (std.mem.eql(u8, name, "i16")) return try getOrAddBuiltinType(module, "i16", 16, .signed);
    if (std.mem.eql(u8, name, "i32")) return try getOrAddBuiltinType(module, "i32", 32, .signed);
    if (std.mem.eql(u8, name, "i64")) return try getOrAddBuiltinType(module, "i64", 64, .signed);
    return null;
}

fn getOrAddBuiltinType(
    module: *module_mod.Module,
    name: []const u8,
    bits: u16,
    signedness: @import("types.zig").IntSignedness,
) ExpressionError!@import("types.zig").TypeId {
    return module.getOrAddIntType(name, bits, signedness) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidIntegerBits,
        error.DuplicateTypeName,
        error.TooManyTypes,
        => error.InvalidOperand,
    };
}

fn valuesEqual(left: *const Node, right: *const Node, ctx: *EvalContext) ExpressionError!bool {
    var left_value = try evaluateValue(ctx.module.allocator, left, ctx);
    defer left_value.deinit(ctx.module.allocator);
    var right_value = try evaluateValue(ctx.module.allocator, right, ctx);
    defer right_value.deinit(ctx.module.allocator);

    return switch (left_value) {
        .void => right_value == .void,
        .integer => |left_integer| switch (right_value) {
            .integer => |right_integer| left_integer.value == right_integer.value,
            else => false,
        },
        .boolean => |left_bool| switch (right_value) {
            .boolean => |right_bool| left_bool == right_bool,
            else => false,
        },
        .string => |left_text| switch (right_value) {
            .string => |right_text| std.mem.eql(u8, left_text, right_text),
            else => false,
        },
        .bytes => |left_bytes| switch (right_value) {
            .bytes => |right_bytes| std.mem.eql(u8, left_bytes, right_bytes),
            else => false,
        },
        .type => |left_type| switch (right_value) {
            .type => |right_type| left_type.index == right_type.index,
            else => false,
        },
        .@"struct" => |left_struct| switch (right_value) {
            .@"struct" => |right_struct| structValuesEqual(left_struct, right_struct),
            else => false,
        },
        .list => |left_list| switch (right_value) {
            .list => |right_list| listValuesEqual(left_list, right_list),
            else => false,
        },
        .map => |left_map| switch (right_value) {
            .map => |right_map| mapValuesEqual(left_map, right_map),
            else => false,
        },
    };
}

fn structValuesEqual(left: value_mod.StructValue, right: value_mod.StructValue) bool {
    if (left.type_id.index != right.type_id.index) return false;
    if (left.fields.len != right.fields.len) return false;
    for (left.fields, right.fields) |left_field, right_field| {
        if (!std.mem.eql(u8, left_field.name, right_field.name)) return false;
        if (!valueValuesEqual(left_field.value, right_field.value)) return false;
    }
    return true;
}

fn listValuesEqual(left: value_mod.ListValue, right: value_mod.ListValue) bool {
    if (left.items.len != right.items.len) return false;
    for (left.items, right.items) |left_item, right_item| {
        if (!valueValuesEqual(left_item, right_item)) return false;
    }
    return true;
}

fn mapValuesEqual(left: value_mod.MapValue, right: value_mod.MapValue) bool {
    if (left.entries.len != right.entries.len) return false;
    for (left.entries) |left_entry| {
        const right_entry = right.entryByKey(left_entry.key) orelse return false;
        if (!valueValuesEqual(left_entry.value, right_entry.value)) return false;
    }
    return true;
}

fn valueValuesEqual(left: value_mod.Value, right: value_mod.Value) bool {
    return switch (left) {
        .void => right == .void,
        .integer => |left_integer| switch (right) {
            .integer => |right_integer| left_integer.value == right_integer.value,
            else => false,
        },
        .boolean => |left_bool| switch (right) {
            .boolean => |right_bool| left_bool == right_bool,
            else => false,
        },
        .string => |left_text| switch (right) {
            .string => |right_text| std.mem.eql(u8, left_text, right_text),
            else => false,
        },
        .bytes => |left_bytes| switch (right) {
            .bytes => |right_bytes| std.mem.eql(u8, left_bytes, right_bytes),
            else => false,
        },
        .type => |left_type| switch (right) {
            .type => |right_type| left_type.index == right_type.index,
            else => false,
        },
        .@"struct" => |left_struct| switch (right) {
            .@"struct" => |right_struct| structValuesEqual(left_struct, right_struct),
            else => false,
        },
        .list => |left_list| switch (right) {
            .list => |right_list| listValuesEqual(left_list, right_list),
            else => false,
        },
        .map => |left_map| switch (right) {
            .map => |right_map| mapValuesEqual(left_map, right_map),
            else => false,
        },
    };
}

fn expectIntegerValue(value: value_mod.Value) ExpressionError!u64 {
    return value.expectInteger() catch error.TypeMismatch;
}

fn expectBooleanValue(value: value_mod.Value) ExpressionError!bool {
    return value.expectBoolean() catch error.TypeMismatch;
}

fn stringLiteralToWord(text: []const u8) u64 {
    var value: u64 = 0;
    const count = @min(text.len, @sizeOf(u64));
    var index: usize = 0;
    while (index < count) : (index += 1) {
        const shift: std.math.Log2Int(u64) = @intCast(index * 8);
        value |= @as(u64, text[index]) << shift;
    }
    return value;
}

fn parseIntegerLiteral(allocator: Allocator, token: []const u8) ExpressionError!u64 {
    const normalized = try normalizeNumberToken(allocator, token);
    defer allocator.free(normalized);
    if (normalized.len == 0) return error.InvalidNumber;

    if (std.mem.startsWith(u8, normalized, "0x") or std.mem.startsWith(u8, normalized, "0h")) {
        return std.fmt.parseInt(u64, normalized[2..], 16) catch error.InvalidNumber;
    }
    if (std.mem.endsWith(u8, normalized, "b")) {
        return std.fmt.parseInt(u64, normalized[0 .. normalized.len - 1], 2) catch error.InvalidNumber;
    }
    if (std.mem.endsWith(u8, normalized, "h")) {
        return std.fmt.parseInt(u64, normalized[0 .. normalized.len - 1], 16) catch error.InvalidNumber;
    }
    if (std.mem.endsWith(u8, normalized, "o")) {
        return std.fmt.parseInt(u64, normalized[0 .. normalized.len - 1], 8) catch error.InvalidNumber;
    }
    if (std.mem.startsWith(u8, normalized, "0b")) {
        return std.fmt.parseInt(u64, normalized[2..], 2) catch error.InvalidNumber;
    }
    if (std.mem.startsWith(u8, normalized, "0o")) {
        return std.fmt.parseInt(u64, normalized[2..], 8) catch error.InvalidNumber;
    }
    if (normalized.len > 1 and normalized[0] == '0') {
        return std.fmt.parseInt(u64, normalized[1..], 8) catch
            std.fmt.parseInt(u64, normalized, 10) catch error.InvalidNumber;
    }
    return std.fmt.parseInt(u64, normalized, 10) catch error.InvalidNumber;
}

fn normalizeNumberToken(allocator: Allocator, token: []const u8) Allocator.Error![]u8 {
    var normalized: std.ArrayList(u8) = .empty;
    errdefer normalized.deinit(allocator);

    for (token) |byte| {
        if (byte == '_' or byte == '\'') continue;
        try normalized.append(allocator, std.ascii.toLower(byte));
    }

    return normalized.toOwnedSlice(allocator);
}

fn countDecimalDigits(value: u64) u64 {
    var digits: u64 = 1;
    var rest = value;
    while (rest >= 10) : (digits += 1) {
        rest /= 10;
    }
    return digits;
}

fn isBuiltinName(name: []const u8) bool {
    return std.mem.eql(u8, name, "sizeof") or
        std.mem.eql(u8, name, "lengthof") or
        std.mem.eql(u8, name, "pack") or
        std.mem.eql(u8, name, "offset_of") or
        std.mem.eql(u8, name, "here") or
        std.mem.eql(u8, name, "region_base") or
        std.mem.eql(u8, name, "file_offset") or
        std.mem.eql(u8, name, "file_cursor_real") or
        std.mem.eql(u8, name, "file_cursor_potential") or
        std.mem.eql(u8, name, "tail_reserve_size") or
        std.mem.eql(u8, name, "region_file_offset") or
        std.mem.eql(u8, name, "region_file_size") or
        std.mem.eql(u8, name, "region_logical_size") or
        std.mem.eql(u8, name, "label_addr") or
        std.mem.eql(u8, name, "sym.unique") or
        std.mem.eql(u8, name, "load.bytes") or
        meta_std.isBuiltinName(name) or
        meta_data.isBuiltinName(name) or
        loadByteCount(name) != null;
}

test "expression evaluates arithmetic precedence and bitwise operators" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "(4 + 2) * 3 ^ 1");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 19), try evaluateInteger(&expression, &ctx));
}

test "expression evaluates sizeof and lengthof builtins" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    const u16_type = try module.getOrAddIntType("u16", 16, .unsigned);
    const header = try module.addStructType("Header", &.{
        .{ .name = "magic", .ty = u16_type },
        .{ .name = "flags", .ty = u16_type },
    }, .@"packed");
    try module.registerTypeName("Header", header);
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "sizeof(Header) + lengthof(\"AB\")");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 6), try evaluateInteger(&expression, &ctx));

    _ = try module.defineValue("name", .{ .string = try std.testing.allocator.dupe(u8, "ABCD") }, .@"const", source.unknown_span);
    var string_symbol_expression = try parseOwned(std.testing.allocator, "lengthof(name)");
    defer string_symbol_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 4), try evaluateInteger(&string_symbol_expression, &ctx));
}

test "expression parses dotted Meta std builtins" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "list.get(list.of(1, 2), 1)");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 2), try evaluateInteger(&expression, &ctx));
}

test "expression rejects division by zero" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "4 / (2 - 2)");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectError(error.DivisionByZero, evaluateInteger(&expression, &ctx));
}

test "expression resolves frontend value bindings" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    _ = try module.defineValue("page", value_mod.Value.int(4096), .@"const", source.unknown_span);
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "page + 16");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(u64, 4112), try evaluateInteger(&expression, &ctx));
}

test "expression accesses struct fields with typed integer facts" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    const u16_type = try module.getOrAddIntType("u16", 16, .unsigned);
    const u32_type = try module.getOrAddIntType("u32", 32, .unsigned);
    const header = try module.addStructType("Header", &.{
        .{ .name = "magic", .ty = u16_type },
        .{ .name = "lfanew", .ty = u32_type },
    }, .@"packed");
    try module.registerTypeName("Header", header);

    var struct_value: value_mod.StructValue = .{
        .type_id = header,
        .fields = try std.testing.allocator.alloc(value_mod.StructFieldValue, 2),
    };
    var owns_struct_value = true;
    errdefer if (owns_struct_value) struct_value.deinit(std.testing.allocator);
    struct_value.fields[0] = .{
        .name = try std.testing.allocator.dupe(u8, "magic"),
        .value = value_mod.Value.typedInteger(0x5a4d, u16_type),
    };
    struct_value.fields[1] = .{
        .name = try std.testing.allocator.dupe(u8, "lfanew"),
        .value = value_mod.Value.typedInteger(0x80, u32_type),
    };
    _ = try module.defineValue("hdr", .{ .@"struct" = struct_value }, .@"const", source.unknown_span);
    owns_struct_value = false;

    var ctx: EvalContext = .{ .module = &module };
    var expression = try parseOwned(std.testing.allocator, "hdr.magic");
    defer expression.deinit(std.testing.allocator);

    var result = try evaluateValue(std.testing.allocator, &expression, &ctx);
    defer result.deinit(std.testing.allocator);
    const integer = try result.expectIntegerValue();
    try std.testing.expectEqual(@as(u64, 0x5a4d), integer.value);
    try std.testing.expectEqual(u16_type.index, integer.type_id.?.index);
}

test "expression rejects empty struct field access" {
    try std.testing.expectError(error.InvalidToken, parseOwned(std.testing.allocator, "hdr..magic"));
}

test "expression packs stored struct values into bytes" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    const u16_type = try module.getOrAddIntType("u16", 16, .unsigned);
    const u32_type = try module.getOrAddIntType("u32", 32, .unsigned);
    const header = try module.addStructType("Header", &.{
        .{ .name = "magic", .ty = u16_type },
        .{ .name = "lfanew", .ty = u32_type },
    }, .@"packed");
    try module.registerTypeName("Header", header);

    var struct_value: value_mod.StructValue = .{
        .type_id = header,
        .fields = try std.testing.allocator.alloc(value_mod.StructFieldValue, 2),
    };
    var owns_struct_value = true;
    errdefer if (owns_struct_value) struct_value.deinit(std.testing.allocator);
    struct_value.fields[0] = .{
        .name = try std.testing.allocator.dupe(u8, "magic"),
        .value = value_mod.Value.typedInteger(0x5a4d, u16_type),
    };
    struct_value.fields[1] = .{
        .name = try std.testing.allocator.dupe(u8, "lfanew"),
        .value = value_mod.Value.typedInteger(0x80, u32_type),
    };
    _ = try module.defineValue("hdr", .{ .@"struct" = struct_value }, .@"const", source.unknown_span);
    owns_struct_value = false;

    var ctx: EvalContext = .{ .module = &module };

    var pack_expression = try parseOwned(std.testing.allocator, "pack(hdr)");
    defer pack_expression.deinit(std.testing.allocator);
    var packed_value = try evaluateValue(std.testing.allocator, &pack_expression, &ctx);
    defer packed_value.deinit(std.testing.allocator);
    try std.testing.expectEqualSlices(u8, &.{ 0x4d, 0x5a, 0x80, 0x00, 0x00, 0x00 }, try packed_value.expectBytes());

    var length_expression = try parseOwned(std.testing.allocator, "lengthof(pack(hdr))");
    defer length_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(u64, 6), try evaluateInteger(&length_expression, &ctx));
}

test "expression evaluates boolean comparison and logical operators" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "true && !false && 1 < 2 && 3 == 3");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectEqual(true, try evaluateBoolean(&expression, &ctx));
}

test "expression logical operators short circuit" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var and_expression = try parseOwned(std.testing.allocator, "false && (1 / 0 == 0)");
    defer and_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(false, try evaluateBoolean(&and_expression, &ctx));

    var or_expression = try parseOwned(std.testing.allocator, "true || (1 / 0 == 0)");
    defer or_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, try evaluateBoolean(&or_expression, &ctx));
}

test "expression compares strings bytes and type values" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    const u32_type = try module.getOrAddIntType("u32", 32, .unsigned);
    try module.registerTypeName("WordAlias", u32_type);
    var ctx: EvalContext = .{ .module = &module };

    var string_expression = try parseOwned(std.testing.allocator, "\"a\" == \"a\"");
    defer string_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, try evaluateBoolean(&string_expression, &ctx));

    var bytes_expression = try parseOwned(std.testing.allocator, "b\"AB\" == b\"AB\"");
    defer bytes_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, try evaluateBoolean(&bytes_expression, &ctx));

    var type_expression = try parseOwned(std.testing.allocator, "u32 == WordAlias");
    defer type_expression.deinit(std.testing.allocator);
    try std.testing.expectEqual(true, try evaluateBoolean(&type_expression, &ctx));
}

test "expression rejects boolean as integer" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    var ctx: EvalContext = .{ .module = &module };

    var expression = try parseOwned(std.testing.allocator, "true");
    defer expression.deinit(std.testing.allocator);

    try std.testing.expectError(error.TypeMismatch, evaluateInteger(&expression, &ctx));
}
