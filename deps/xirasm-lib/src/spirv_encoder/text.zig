const std = @import("std");

const tables = @import("text_tables.zig");
const types = @import("types.zig");
const module_mod = @import("module.zig");

const Allocator = std.mem.Allocator;

pub const Word = types.Word;

pub const ParseError = Allocator.Error || error{
    EmptyOrComment,
    UnknownOpcode,
    UnknownOperand,
    ExpectedId,
    ExpectedEquals,
    ExpectedOperand,
    TooManyOperands,
    InvalidInteger,
    InvalidString,
    InstructionTooLong,
    InvalidHeaderBound,
    IdBoundOverflow,
};

pub const ParseOptions = struct {};

pub const SourceOptions = struct {
    version: module_mod.Version = .v1_6,
    generator: Word = module_mod.default_generator,
    schema: Word = module_mod.default_schema,
};

pub const ScalarType = union(enum) {
    int: struct {
        width: u32,
        signed: bool,
    },
    float: struct {
        width: u32,
    },
};

pub const ParseContext = struct {
    scalar_types: std.AutoHashMapUnmanaged(Word, ScalarType) = .empty,

    pub fn deinit(self: *ParseContext, allocator: Allocator) void {
        self.scalar_types.deinit(allocator);
        self.* = undefined;
    }

    pub fn reset(self: *ParseContext) void {
        self.scalar_types.clearRetainingCapacity();
    }
};

pub const LineResult = struct {
    words: []Word,
    max_id: Word = 0,

    pub fn deinit(self: *LineResult, allocator: Allocator) void {
        allocator.free(self.words);
        self.* = undefined;
    }
};

pub const SourceResult = struct {
    words: []Word,

    pub fn deinit(self: *SourceResult, allocator: Allocator) void {
        allocator.free(self.words);
        self.* = undefined;
    }

    pub fn toOwnedBytes(self: SourceResult, allocator: Allocator) ![]u8 {
        return try allocator.dupe(u8, std.mem.sliceAsBytes(self.words));
    }
};

pub fn parseSource(allocator: Allocator, source: []const u8, options: SourceOptions) ParseError!SourceResult {
    var words: std.ArrayListUnmanaged(Word) = .empty;
    errdefer words.deinit(allocator);

    try words.ensureUnusedCapacity(allocator, 5);
    words.appendAssumeCapacity(module_mod.magic_number);
    words.appendAssumeCapacity(options.version.toWord());
    words.appendAssumeCapacity(options.generator);
    words.appendAssumeCapacity(1);
    words.appendAssumeCapacity(options.schema);

    var context: ParseContext = .{};
    defer context.deinit(allocator);

    var max_id: Word = 0;
    var lines = std.mem.splitScalar(u8, source, '\n');
    while (lines.next()) |line| {
        var parsed = parseLineWithContext(allocator, &context, line, .{}) catch |err| switch (err) {
            error.EmptyOrComment => continue,
            else => |leftover| return leftover,
        };
        defer parsed.deinit(allocator);

        if (parsed.max_id > max_id) max_id = parsed.max_id;
        try words.appendSlice(allocator, parsed.words);
    }

    const bound = std.math.add(Word, max_id, 1) catch return error.IdBoundOverflow;
    words.items[3] = @max(bound, 1);

    return .{ .words = try words.toOwnedSlice(allocator) };
}

pub fn parseSourceToOwnedWords(allocator: Allocator, source: []const u8, options: SourceOptions) ParseError![]Word {
    var parsed = try parseSource(allocator, source, options);
    defer parsed.deinit(allocator);
    return try allocator.dupe(Word, parsed.words);
}

pub fn parseSourceToOwnedBytes(allocator: Allocator, source: []const u8, options: SourceOptions) ParseError![]u8 {
    var parsed = try parseSource(allocator, source, options);
    defer parsed.deinit(allocator);
    return try parsed.toOwnedBytes(allocator);
}

pub fn parseLine(allocator: Allocator, line: []const u8, _: ParseOptions) ParseError!LineResult {
    return parseLineWithContext(allocator, null, line, .{});
}

