const std = @import("std");

const api = @import("api.zig");
const types = @import("types.zig");

pub const SourceError = types.EncodeError || error{
    InvalidOperand,
    OutOfMemory,
    TooManyOperands,
    UnsupportedOperandSyntax,
};

const MemoryOperandOrder = enum {
    base_then_offset,
    offset_then_base,
};

pub const ExpressionResolver = struct {
    context: *anyopaque,
    resolveFn: *const fn (context: *anyopaque, text: []const u8) SourceError!?i64,

    pub fn resolve(self: ExpressionResolver, text: []const u8) SourceError!?i64 {
        return self.resolveFn(self.context, text);
    }
};

pub const ParsedInstruction = struct {
    mnemonic: []const u8,
    storage: [16]types.Operand = undefined,
    len: usize = 0,

    pub fn operands(self: *const ParsedInstruction) []const types.Operand {
        return self.storage[0..self.len];
    }
};

const OperandContext = struct {
    semantic: ?types.Semantic,
    memory_order: MemoryOperandOrder,
    mnemonic: []const u8,
};

pub fn parseInstructionText(line: []const u8, resolver: ?ExpressionResolver) SourceError!ParsedInstruction {
    const stripped = stripCommentAndWhitespace(line);
    if (stripped.len == 0) return error.UnsupportedInstruction;

    const split = firstWhitespace(stripped);
    const raw_mnemonic = if (split) |space_pos| stripped[0..space_pos] else stripped;
    if (raw_mnemonic.len == 0) return error.UnsupportedInstruction;
    const mnemonic_info = parseMnemonic(raw_mnemonic);

    var parsed: ParsedInstruction = .{ .mnemonic = mnemonic_info.base };
    if (split) |space_pos| {
        const args = std.mem.trim(u8, stripped[space_pos + 1 ..], " \t\r\n");
        const spec = (api.instructionByMnemonic(mnemonic_info.base) catch null) orelse
            (api.instructionByMnemonicAnyXLen(mnemonic_info.base) catch null);
        const context = OperandContext{
            .semantic = if (spec) |active| active.semantic else null,
            .memory_order = memoryOperandOrderForSpec(spec),
            .mnemonic = mnemonic_info.base,
        };
        try parseOperandList(args, resolver, context, &parsed);
        normalizeParsedOperandOrder(context, &parsed);
    }
    try appendOrderingOperands(mnemonic_info.ordering, &parsed);
    try appendSuffixImmediate(mnemonic_info.suffix_immediate, &parsed);
    return parsed;
}

pub fn encodeInstructionText(line: []const u8, xlen: u8, resolver: ?ExpressionResolver) SourceError!types.EncodedInstruction {
    const parsed = try parseInstructionText(line, resolver);
    return api.encodeMnemonic(parsed.mnemonic, xlen, parsed.operands());
}

fn parseOperandList(
    args: []const u8,
    resolver: ?ExpressionResolver,
    context: OperandContext,
    parsed: *ParsedInstruction,
) SourceError!void {
    if (context.semantic == .rd_rs1_zimm11 or context.semantic == .rd_zimm5_zimm10) {
        return parseVSetOperandList(args, resolver, context, parsed);
    }

    var start: usize = 0;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    var in_char = false;

    for (args, 0..) |ch, i| {
        switch (ch) {
            '(' => paren_depth += 1,
            ')' => paren_depth = paren_depth -| 1,
            '[' => bracket_depth += 1,
            ']' => bracket_depth = bracket_depth -| 1,
            '{' => brace_depth += 1,
            '}' => brace_depth = brace_depth -| 1,
            '\'' => in_char = !in_char,
            ',' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0 and !in_char) {
                    try appendOperand(args[start..i], resolver, context, parsed);
                    start = i + 1;
                }
            },
            else => {},
        }
    }
    try appendOperand(args[start..], resolver, context, parsed);
    try appendImplicitVectorNf(context, parsed);
    try appendImplicitVectorMask(context, parsed);
}

