const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ParseError = Allocator.Error || error{
    InvalidInstructionText,
};

pub const ParsedInstruction = struct {
    mnemonic: []u8,
    operands: []const []const u8,
    owned_operands: [][]u8,

    pub fn deinit(self: *ParsedInstruction, allocator: Allocator) void {
        allocator.free(self.mnemonic);
        for (self.owned_operands) |operand| {
            allocator.free(operand);
        }
        allocator.free(self.owned_operands);
        allocator.free(self.operands);
        self.* = undefined;
    }
};

pub fn parseInstructionText(allocator: Allocator, text: []const u8) ParseError!ParsedInstruction {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidInstructionText;

    const split = std.mem.indexOfAny(u8, trimmed, " \t");
    const mnemonic_text = if (split) |index| trimmed[0..index] else trimmed;
    if (mnemonic_text.len == 0) return error.InvalidInstructionText;

    const mnemonic = try allocator.dupe(u8, mnemonic_text);
    errdefer allocator.free(mnemonic);

    var owned_operands: std.ArrayList([]u8) = .empty;
    errdefer deinitOperandList(&owned_operands, allocator);

    if (split) |index| {
        const operands_text = std.mem.trim(u8, trimmed[index + 1 ..], " \t\r\n");
        if (operands_text.len != 0) {
            var iterator = OperandIterator.init(operands_text);
            while (iterator.next()) |operand_text| {
                const owned = try allocator.dupe(u8, operand_text);
                errdefer allocator.free(owned);
                try owned_operands.append(allocator, owned);
            }
        }
    }

    const owned_slice = try owned_operands.toOwnedSlice(allocator);
    errdefer {
        for (owned_slice) |operand| allocator.free(operand);
        allocator.free(owned_slice);
    }

    const operand_refs = try allocator.alloc([]const u8, owned_slice.len);
    errdefer allocator.free(operand_refs);
    for (owned_slice, 0..) |operand, index| {
        operand_refs[index] = operand;
    }

    return .{
        .mnemonic = mnemonic,
        .operands = operand_refs,
        .owned_operands = owned_slice,
    };
}

fn deinitOperandList(list: *std.ArrayList([]u8), allocator: Allocator) void {
    for (list.items) |operand| allocator.free(operand);
    list.deinit(allocator);
}

pub fn operandText(text: []const u8) ?[]const u8 {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const split = std.mem.indexOfAny(u8, trimmed, " \t") orelse return null;
    return std.mem.trim(u8, trimmed[split + 1 ..], " \t\r\n");
}

pub const OperandIterator = struct {
    text: []const u8,
    index: usize = 0,

    pub fn init(text: []const u8) OperandIterator {
        return .{ .text = text };
    }

    pub fn next(self: *OperandIterator) ?[]const u8 {
        while (self.index < self.text.len and (self.text[self.index] == ',' or std.ascii.isWhitespace(self.text[self.index]))) {
            self.index += 1;
        }
        if (self.index >= self.text.len) return null;

        const start = self.index;
        var bracket_depth: usize = 0;
        var paren_depth: usize = 0;
        var brace_depth: usize = 0;
        var in_quote: ?u8 = null;

        while (self.index < self.text.len) : (self.index += 1) {
            const byte = self.text[self.index];
            if (in_quote) |quote| {
                if (byte == quote) in_quote = null;
                continue;
            }

            switch (byte) {
                '\'', '"' => in_quote = byte,
                '[' => bracket_depth += 1,
                ']' => {
                    if (bracket_depth > 0) bracket_depth -= 1;
                },
                '(' => paren_depth += 1,
                ')' => {
                    if (paren_depth > 0) paren_depth -= 1;
                },
                '{' => brace_depth += 1,
                '}' => {
                    if (brace_depth > 0) brace_depth -= 1;
                },
                ',' => {
                    if (bracket_depth == 0 and paren_depth == 0 and brace_depth == 0) break;
                },
                else => {},
            }
        }

        const end = self.index;
        if (self.index < self.text.len and self.text[self.index] == ',') self.index += 1;
        return std.mem.trim(u8, self.text[start..end], " \t\r\n");
    }
};

pub fn looksLikeSymbolReference(token: []const u8) bool {
    if (token.len == 0) return false;
    if (!std.ascii.isAlphabetic(token[0]) and token[0] != '_' and token[0] != '.') return false;
    for (token) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.' and byte != '$') return false;
    }
    return true;
}

pub fn isKnownRiscvWord(token: []const u8) bool {
    const lower = std.ascii.eqlIgnoreCase;
    return lower(token, "zero") or
        lower(token, "ra") or
        lower(token, "sp") or
        lower(token, "gp") or
        lower(token, "tp") or
        isRiscvRegisterNumber(token) or
        isRiscvAbiRegister(token);
}

fn isRiscvRegisterNumber(token: []const u8) bool {
    if (token.len < 2 or token.len > 3) return false;
    const prefix = token[0];
    if (prefix != 'x' and prefix != 'X' and prefix != 'f' and prefix != 'F') return false;
    const number = std.fmt.parseInt(u8, token[1..], 10) catch return false;
    return number < 32;
}

fn isRiscvAbiRegister(token: []const u8) bool {
    if (token.len < 2 or token.len > 3) return false;
    const class = token[0];
    if (class != 'a' and class != 'A' and
        class != 's' and class != 'S' and
        class != 't' and class != 'T')
    {
        return false;
    }
    const index = std.fmt.parseInt(u8, token[1..], 10) catch return false;
    return switch (std.ascii.toLower(class)) {
        'a' => index < 8,
        's' => index < 12,
        't' => index < 7,
        else => false,
    };
}

test "ISA text iterator keeps nested operands together" {
    var parsed = try parseInstructionText(std.testing.allocator, "mov rax, [rbx + foo(1, 2)], DosHeader { magic: 0x5a4d, lfanew: 0x80 }");
    defer parsed.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("mov", parsed.mnemonic);
    try std.testing.expectEqual(@as(usize, 3), parsed.operands.len);
    try std.testing.expectEqualStrings("rax", parsed.operands[0]);
    try std.testing.expectEqualStrings("[rbx + foo(1, 2)]", parsed.operands[1]);
    try std.testing.expectEqualStrings("DosHeader { magic: 0x5a4d, lfanew: 0x80 }", parsed.operands[2]);
}

test "ISA text symbol references reject compound expressions" {
    try std.testing.expect(!looksLikeSymbolReference("target+4"));
}