pub fn parseLineWithContext(
    allocator: Allocator,
    context: ?*ParseContext,
    line: []const u8,
    _: ParseOptions,
) ParseError!LineResult {
    var tokenizer = Tokenizer.init(line);
    const first_token = tokenizer.next() orelse return error.EmptyOrComment;

    var opcode_token = first_token;
    var result_id: ?Word = null;
    if (isIdToken(first_token)) {
        result_id = try parseId(first_token);
        const equals = tokenizer.next() orelse return error.ExpectedEquals;
        if (!std.mem.eql(u8, equals, "=")) return error.ExpectedEquals;
        opcode_token = tokenizer.next() orelse return error.UnknownOpcode;
    }

    const opcode = tables.lookupOpcode(opcode_token) orelse return error.UnknownOpcode;
    var operands: std.ArrayListUnmanaged(Word) = .empty;
    defer operands.deinit(allocator);

    var max_id = result_id orelse 0;
    var result_type_id: ?Word = null;
    var operand_index: usize = 0;
    while (operand_index < opcode.operands.len) : (operand_index += 1) {
        const operand = opcode.operands[operand_index];
        switch (operand.quantifier) {
            .one => {
                if (result_id) |id| {
                    if (operand.kind == .id_result) {
                        try appendWord(allocator, &operands, id);
                        result_id = null;
                        continue;
                    }
                }

                try appendOperand(allocator, context, &operands, &tokenizer, operand.kind, result_type_id, &max_id);
                if (operand.kind == .id_result_type and operands.items.len != 0) {
                    result_type_id = operands.items[operands.items.len - 1];
                }
            },
            .optional => {
                if (tokenizer.peek() == null) continue;
                try appendOperand(allocator, context, &operands, &tokenizer, operand.kind, result_type_id, &max_id);
            },
            .variable => {
                while (tokenizer.peek() != null) {
                    try appendOperand(allocator, context, &operands, &tokenizer, operand.kind, result_type_id, &max_id);
                }
            },
        }
    }

    if (result_id != null) return error.ExpectedOperand;
    if (tokenizer.next() != null) return error.TooManyOperands;

    const word_count = operands.items.len + 1;
    if (word_count > std.math.maxInt(u16)) return error.InstructionTooLong;

    var words: std.ArrayListUnmanaged(Word) = .empty;
    errdefer words.deinit(allocator);
    try words.ensureTotalCapacity(allocator, word_count);
    const count: Word = @intCast(word_count);
    words.appendAssumeCapacity((count << 16) | @as(Word, opcode.opcode));
    words.appendSliceAssumeCapacity(operands.items);

    const owned_words = try words.toOwnedSlice(allocator);
    errdefer allocator.free(owned_words);

    if (context) |ctx| {
        try recordParsedFacts(allocator, ctx, opcode.opcode, owned_words);
    }

    return .{
        .words = owned_words,
        .max_id = max_id,
    };
}

fn appendOperand(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    tokenizer: *Tokenizer,
    kind: tables.OperandKind,
    result_type_id: ?Word,
    max_id: *Word,
) ParseError!void {
    switch (kind) {
        .id_result,
        .id_result_type,
        .id_ref,
        .id_scope,
        .id_memory_semantics,
        => {
            const id = try parseId(tokenizer.next() orelse return error.ExpectedOperand);
            if (id > max_id.*) max_id.* = id;
            try appendWord(allocator, out, id);
        },
        .literal_string => {
            const raw = tokenizer.next() orelse return error.ExpectedOperand;
            try appendString(allocator, out, raw);
        },
        .literal_integer => {
            try appendWord(allocator, out, try parseWord(tokenizer.next() orelse return error.ExpectedOperand));
        },
        .literal_float => {
            try appendFloat32(allocator, out, tokenizer.next() orelse return error.ExpectedOperand);
        },
        .literal_context_dependent_number => {
            try appendContextDependentNumber(
                allocator,
                context,
                out,
                tokenizer.next() orelse return error.ExpectedOperand,
                result_type_id,
            );
        },
        .literal_ext_inst_integer => {
            try appendExtInst(allocator, context, out, tokenizer, max_id);
        },
        .literal_spec_constant_op_integer => {
            try appendSpecConstantOp(allocator, context, out, tokenizer, result_type_id, max_id);
        },
        .pair_literal_integer_id_ref => {
            try appendWord(allocator, out, try parseWord(tokenizer.next() orelse return error.ExpectedOperand));
            const id = try parseId(tokenizer.next() orelse return error.ExpectedOperand);
            if (id > max_id.*) max_id.* = id;
            try appendWord(allocator, out, id);
        },
        .pair_id_ref_literal_integer => {
            const id = try parseId(tokenizer.next() orelse return error.ExpectedOperand);
            if (id > max_id.*) max_id.* = id;
            try appendWord(allocator, out, id);
            try appendWord(allocator, out, try parseWord(tokenizer.next() orelse return error.ExpectedOperand));
        },
        .pair_id_ref_id_ref => {
            const first = try parseId(tokenizer.next() orelse return error.ExpectedOperand);
            const second = try parseId(tokenizer.next() orelse return error.ExpectedOperand);
            if (first > max_id.*) max_id.* = first;
            if (second > max_id.*) max_id.* = second;
            try appendWord(allocator, out, first);
            try appendWord(allocator, out, second);
        },
        else => switch (tables.operandCategory(kind)) {
            .value_enum => try appendValueEnum(allocator, context, out, tokenizer, kind, result_type_id, max_id),
            .bit_enum => try appendBitEnum(allocator, context, out, tokenizer, kind, result_type_id, max_id),
            else => return error.UnknownOperand,
        },
    }
}