fn parseVSetOperandList(
    args: []const u8,
    resolver: ?ExpressionResolver,
    context: OperandContext,
    parsed: *ParsedInstruction,
) SourceError!void {
    var parts: [6][]const u8 = undefined;
    var len: usize = 0;
    var iter = std.mem.splitScalar(u8, args, ',');
    while (iter.next()) |part| {
        if (len >= parts.len) return error.TooManyOperands;
        parts[len] = std.mem.trim(u8, part, " \t\r\n");
        len += 1;
    }

    if (len != 3 and len != 6) return error.OperandCountMismatch;
    try appendRegisterOperand(parts[0], parsed);
    switch (context.semantic orelse return error.UnsupportedOperandSyntax) {
        .rd_rs1_zimm11 => try appendRegisterOperand(parts[1], parsed),
        .rd_zimm5_zimm10 => try appendImmediateOperand(parts[1], resolver, parsed),
        else => return error.UnsupportedOperandSyntax,
    }
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .imm = if (len == 6)
        try parseVTypeParts(parts[2], parts[3], parts[4], parts[5])
    else
        parseVType(parts[2]) catch |err| switch (err) {
            error.UnsupportedOperandSyntax => try parseImmediate(parts[2], resolver),
            else => return err,
        } };
    parsed.len += 1;
}

fn appendRegisterOperand(raw: []const u8, parsed: *ParsedInstruction) SourceError!void {
    const token = std.mem.trim(u8, raw, " \t\r\n");
    if (token.len == 0) return error.InvalidOperand;
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .reg = api.parseRegister(token) catch return error.InvalidOperand };
    parsed.len += 1;
}

fn appendImmediateOperand(raw: []const u8, resolver: ?ExpressionResolver, parsed: *ParsedInstruction) SourceError!void {
    const token = std.mem.trim(u8, raw, " \t\r\n");
    if (token.len == 0) return error.InvalidOperand;
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .imm = try parseImmediate(token, resolver) };
    parsed.len += 1;
}

fn appendOperand(
    raw: []const u8,
    resolver: ?ExpressionResolver,
    context: OperandContext,
    parsed: *ParsedInstruction,
) SourceError!void {
    const token = std.mem.trim(u8, raw, " \t\r\n");
    if (token.len == 0) return error.InvalidOperand;
    if (isExplicitVectorMaskPosition(context, parsed.len) and !isVectorMaskOperand(token)) {
        return error.InvalidOperand;
    }
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    const projected = try parseOperand(token, resolver, context);
    switch (projected) {
        .one => |operand| {
            parsed.storage[parsed.len] = operand;
            parsed.len += 1;
        },
        .two => |operands| {
            if (parsed.len + 2 > parsed.storage.len) return error.TooManyOperands;
            parsed.storage[parsed.len] = operands[0];
            parsed.storage[parsed.len + 1] = operands[1];
            parsed.len += 2;
        },
    }
}

const ProjectedOperand = union(enum) {
    one: types.Operand,
    two: [2]types.Operand,
};

fn parseOperand(token: []const u8, resolver: ?ExpressionResolver, context: OperandContext) SourceError!ProjectedOperand {
    if (context.semantic) |semantic| {
        if (semantic == .amo or semantic == .lr or semantic == .sc) {
            if (parseAtomicAddress(token)) |operand| {
                return .{ .one = operand };
            } else |err| switch (err) {
                error.UnsupportedOperandSyntax => {},
                else => return err,
            }
        }
        if (isVectorMemorySemantic(semantic)) {
            if (parseVectorMemoryBase(token)) |operand| {
                return .{ .one = operand };
            } else |err| switch (err) {
                error.UnsupportedOperandSyntax => {},
                else => return err,
            }
        }
    }

    if (parseLoadStoreAddress(token, resolver, context.memory_order)) |operands| {
        return .{ .two = operands };
    } else |err| switch (err) {
        error.UnsupportedOperandSyntax => {},
        else => return err,
    }

    if (parseSpecialOperand(token, resolver, context)) |operand| {
        return .{ .one = operand };
    } else |err| switch (err) {
        error.UnsupportedOperandSyntax => {},
        else => return err,
    }

    if (parseRegisterList(token)) |encoded| {
        return .{ .one = .{ .imm = encoded } };
    } else |_| {}

    if (api.parseRegister(token)) |reg| {
        return .{ .one = .{ .reg = reg } };
    } else |_| {}

    if (parseFenceMask(token)) |mask| {
        return .{ .one = .{ .imm = mask } };
    } else |_| {}

    if (parseRoundingMode(token)) |rm| {
        return .{ .one = .{ .imm = rm } };
    } else |_| {}

    if (parseCsrName(token)) |csr| {
        return .{ .one = .{ .imm = csr } };
    } else |_| {}

    return .{ .one = .{ .imm = try parseImmediate(token, resolver) } };
}