fn appendExtInst(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    tokenizer: *Tokenizer,
    max_id: *Word,
) ParseError!void {
    const token = tokenizer.next() orelse return error.ExpectedOperand;
    if (tables.lookupGlslStd450ExtInst(token)) |inst| {
        try appendWord(allocator, out, inst.value);
        for (inst.operands) |operand| {
            try appendOperand(allocator, context, out, tokenizer, operand.kind, null, max_id);
        }
        return;
    }
    try appendWord(allocator, out, try parseWord(token));
}

fn appendSpecConstantOp(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    tokenizer: *Tokenizer,
    result_type_id: ?Word,
    max_id: *Word,
) ParseError!void {
    const token = tokenizer.next() orelse return error.ExpectedOperand;
    if (tables.lookupSpecConstantOpcode(token)) |opcode| {
        try appendWord(allocator, out, opcode.opcode);
        for (opcode.operands) |operand| {
            switch (operand.quantifier) {
                .one => try appendOperand(allocator, context, out, tokenizer, operand.kind, result_type_id, max_id),
                .optional => {
                    if (tokenizer.peek() != null) {
                        try appendOperand(allocator, context, out, tokenizer, operand.kind, result_type_id, max_id);
                    }
                },
                .variable => {
                    while (tokenizer.peek() != null) {
                        try appendOperand(allocator, context, out, tokenizer, operand.kind, result_type_id, max_id);
                    }
                },
            }
        }
        return;
    }
    try appendWord(allocator, out, try parseWord(token));
}

fn appendContextDependentNumber(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    token: []const u8,
    result_type_id: ?Word,
) ParseError!void {
    if (context) |ctx| {
        if (result_type_id) |type_id| {
            if (ctx.scalar_types.get(type_id)) |scalar| {
                return appendTypedContextDependentNumber(allocator, out, token, scalar);
            }
        }
    }
    if (isFloatToken(token)) {
        const value = std.fmt.parseFloat(f32, token) catch return error.InvalidInteger;
        try appendWord(allocator, out, @bitCast(value));
        return;
    }

    try appendWord(allocator, out, try parseWord(token));
}

fn appendTypedContextDependentNumber(
    allocator: Allocator,
    out: *std.ArrayListUnmanaged(Word),
    token: []const u8,
    scalar: ScalarType,
) ParseError!void {
    switch (scalar) {
        .float => |info| switch (info.width) {
            32 => {
                const value = std.fmt.parseFloat(f32, token) catch return error.InvalidInteger;
                try appendWord(allocator, out, @bitCast(value));
            },
            64 => {
                const value = std.fmt.parseFloat(f64, token) catch return error.InvalidInteger;
                const raw: u64 = @bitCast(value);
                try appendWord(allocator, out, @truncate(raw));
                try appendWord(allocator, out, @truncate(raw >> 32));
            },
            else => return error.InvalidInteger,
        },
        .int => |info| switch (info.width) {
            32 => {
                if (info.signed) {
                    try appendWord(allocator, out, try parseSignedWord(token));
                } else {
                    try appendWord(allocator, out, try parseWord(token));
                }
            },
            else => return error.InvalidInteger,
        },
    }
}