fn parseAtomicAddress(token: []const u8) SourceError!types.Operand {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed.len < 3 or trimmed[0] != '(' or trimmed[trimmed.len - 1] != ')') {
        return error.UnsupportedOperandSyntax;
    }
    const base_text = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t\r\n");
    if (base_text.len == 0) return error.UnsupportedOperandSyntax;
    const base = api.parseRegister(base_text) catch return error.UnsupportedOperandSyntax;
    return .{ .reg = base };
}

fn isVectorMemorySemantic(semantic: types.Semantic) bool {
    return switch (semantic) {
        .vd_rs1_nf_vm,
        .vs3_rs1_nf_vm,
        .vd_rs1_vs2_nf_vm,
        .vs3_rs1_vs2_nf_vm,
        .vd_rs1_rs2_nf_vm,
        .vs3_rs1_rs2_nf_vm,
        .vs3_rs1,
        => true,
        else => false,
    };
}

fn hasVectorNfOperand(semantic: types.Semantic) bool {
    return switch (semantic) {
        .vd_rs1_nf_vm,
        .vs3_rs1_nf_vm,
        .vd_rs1_vs2_nf_vm,
        .vs3_rs1_vs2_nf_vm,
        .vd_rs1_rs2_nf_vm,
        .vs3_rs1_rs2_nf_vm,
        => true,
        else => false,
    };
}

fn parseVectorMemoryBase(token: []const u8) SourceError!types.Operand {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (!std.mem.endsWith(u8, trimmed, ")")) return error.UnsupportedOperandSyntax;
    const open = std.mem.lastIndexOfScalar(u8, trimmed, '(') orelse return error.UnsupportedOperandSyntax;
    const offset_text = std.mem.trim(u8, trimmed[0..open], " \t\r\n");
    if (offset_text.len != 0) return error.InvalidOperand;
    const base_text = std.mem.trim(u8, trimmed[open + 1 .. trimmed.len - 1], " \t\r\n");
    if (base_text.len == 0) return error.InvalidOperand;
    return .{ .reg = api.parseRegister(base_text) catch return error.InvalidOperand };
}

fn appendImplicitVectorNf(context: OperandContext, parsed: *ParsedInstruction) SourceError!void {
    const semantic = context.semantic orelse return;
    if (!hasVectorNfOperand(semantic)) return;
    const expected = vectorMaskOperandCount(semantic) orelse return;

    const has_explicit_mask = parsed.len == expected - 1;
    const has_implicit_mask = parsed.len == expected - 2;
    if (!has_explicit_mask and !has_implicit_mask) return;
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;

    const insert_index = if (has_explicit_mask) parsed.len - 1 else parsed.len;
    var index = parsed.len;
    while (index > insert_index) : (index -= 1) {
        parsed.storage[index] = parsed.storage[index - 1];
    }
    parsed.storage[insert_index] = .{ .imm = try vectorNfValue(context.mnemonic) };
    parsed.len += 1;
}

fn vectorNfValue(mnemonic: []const u8) SourceError!i64 {
    var normalized_buf: [96]u8 = undefined;
    const normalized = normalizeMnemonicLocal(&normalized_buf, mnemonic) catch return error.InvalidOperand;

    inline for (.{ "vlseg", "vlsseg", "vluxseg", "vloxseg", "vsseg", "vssseg", "vsuxseg", "vsoxseg" }) |prefix| {
        if (segmentNfValue(normalized, prefix)) |nf| return nf;
    }

    if (wholeRegisterNfValue(normalized)) |nf| return nf;
    return 0;
}

fn segmentNfValue(normalized: []const u8, prefix: []const u8) ?i64 {
    if (!std.mem.startsWith(u8, normalized, prefix)) return null;
    if (normalized.len <= prefix.len) return null;
    const ch = normalized[prefix.len];
    if (ch < '2' or ch > '8') return null;
    return @as(i64, ch - '0') - 1;
}

fn wholeRegisterNfValue(normalized: []const u8) ?i64 {
    if (normalized.len < 5) return null;
    if (normalized[0] != 'v' or (normalized[1] != 'l' and normalized[1] != 's')) return null;
    const ch = normalized[2];
    if (ch != '1' and ch != '2' and ch != '4' and ch != '8') return null;
    const rest = normalized[3..];
    if (std.mem.startsWith(u8, rest, "r_")) return @as(i64, ch - '0') - 1;
    if (normalized[1] == 'l' and std.mem.startsWith(u8, rest, "re")) return @as(i64, ch - '0') - 1;
    return null;
}

fn parseSpecialOperand(token: []const u8, resolver: ?ExpressionResolver, context: OperandContext) SourceError!types.Operand {
    const semantic = context.semantic orelse return error.UnsupportedOperandSyntax;
    if (hasVectorMaskOperand(semantic) and isVectorMaskOperand(token)) {
        return .{ .imm = 0 };
    }
    return switch (semantic) {
        .rd_rs1_zimm11,
        .rd_zimm5_zimm10,
        => .{ .imm = parseVType(token) catch |err| switch (err) {
            error.UnsupportedOperandSyntax => try parseImmediate(token, resolver),
            else => return err,
        } },
        .c_sreg_sreg => .{ .imm = try parseZcmpShortRegister(token) },
        .c_rlist_spimm => .{ .imm = parseRegisterList(token) catch |err| switch (err) {
            error.UnsupportedOperandSyntax => try parseImmediate(token, resolver),
            else => return err,
        } },
        .c_mop_t,
        .c_index,
        => .{ .imm = try parseImmediate(token, resolver) },
        else => error.UnsupportedOperandSyntax,
    };
}

fn appendImplicitVectorMask(context: OperandContext, parsed: *ParsedInstruction) SourceError!void {
    const semantic = context.semantic orelse return;
    const expected = vectorMaskOperandCount(semantic) orelse return;
    if (parsed.len + 1 != expected) return;
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .imm = 1 };
    parsed.len += 1;
}

fn hasVectorMaskOperand(semantic: types.Semantic) bool {
    return vectorMaskOperandCount(semantic) != null;
}

fn vectorMaskOperandCount(semantic: types.Semantic) ?usize {
    return switch (semantic) {
        .vd_vs2_vs1_vm,
        .vd_vs2_rs1_vm,
        .vd_vs2_simm5_vm,
        .vd_vs2_zimm5_vm,
        .vd_vs2_zimm6_vm,
        => 4,
        .vd_vs2_vm,
        .rd_vs2_vm,
        => 3,
        .vd_vm => 2,
        .vd_rs1_nf_vm,
        .vs3_rs1_nf_vm,
        => 4,
        .vd_rs1_vs2_nf_vm,
        .vs3_rs1_vs2_nf_vm,
        .vd_rs1_rs2_nf_vm,
        .vs3_rs1_rs2_nf_vm,
        => 5,
        else => null,
    };
}

fn isExplicitVectorMaskPosition(context: OperandContext, parsed_len: usize) bool {
    const semantic = context.semantic orelse return false;
    const expected = vectorMaskOperandCount(semantic) orelse return false;
    if (hasVectorNfOperand(semantic)) {
        return parsed_len + 2 == expected;
    }
    return parsed_len + 1 == expected;
}

fn isVectorMaskOperand(token: []const u8) bool {
    return std.ascii.eqlIgnoreCase(std.mem.trim(u8, token, " \t\r\n"), "v0.t");
}

fn parseZcmpShortRegister(token: []const u8) SourceError!i64 {
    const reg = api.parseRegister(token) catch return error.InvalidOperand;
    return switch (reg) {
        8 => 0,
        9 => 1,
        18 => 2,
        19 => 3,
        20 => 4,
        21 => 5,
        22 => 6,
        23 => 7,
        else => error.InvalidOperand,
    };
}

fn parseLoadStoreAddress(
    token: []const u8,
    resolver: ?ExpressionResolver,
    memory_order: MemoryOperandOrder,
) SourceError![2]types.Operand {
    if (!std.mem.endsWith(u8, token, ")")) return error.UnsupportedOperandSyntax;
    const open = std.mem.lastIndexOfScalar(u8, token, '(') orelse return error.UnsupportedOperandSyntax;
    const offset_text = std.mem.trim(u8, token[0..open], " \t\r\n");
    const base_text = std.mem.trim(u8, token[open + 1 .. token.len - 1], " \t\r\n");
    if (base_text.len == 0) return error.UnsupportedOperandSyntax;
    const base = api.parseRegister(base_text) catch return error.UnsupportedOperandSyntax;
    const offset: i64 = if (offset_text.len == 0) 0 else try parseImmediate(offset_text, resolver);
    return switch (memory_order) {
        .base_then_offset => .{ .{ .reg = base }, .{ .imm = offset } },
        .offset_then_base => .{ .{ .imm = offset }, .{ .reg = base } },
    };
}