fn appendValueEnum(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    tokenizer: *Tokenizer,
    kind: tables.OperandKind,
    result_type_id: ?Word,
    max_id: *Word,
) ParseError!void {
    const token = tokenizer.next() orelse return error.ExpectedOperand;
    const enumerant = tables.lookupEnumerant(kind, token) orelse return error.UnknownOperand;
    try appendWord(allocator, out, enumerant.value);
    for (enumerant.parameters) |parameter_kind| {
        try appendOperand(allocator, context, out, tokenizer, parameter_kind, result_type_id, max_id);
    }
}

fn appendBitEnum(
    allocator: Allocator,
    context: ?*ParseContext,
    out: *std.ArrayListUnmanaged(Word),
    tokenizer: *Tokenizer,
    kind: tables.OperandKind,
    result_type_id: ?Word,
    max_id: *Word,
) ParseError!void {
    const token = tokenizer.next() orelse return error.ExpectedOperand;
    if (std.mem.indexOfScalar(u8, token, '|') == null) {
        if (tables.lookupEnumerant(kind, token)) |enumerant| {
            try appendWord(allocator, out, enumerant.value);
            for (enumerant.parameters) |parameter_kind| {
                try appendOperand(allocator, context, out, tokenizer, parameter_kind, result_type_id, max_id);
            }
            return;
        }
        try appendWord(allocator, out, try parseWord(token));
        return;
    }

    var mask: Word = 0;
    var parameter_kinds: std.ArrayListUnmanaged([]const tables.OperandKind) = .empty;
    defer parameter_kinds.deinit(allocator);

    var terms = std.mem.splitScalar(u8, token, '|');
    while (terms.next()) |term| {
        if (term.len == 0) return error.UnknownOperand;
        const enumerant = tables.lookupEnumerant(kind, term) orelse return error.UnknownOperand;
        mask |= enumerant.value;
        try parameter_kinds.append(allocator, enumerant.parameters);
    }

    try appendWord(allocator, out, mask);
    for (parameter_kinds.items) |parameters| {
        for (parameters) |parameter_kind| {
            try appendOperand(allocator, context, out, tokenizer, parameter_kind, result_type_id, max_id);
        }
    }
}

fn appendWord(allocator: Allocator, out: *std.ArrayListUnmanaged(Word), word: Word) Allocator.Error!void {
    try out.append(allocator, word);
}

fn appendString(allocator: Allocator, out: *std.ArrayListUnmanaged(Word), raw: []const u8) ParseError!void {
    if (raw.len < 2 or raw[0] != '"' or raw[raw.len - 1] != '"') return error.InvalidString;
    var payload: std.ArrayListUnmanaged(u8) = .empty;
    defer payload.deinit(allocator);
    try payload.ensureTotalCapacity(allocator, raw.len - 2);

    var index: usize = 1;
    var escaping = false;
    while (index < raw.len - 1) : (index += 1) {
        const ch = raw[index];
        if (ch == '\\' and !escaping) {
            escaping = true;
            continue;
        }
        payload.appendAssumeCapacity(ch);
        escaping = false;
    }
    if (escaping) return error.InvalidString;

    const total_bytes = payload.items.len + 1;
    const word_count = (total_bytes + @sizeOf(Word) - 1) / @sizeOf(Word);
    try out.ensureUnusedCapacity(allocator, word_count);

    var byte_index: usize = 0;
    while (byte_index < word_count * @sizeOf(Word)) : (byte_index += @sizeOf(Word)) {
        var word: Word = 0;
        var lane: usize = 0;
        while (lane < @sizeOf(Word)) : (lane += 1) {
            const absolute = byte_index + lane;
            const byte: u8 = if (absolute < payload.items.len) payload.items[absolute] else 0;
            word |= @as(Word, byte) << @as(std.math.Log2Int(Word), @intCast(lane * @bitSizeOf(u8)));
        }
        out.appendAssumeCapacity(word);
    }
}