fn parseRegisterList(token: []const u8) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed.len < 2 or trimmed[0] != '{' or trimmed[trimmed.len - 1] != '}') {
        return error.UnsupportedOperandSyntax;
    }

    const inner = std.mem.trim(u8, trimmed[1 .. trimmed.len - 1], " \t\r\n");
    const end_reg = try parseZcmpRegisterListEnd(inner);
    return zcmpRegisterListEncoding(end_reg) orelse error.InvalidOperand;
}

fn parseZcmpRegisterListEnd(inner: []const u8) SourceError!u5 {
    if (inner.len == 0) return error.InvalidOperand;

    var parts = std.mem.splitScalar(u8, inner, ',');
    const first = std.mem.trim(u8, parts.next() orelse return error.InvalidOperand, " \t\r\n");
    const first_reg = api.parseRegister(first) catch return error.InvalidOperand;
    if (first_reg != 1) return error.InvalidOperand;

    const second_raw = parts.next() orelse {
        if (parts.next() != null) return error.InvalidOperand;
        return 1;
    };
    if (parts.next() != null) return error.InvalidOperand;

    const second = std.mem.trim(u8, second_raw, " \t\r\n");
    if (second.len == 0) return error.InvalidOperand;
    const dash = std.mem.indexOfScalar(u8, second, '-');
    if (dash) |dash_index| {
        const start_text = std.mem.trim(u8, second[0..dash_index], " \t\r\n");
        const end_text = std.mem.trim(u8, second[dash_index + 1 ..], " \t\r\n");
        const start_reg = api.parseRegister(start_text) catch return error.InvalidOperand;
        const end_reg = api.parseRegister(end_text) catch return error.InvalidOperand;
        if (start_reg != 8) return error.InvalidOperand;
        return end_reg;
    }

    const second_reg = api.parseRegister(second) catch return error.InvalidOperand;
    if (second_reg != 8) return error.InvalidOperand;
    return second_reg;
}

fn zcmpRegisterListEncoding(end_reg: u5) ?i64 {
    return switch (end_reg) {
        1 => 4,
        8 => 5,
        9 => 6,
        18 => 7,
        19 => 8,
        20 => 9,
        21 => 10,
        22 => 11,
        23 => 12,
        24 => 13,
        25 => 14,
        27 => 15,
        else => null,
    };
}

fn memoryOperandOrder(mnemonic: []const u8) MemoryOperandOrder {
    const spec = (api.instructionByMnemonic(mnemonic) catch null) orelse
        (api.instructionByMnemonicAnyXLen(mnemonic) catch null) orelse
        return .base_then_offset;
    return memoryOperandOrderForSpec(spec);
}

fn memoryOperandOrderForSpec(spec: ?*const types.InstructionSpec) MemoryOperandOrder {
    const active = spec orelse return .base_then_offset;
    return switch (active.semantic) {
        .rs2_imm_rs1,
        .rs2_offset,
        .rs2_rs1_offset,
        .c_rd_p_rs1_p_uimm,
        .c_rs1_p_rs2_p_uimm,
        => .offset_then_base,
        else => .base_then_offset,
    };
}

fn parseImmediate(token: []const u8, resolver: ?ExpressionResolver) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidOperand;
    if (std.fmt.parseInt(i64, trimmed, 0)) |imm| return imm else |_| {}
    if (resolver) |active| {
        if (try active.resolve(trimmed)) |value| return value;
    }
    return error.InvalidOperand;
}

fn parseFenceMask(token: []const u8) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidOperand;
    var mask: i64 = 0;
    for (trimmed) |ch| {
        mask |= switch (std.ascii.toLower(ch)) {
            'i' => 0b1000,
            'o' => 0b0100,
            'r' => 0b0010,
            'w' => 0b0001,
            else => return error.InvalidOperand,
        };
    }
    return mask;
}

fn parseRoundingMode(token: []const u8) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(trimmed, "rne")) return 0;
    if (std.ascii.eqlIgnoreCase(trimmed, "rtz")) return 1;
    if (std.ascii.eqlIgnoreCase(trimmed, "rdn")) return 2;
    if (std.ascii.eqlIgnoreCase(trimmed, "rup")) return 3;
    if (std.ascii.eqlIgnoreCase(trimmed, "rmm")) return 4;
    if (std.ascii.eqlIgnoreCase(trimmed, "dyn")) return 7;
    return error.InvalidOperand;
}

fn parseVType(token: []const u8) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    if (trimmed.len == 0) return error.UnsupportedOperandSyntax;
    if (std.ascii.toLower(trimmed[0]) != 'e') return error.UnsupportedOperandSyntax;

    var parts = std.mem.splitScalar(u8, trimmed, ',');
    const sew_text = std.mem.trim(u8, parts.next() orelse return error.InvalidOperand, " \t\r\n");
    const lmul_text = std.mem.trim(u8, parts.next() orelse return error.InvalidOperand, " \t\r\n");
    const tail_text = std.mem.trim(u8, parts.next() orelse return error.InvalidOperand, " \t\r\n");
    const mask_text = std.mem.trim(u8, parts.next() orelse return error.InvalidOperand, " \t\r\n");
    if (parts.next() != null) return error.InvalidOperand;

    return parseVTypeParts(sew_text, lmul_text, tail_text, mask_text);
}

fn parseVTypeParts(
    sew_text: []const u8,
    lmul_text: []const u8,
    tail_text: []const u8,
    mask_text: []const u8,
) SourceError!i64 {
    const sew = try parseVTypeSew(sew_text);
    const lmul = try parseVTypeLmul(lmul_text);
    const tail_agnostic: i64 = if (std.ascii.eqlIgnoreCase(tail_text, "ta"))
        1
    else if (std.ascii.eqlIgnoreCase(tail_text, "tu"))
        0
    else
        return error.InvalidOperand;
    const mask_agnostic: i64 = if (std.ascii.eqlIgnoreCase(mask_text, "ma"))
        1
    else if (std.ascii.eqlIgnoreCase(mask_text, "mu"))
        0
    else
        return error.InvalidOperand;

    return lmul | (sew << 3) | (tail_agnostic << 6) | (mask_agnostic << 7);
}

fn parseVTypeSew(token: []const u8) SourceError!i64 {
    if (std.ascii.eqlIgnoreCase(token, "e8")) return 0;
    if (std.ascii.eqlIgnoreCase(token, "e16")) return 1;
    if (std.ascii.eqlIgnoreCase(token, "e32")) return 2;
    if (std.ascii.eqlIgnoreCase(token, "e64")) return 3;
    return error.InvalidOperand;
}

fn parseVTypeLmul(token: []const u8) SourceError!i64 {
    if (std.ascii.eqlIgnoreCase(token, "m1")) return 0;
    if (std.ascii.eqlIgnoreCase(token, "m2")) return 1;
    if (std.ascii.eqlIgnoreCase(token, "m4")) return 2;
    if (std.ascii.eqlIgnoreCase(token, "m8")) return 3;
    if (std.ascii.eqlIgnoreCase(token, "mf8")) return 5;
    if (std.ascii.eqlIgnoreCase(token, "mf4")) return 6;
    if (std.ascii.eqlIgnoreCase(token, "mf2")) return 7;
    return error.InvalidOperand;
}

const CsrName = struct {
    name: []const u8,
    value: i64,
};

const csr_names = [_]CsrName{
    .{ .name = "fflags", .value = 0x001 },
    .{ .name = "frm", .value = 0x002 },
    .{ .name = "fcsr", .value = 0x003 },
    .{ .name = "cycle", .value = 0xc00 },
    .{ .name = "time", .value = 0xc01 },
    .{ .name = "instret", .value = 0xc02 },
    .{ .name = "cycleh", .value = 0xc80 },
    .{ .name = "timeh", .value = 0xc81 },
    .{ .name = "instreth", .value = 0xc82 },
    .{ .name = "sstatus", .value = 0x100 },
    .{ .name = "sie", .value = 0x104 },
    .{ .name = "stvec", .value = 0x105 },
    .{ .name = "scounteren", .value = 0x106 },
    .{ .name = "sscratch", .value = 0x140 },
    .{ .name = "sepc", .value = 0x141 },
    .{ .name = "scause", .value = 0x142 },
    .{ .name = "stval", .value = 0x143 },
    .{ .name = "sip", .value = 0x144 },
    .{ .name = "satp", .value = 0x180 },
    .{ .name = "mstatus", .value = 0x300 },
    .{ .name = "misa", .value = 0x301 },
    .{ .name = "medeleg", .value = 0x302 },
    .{ .name = "mideleg", .value = 0x303 },
    .{ .name = "mie", .value = 0x304 },
    .{ .name = "mtvec", .value = 0x305 },
    .{ .name = "mcounteren", .value = 0x306 },
    .{ .name = "mscratch", .value = 0x340 },
    .{ .name = "mepc", .value = 0x341 },
    .{ .name = "mcause", .value = 0x342 },
    .{ .name = "mtval", .value = 0x343 },
    .{ .name = "mip", .value = 0x344 },
    .{ .name = "mstatush", .value = 0x310 },
    .{ .name = "pmpcfg0", .value = 0x3a0 },
    .{ .name = "pmpcfg1", .value = 0x3a1 },
    .{ .name = "pmpcfg2", .value = 0x3a2 },
    .{ .name = "pmpcfg3", .value = 0x3a3 },
    .{ .name = "pmpaddr0", .value = 0x3b0 },
    .{ .name = "pmpaddr1", .value = 0x3b1 },
    .{ .name = "pmpaddr2", .value = 0x3b2 },
    .{ .name = "pmpaddr3", .value = 0x3b3 },
};