fn appendFloat32(allocator: Allocator, out: *std.ArrayListUnmanaged(Word), token: []const u8) ParseError!void {
    const value = std.fmt.parseFloat(f32, token) catch return error.InvalidInteger;
    try appendWord(allocator, out, @bitCast(value));
}

fn parseId(token: []const u8) ParseError!Word {
    if (!isIdToken(token)) return error.ExpectedId;
    return parseWord(token[1..]);
}

fn parseWord(token: []const u8) ParseError!Word {
    if (token.len == 0) return error.InvalidInteger;
    const base: u8 = if (std.mem.startsWith(u8, token, "0x") or std.mem.startsWith(u8, token, "0X")) 16 else 10;
    const digits = if (base == 16) token[2..] else token;
    if (digits.len == 0) return error.InvalidInteger;
    const value = std.fmt.parseUnsigned(u64, digits, base) catch return error.InvalidInteger;
    return std.math.cast(Word, value) orelse error.InvalidInteger;
}

fn parseSignedWord(token: []const u8) ParseError!Word {
    if (token.len == 0) return error.InvalidInteger;
    const value = std.fmt.parseInt(i64, token, 10) catch return error.InvalidInteger;
    const narrowed = std.math.cast(i32, value) orelse return error.InvalidInteger;
    return @bitCast(narrowed);
}

fn isFloatToken(token: []const u8) bool {
    return std.mem.indexOfScalar(u8, token, '.') != null or
        std.mem.indexOfScalar(u8, token, 'p') != null or
        std.mem.indexOfScalar(u8, token, 'P') != null;
}

fn isIdToken(token: []const u8) bool {
    return token.len > 1 and token[0] == '%';
}

const Tokenizer = struct {
    text: []const u8,
    index: usize = 0,
    cached: ?[]const u8 = null,

    fn init(text: []const u8) Tokenizer {
        return .{ .text = text };
    }

    fn peek(self: *Tokenizer) ?[]const u8 {
        if (self.cached == null) self.cached = self.nextRaw();
        return self.cached;
    }

    fn next(self: *Tokenizer) ?[]const u8 {
        if (self.cached) |token| {
            self.cached = null;
            return token;
        }
        return self.nextRaw();
    }

    fn nextRaw(self: *Tokenizer) ?[]const u8 {
        self.skipSpace();
        if (self.index >= self.text.len) return null;

        const start = self.index;
        if (self.text[self.index] == '"') {
            self.index += 1;
            var escaping = false;
            while (self.index < self.text.len) : (self.index += 1) {
                const ch = self.text[self.index];
                if (ch == '\\' and !escaping) {
                    escaping = true;
                    continue;
                }
                if (ch == '"' and !escaping) {
                    self.index += 1;
                    return self.text[start..self.index];
                }
                escaping = false;
            }
            self.index = self.text.len;
            return self.text[start..self.index];
        }

        while (self.index < self.text.len and !isSpace(self.text[self.index])) : (self.index += 1) {}
        return self.text[start..self.index];
    }

    fn skipSpace(self: *Tokenizer) void {
        while (self.index < self.text.len and isSpace(self.text[self.index])) : (self.index += 1) {}
    }
};

fn isSpace(ch: u8) bool {
    return ch == ' ' or ch == '\t' or ch == '\r' or ch == '\n';
}

fn recordParsedFacts(
    allocator: Allocator,
    context: *ParseContext,
    opcode: u16,
    words: []const Word,
) Allocator.Error!void {
    switch (opcode) {
        21 => {
            if (words.len < 4) return;
            try context.scalar_types.put(allocator, words[1], .{ .int = .{
                .width = words[2],
                .signed = words[3] != 0,
            } });
        },
        22 => {
            if (words.len < 3) return;
            try context.scalar_types.put(allocator, words[1], .{ .float = .{
                .width = words[2],
            } });
        },
        else => {},
    }
}

test "parse raw-id capability and memory model" {
    const testing = std.testing;

    var capability = try parseLine(testing.allocator, "OpCapability Shader", .{});
    defer capability.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00020011, 1 }, capability.words);

    var memory_model = try parseLine(testing.allocator, "OpMemoryModel Logical GLSL450", .{});
    defer memory_model.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x0003000e, 0, 1 }, memory_model.words);
}