fn parseCsrName(token: []const u8) SourceError!i64 {
    const trimmed = std.mem.trim(u8, token, " \t\r\n");
    for (csr_names) |entry| {
        if (std.ascii.eqlIgnoreCase(trimmed, entry.name)) return entry.value;
    }
    return error.InvalidOperand;
}

const Ordering = struct {
    aq: i64,
    rl: i64,
};

const MnemonicInfo = struct {
    base: []const u8,
    ordering: ?Ordering,
    suffix_immediate: ?i64 = null,
};

fn parseMnemonic(mnemonic: []const u8) MnemonicInfo {
    if (parseZimopMnemonic(mnemonic)) |info| return info;
    if (parseZalasrMnemonic(mnemonic)) |info| return info;
    if (orderingSuffixLen(mnemonic, "_aqrl")) |suffix_len| {
        return .{ .base = mnemonic[0 .. mnemonic.len - suffix_len], .ordering = .{ .aq = 1, .rl = 1 } };
    }
    if (orderingSuffixLen(mnemonic, "_aq")) |suffix_len| {
        return .{ .base = mnemonic[0 .. mnemonic.len - suffix_len], .ordering = .{ .aq = 1, .rl = 0 } };
    }
    if (orderingSuffixLen(mnemonic, "_rl")) |suffix_len| {
        return .{ .base = mnemonic[0 .. mnemonic.len - suffix_len], .ordering = .{ .aq = 0, .rl = 1 } };
    }
    return .{ .base = mnemonic, .ordering = null };
}

fn parseZimopMnemonic(mnemonic: []const u8) ?MnemonicInfo {
    var normalized_buf: [96]u8 = undefined;
    const normalized = normalizeMnemonicLocal(&normalized_buf, mnemonic) catch return null;
    if (std.mem.startsWith(u8, normalized, "mop_r_")) {
        const encoded = std.fmt.parseInt(i64, normalized["mop_r_".len..], 10) catch return null;
        if (encoded < 0 or encoded > 31) return null;
        return .{ .base = "mop.r.n", .ordering = null, .suffix_immediate = encoded };
    }
    if (std.mem.startsWith(u8, normalized, "mop_rr_")) {
        const encoded = std.fmt.parseInt(i64, normalized["mop_rr_".len..], 10) catch return null;
        if (encoded < 0 or encoded > 7) return null;
        return .{ .base = "mop.rr.n", .ordering = null, .suffix_immediate = encoded };
    }
    return null;
}

fn parseZalasrMnemonic(mnemonic: []const u8) ?MnemonicInfo {
    var normalized_buf: [96]u8 = undefined;
    const normalized = normalizeMnemonicLocal(&normalized_buf, mnemonic) catch return null;

    if (std.mem.endsWith(u8, normalized, "_aqrl")) {
        const normalized_base = normalized[0 .. normalized.len - "_aqrl".len];
        if (zalasrAcquireLoadMnemonic(normalized_base)) |base| {
            return .{ .base = base, .ordering = null, .suffix_immediate = 1 };
        }
        if (zalasrReleaseStoreMnemonic(normalized_base)) |base| {
            return .{ .base = base, .ordering = null, .suffix_immediate = 1 };
        }
        return null;
    }

    if (std.mem.endsWith(u8, normalized, "_aq")) {
        const normalized_base = normalized[0 .. normalized.len - "_aq".len];
        return if (zalasrAcquireLoadMnemonic(normalized_base)) |base|
            .{ .base = base, .ordering = null, .suffix_immediate = 0 }
        else
            null;
    }

    if (std.mem.endsWith(u8, normalized, "_rl")) {
        const normalized_base = normalized[0 .. normalized.len - "_rl".len];
        return if (zalasrReleaseStoreMnemonic(normalized_base)) |base|
            .{ .base = base, .ordering = null, .suffix_immediate = 0 }
        else
            null;
    }

    return null;
}