test "parse raw-id result instructions" {
    const testing = std.testing;

    var void_type = try parseLine(testing.allocator, "%1 = OpTypeVoid", .{});
    defer void_type.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00020013, 1 }, void_type.words);
    try testing.expectEqual(@as(Word, 1), void_type.max_id);

    var fn_type = try parseLine(testing.allocator, "%2 = OpTypeFunction %1", .{});
    defer fn_type.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00030021, 2, 1 }, fn_type.words);
    try testing.expectEqual(@as(Word, 2), fn_type.max_id);

    var function = try parseLine(testing.allocator, "%3 = OpFunction %1 None %2", .{});
    defer function.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00050036, 1, 3, 0, 2 }, function.words);
    try testing.expectEqual(@as(Word, 3), function.max_id);
}

test "parse strings and variable id operands" {
    const testing = std.testing;

    var entry = try parseLine(testing.allocator, "OpEntryPoint GLCompute %3 \"main\" %4 %5", .{});
    defer entry.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x0007000f, 5, 3, 0x6e69616d, 0, 4, 5 }, entry.words);
    try testing.expectEqual(@as(Word, 5), entry.max_id);

    var escaped = try parseLine(testing.allocator, "OpName %1 \"a\\\"b\\\\c\"", .{});
    defer escaped.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00040005, 1, 0x5c622261, 0x63 }, escaped.words);
}

test "parse value enum parameters and bit enum parameters" {
    const testing = std.testing;

    var mode = try parseLine(testing.allocator, "OpExecutionMode %3 LocalSize 1 2 3", .{});
    defer mode.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00060010, 3, 17, 1, 2, 3 }, mode.words);

    var store = try parseLine(testing.allocator, "OpStore %7 %8 Aligned 4", .{});
    defer store.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x0005003e, 7, 8, 2, 4 }, store.words);

    var volatile_aligned = try parseLine(testing.allocator, "OpStore %7 %8 Volatile|Aligned 4", .{});
    defer volatile_aligned.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x0005003e, 7, 8, 3, 4 }, volatile_aligned.words);

    var literal_float = try parseLine(testing.allocator, "OpDecorate %1 FPMaxErrorDecorationINTEL 1.5", .{});
    defer literal_float.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00040047, 1, 6170, 0x3fc00000 }, literal_float.words);
}

test "parse extended instruction and spec constant opcode names" {
    const testing = std.testing;

    var ext_inst = try parseLine(testing.allocator, "%12 = OpExtInst %15 %1 Log2 %11", .{});
    defer ext_inst.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x0006000c, 15, 12, 1, 30, 11 }, ext_inst.words);

    var spec_op = try parseLine(testing.allocator, "%8 = OpSpecConstantOp %4 CompositeExtract %7 2", .{});
    defer spec_op.deinit(testing.allocator);
    try testing.expectEqualSlices(Word, &.{ 0x00060034, 4, 8, 81, 7, 2 }, spec_op.words);
}

test "parse source emits full module in source order" {
    const source =
        \\OpCapability Shader
        \\OpMemoryModel Logical GLSL450
        \\%1 = OpTypeVoid
        \\OpName %1 "main"
    ;

    var parsed = try parseSource(std.testing.allocator, source, .{});
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(Word, &.{
        module_mod.magic_number,
        module_mod.Version.v1_6.toWord(),
        module_mod.default_generator,
        2,
        module_mod.default_schema,
        0x00020011,
        1,
        0x0003000e,
        0,
        1,
        0x00020013,
        1,
        0x00040005,
        1,
        0x6e69616d,
        0,
    }, parsed.words);
}

fn allocationFailureParseProbe(allocator: Allocator) !void {
    var context: ParseContext = .{};
    defer context.deinit(allocator);

    var int_type = try parseLineWithContext(allocator, &context, "%1 = OpTypeInt 32 1", .{});
    defer int_type.deinit(allocator);

    var constant = try parseLineWithContext(allocator, &context, "%2 = OpConstant %1 -7", .{});
    defer constant.deinit(allocator);

    var name = try parseLineWithContext(allocator, &context, "OpName %2 \"a\\\"b\\\\c\"", .{});
    defer name.deinit(allocator);
}

test "parse line handles allocation failures without leaks" {
    try std.testing.checkAllAllocationFailures(std.testing.allocator, allocationFailureParseProbe, .{});
}