fn zalasrAcquireLoadMnemonic(normalized_base: []const u8) ?[]const u8 {
    inline for (.{
        .{ .base = "lb", .mnemonic = "lb.aq" },
        .{ .base = "lh", .mnemonic = "lh.aq" },
        .{ .base = "lw", .mnemonic = "lw.aq" },
        .{ .base = "ld", .mnemonic = "ld.aq" },
    }) |entry| {
        if (std.mem.eql(u8, normalized_base, entry.base)) return entry.mnemonic;
    }
    return null;
}

fn zalasrReleaseStoreMnemonic(normalized_base: []const u8) ?[]const u8 {
    inline for (.{
        .{ .base = "sb", .mnemonic = "sb.rl" },
        .{ .base = "sh", .mnemonic = "sh.rl" },
        .{ .base = "sw", .mnemonic = "sw.rl" },
        .{ .base = "sd", .mnemonic = "sd.rl" },
    }) |entry| {
        if (std.mem.eql(u8, normalized_base, entry.base)) return entry.mnemonic;
    }
    return null;
}

fn orderingSuffixLen(mnemonic: []const u8, suffix: []const u8) ?usize {
    var normalized_buf: [96]u8 = undefined;
    const normalized = normalizeMnemonicLocal(&normalized_buf, mnemonic) catch return null;
    if (!std.mem.endsWith(u8, normalized, suffix)) return null;
    return suffix.len;
}

fn appendOrderingOperands(ordering: ?Ordering, parsed: *ParsedInstruction) SourceError!void {
    const active = ordering orelse return;
    if (parsed.len + 2 > parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .imm = active.aq };
    parsed.storage[parsed.len + 1] = .{ .imm = active.rl };
    parsed.len += 2;
}

fn appendSuffixImmediate(suffix_immediate: ?i64, parsed: *ParsedInstruction) SourceError!void {
    const active = suffix_immediate orelse return;
    if (parsed.len >= parsed.storage.len) return error.TooManyOperands;
    parsed.storage[parsed.len] = .{ .imm = active };
    parsed.len += 1;
}

fn normalizeParsedOperandOrder(context: OperandContext, parsed: *ParsedInstruction) void {
    switch (context.semantic orelse return) {
        .rs1_rs2_aq => {
            if (parsed.len >= 2) {
                const rs2 = parsed.storage[0];
                parsed.storage[0] = parsed.storage[1];
                parsed.storage[1] = rs2;
            }
        },
        else => {},
    }
}

test "source parser encodes canonical atomic address forms" {
    const amoadd = try encodeInstructionText("amoadd.w.aqrl a0, a1, (a2)", 64, null);
    try std.testing.expectEqualSlices(u8, &.{ 0x2f, 0x25, 0xb6, 0x06 }, amoadd.asSlice());

    const load_reserved = try encodeInstructionText("lr.d.aq a3, (a4)", 64, null);
    try std.testing.expectEqualSlices(u8, &.{ 0xaf, 0x36, 0x07, 0x14 }, load_reserved.asSlice());

    const store_conditional = try encodeInstructionText("sc.d.rl a5, a6, (a7)", 64, null);
    try std.testing.expectEqualSlices(u8, &.{ 0xaf, 0xb7, 0x08, 0x1b }, store_conditional.asSlice());
}

fn normalizeMnemonicLocal(buffer: []u8, mnemonic: []const u8) SourceError![]const u8 {
    const trimmed = std.mem.trim(u8, mnemonic, " \t\r\n");
    if (trimmed.len > buffer.len) return error.MnemonicTooLong;
    for (trimmed, 0..) |ch, index| {
        buffer[index] = switch (ch) {
            '.', '-' => '_',
            else => std.ascii.toLower(ch),
        };
    }
    return buffer[0..trimmed.len];
}

fn stripCommentAndWhitespace(line: []const u8) []const u8 {
    var end = line.len;
    if (std.mem.indexOfScalar(u8, line, '#')) |idx| end = @min(end, idx);
    if (std.mem.indexOfScalar(u8, line, ';')) |idx| end = @min(end, idx);
    return std.mem.trim(u8, line[0..end], " \t\r\n");
}

fn firstWhitespace(text: []const u8) ?usize {
    for (text, 0..) |ch, index| {
        if (ch == ' ' or ch == '\t') return index;
    }
    return null;
}
