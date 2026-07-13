const std = @import("std");

const identifier = @import("identifier.zig");
const source = @import("source.zig");

pub const TokenKind = enum {
    blank,
    comment,
    label,
    isa_line,
    api_call,
    legacy_directive,
    meta_line,
    meta_block_start,
    meta_block_end,
};

pub const Token = struct {
    kind: TokenKind,
    span: source.SourceSpan,
    text: []const u8,
    line: u32,
    column: u32,
};

pub const Lexer = struct {
    source_id: ?source.SourceId = null,
    input: []const u8,
    cursor: usize = 0,
    line: u32 = 1,

    pub fn init(input: []const u8) Lexer {
        return .{
            .input = input,
        };
    }

    pub fn initWithSource(source_id: source.SourceId, input: []const u8) Lexer {
        return .{
            .source_id = source_id,
            .input = input,
        };
    }

    pub fn next(self: *Lexer) error{SourceTooLarge}!Token {
        if (self.cursor >= self.input.len) {
            return .{
                .kind = .blank,
                .span = try self.span(self.input.len, self.input.len),
                .text = "",
                .line = self.line,
                .column = 1,
            };
        }

        const line_start = self.cursor;
        var line_end = line_start;
        while (line_end < self.input.len and self.input[line_end] != '\n' and self.input[line_end] != '\r') {
            line_end += 1;
        }

        const next_cursor = consumeLineEnding(self.input, line_end);
        const raw_line = self.input[line_start..line_end];
        const current_line = self.line;
        self.cursor = next_cursor;
        self.line += 1;

        return try classifyLine(self.source_id, raw_line, line_start, current_line);
    }

    pub fn done(self: *const Lexer) bool {
        return self.cursor >= self.input.len;
    }

    fn span(self: *const Lexer, start: usize, end: usize) error{SourceTooLarge}!source.SourceSpan {
        return makeSpan(self.source_id, start, end);
    }
};

pub fn classifyLine(
    source_id: ?source.SourceId,
    raw_line: []const u8,
    line_start: usize,
    line: u32,
) error{SourceTooLarge}!Token {
    const trimmed = trimHorizontal(raw_line);
    const offset = horizontalLeftTrimOffset(raw_line);
    const absolute_start = line_start + offset;
    const absolute_end = absolute_start + trimmed.len;

    if (trimmed.len == 0) {
        return .{
            .kind = .blank,
            .span = try makeSpan(source_id, line_start, line_start + raw_line.len),
            .text = trimmed,
            .line = line,
            .column = try columnFromOffset(offset),
        };
    }

    if (isCommentLine(trimmed)) {
        return .{
            .kind = .comment,
            .span = try makeSpan(source_id, absolute_start, absolute_end),
            .text = trimmed,
            .line = line,
            .column = try columnFromOffset(offset),
        };
    }

    const kind = classifyTrimmed(trimmed);
    return .{
        .kind = kind,
        .span = try makeSpan(source_id, absolute_start, absolute_end),
        .text = trimmed,
        .line = line,
        .column = try columnFromOffset(offset),
    };
}

fn classifyTrimmed(trimmed: []const u8) TokenKind {
    if (std.mem.eql(u8, trimmed, "{")) return .meta_block_start;
    if (std.mem.eql(u8, trimmed, "}")) return .meta_block_end;
    if (isStandaloneLabel(trimmed)) return .label;
    if (looksLikeLegacyDirective(trimmed)) return .legacy_directive;
    if (looksLikeMetaLine(trimmed)) return .meta_line;
    if (looksLikeApiCall(trimmed)) return .api_call;
    return .isa_line;
}

fn consumeLineEnding(input: []const u8, line_end: usize) usize {
    if (line_end >= input.len) return line_end;
    if (input[line_end] == '\r') {
        const after_cr = line_end + 1;
        if (after_cr < input.len and input[after_cr] == '\n') return after_cr + 1;
        return after_cr;
    }
    return line_end + 1;
}

fn trimHorizontal(line: []const u8) []const u8 {
    return std.mem.trim(u8, line, " \t");
}

fn horizontalLeftTrimOffset(line: []const u8) usize {
    var offset: usize = 0;
    while (offset < line.len and (line[offset] == ' ' or line[offset] == '\t')) {
        offset += 1;
    }
    return offset;
}

fn isCommentLine(trimmed: []const u8) bool {
    return std.mem.startsWith(u8, trimmed, ";") or
        std.mem.startsWith(u8, trimmed, "//") or
        std.mem.startsWith(u8, trimmed, "#");
}

fn isStandaloneLabel(trimmed: []const u8) bool {
    if (trimmed.len < 2) return false;
    if (trimmed[trimmed.len - 1] != ':') return false;
    return isIdentifier(trimmed[0 .. trimmed.len - 1]);
}

fn isIdentifier(text: []const u8) bool {
    return identifier.isName(text);
}

fn looksLikeMetaLine(trimmed: []const u8) bool {
    const first_word = firstWord(trimmed);
    return std.mem.eql(u8, first_word, "let") or
        std.mem.eql(u8, first_word, "const") or
        std.mem.eql(u8, first_word, "var") or
        std.mem.eql(u8, first_word, "fn") or
        std.mem.eql(u8, first_word, "meta") or
        std.mem.eql(u8, first_word, "packed") or
        std.mem.eql(u8, first_word, "for") or
        std.mem.eql(u8, first_word, "while") or
        std.mem.eql(u8, first_word, "defer") or
        std.mem.eql(u8, first_word, "late_layout") or
        std.mem.eql(u8, first_word, "if") or
        std.mem.eql(u8, first_word, "else") or
        std.mem.eql(u8, first_word, "return") or
        std.mem.eql(u8, first_word, "break") or
        std.mem.eql(u8, first_word, "continue") or
        std.mem.eql(u8, first_word, "struct") or
        std.mem.eql(u8, first_word, "enum") or
        std.mem.eql(u8, first_word, "union") or
        looksLikeAssignment(trimmed) or
        std.mem.startsWith(u8, trimmed, "@");
}

fn looksLikeAssignment(trimmed: []const u8) bool {
    const equals_index = std.mem.indexOfScalar(u8, trimmed, '=') orelse return false;
    if (equals_index == 0) return false;

    if (equals_index + 1 < trimmed.len and trimmed[equals_index + 1] == '=') return false;
    if (equals_index != 0 and (trimmed[equals_index - 1] == '!' or
        trimmed[equals_index - 1] == '<' or
        trimmed[equals_index - 1] == '>' or
        trimmed[equals_index - 1] == '='))
    {
        return false;
    }

    const name = std.mem.trim(u8, trimmed[0..equals_index], " \t");
    return identifier.isName(name);
}

fn looksLikeLegacyDirective(trimmed: []const u8) bool {
    const first_word = firstWord(trimmed);
    return isLegacyDirectiveName(first_word) and !hasCallOpenAfterCallee(trimmed);
}

fn isLegacyDirectiveName(name: []const u8) bool {
    return std.ascii.eqlIgnoreCase(name, "org") or
        std.ascii.eqlIgnoreCase(name, "db") or
        std.ascii.eqlIgnoreCase(name, "dw") or
        std.ascii.eqlIgnoreCase(name, "dd") or
        std.ascii.eqlIgnoreCase(name, "dq") or
        std.ascii.eqlIgnoreCase(name, "resb") or
        std.ascii.eqlIgnoreCase(name, "resw") or
        std.ascii.eqlIgnoreCase(name, "resd") or
        std.ascii.eqlIgnoreCase(name, "resq") or
        std.ascii.eqlIgnoreCase(name, "times") or
        std.ascii.eqlIgnoreCase(name, "align") or
        std.ascii.eqlIgnoreCase(name, "section");
}

fn looksLikeApiCall(trimmed: []const u8) bool {
    return hasCallOpenAfterCallee(trimmed) and callCalleeIsDottedIdentifier(trimmed);
}

fn hasCallOpenAfterCallee(trimmed: []const u8) bool {
    const callee_end = callCalleeEnd(trimmed);
    var index = callee_end;
    while (index < trimmed.len and (trimmed[index] == ' ' or trimmed[index] == '\t')) {
        index += 1;
    }
    return index < trimmed.len and trimmed[index] == '(';
}

fn callCalleeIsDottedIdentifier(trimmed: []const u8) bool {
    const callee = trimmed[0..callCalleeEnd(trimmed)];
    if (callee.len == 0) return false;

    var segment_start: usize = 0;
    var index: usize = 0;
    while (index <= callee.len) : (index += 1) {
        if (index == callee.len or callee[index] == '.') {
            if (!isIdentifier(callee[segment_start..index])) return false;
            segment_start = index + 1;
        }
    }
    return segment_start != 1;
}

fn callCalleeEnd(trimmed: []const u8) usize {
    var end: usize = 0;
    while (end < trimmed.len and isCalleeContinue(trimmed[end])) {
        end += 1;
    }
    return end;
}

fn firstWord(trimmed: []const u8) []const u8 {
    var end: usize = 0;
    while (end < trimmed.len and identifier.isContinue(trimmed[end])) {
        end += 1;
    }
    return trimmed[0..end];
}

fn isCalleeContinue(byte: u8) bool {
    return identifier.isContinue(byte) or byte == '.';
}

fn makeSpan(
    source_id: ?source.SourceId,
    start: usize,
    end: usize,
) error{SourceTooLarge}!source.SourceSpan {
    if (start > std.math.maxInt(u32) or end > std.math.maxInt(u32)) {
        return error.SourceTooLarge;
    }
    return .{
        .source = source_id,
        .start = @intCast(start),
        .end = @intCast(end),
    };
}

fn columnFromOffset(offset: usize) error{SourceTooLarge}!u32 {
    if (offset >= std.math.maxInt(u32)) return error.SourceTooLarge;
    return @intCast(offset + 1);
}

test "lexer classifies labels ISA lines and meta lines" {
    const input =
        \\loop:
        \\    mov rax, 1
        \\origin(0x7c00);
        \\emit.u16(0xaa55);
        \\org 0x7c00
        \\let count = 4
        \\for i in range(0, count) {
        \\}
        \\; comment
        \\
    ;

    var lexer = Lexer.init(input);

    const label = try lexer.next();
    try std.testing.expectEqual(TokenKind.label, label.kind);
    try std.testing.expectEqualStrings("loop:", label.text);
    try std.testing.expectEqual(@as(u32, 1), label.line);
    try std.testing.expectEqual(@as(u32, 1), label.column);

    const instruction = try lexer.next();
    try std.testing.expectEqual(TokenKind.isa_line, instruction.kind);
    try std.testing.expectEqualStrings("mov rax, 1", instruction.text);
    try std.testing.expectEqual(@as(u32, 2), instruction.line);
    try std.testing.expectEqual(@as(u32, 5), instruction.column);

    const origin_call = try lexer.next();
    try std.testing.expectEqual(TokenKind.api_call, origin_call.kind);
    try std.testing.expectEqualStrings("origin(0x7c00);", origin_call.text);

    const emit_call = try lexer.next();
    try std.testing.expectEqual(TokenKind.api_call, emit_call.kind);
    try std.testing.expectEqualStrings("emit.u16(0xaa55);", emit_call.text);

    const legacy_org = try lexer.next();
    try std.testing.expectEqual(TokenKind.legacy_directive, legacy_org.kind);
    try std.testing.expectEqualStrings("org 0x7c00", legacy_org.text);

    const let_line = try lexer.next();
    try std.testing.expectEqual(TokenKind.meta_line, let_line.kind);
    try std.testing.expectEqualStrings("let count = 4", let_line.text);

    const for_line = try lexer.next();
    try std.testing.expectEqual(TokenKind.meta_line, for_line.kind);
    try std.testing.expectEqualStrings("for i in range(0, count) {", for_line.text);

    const block_end = try lexer.next();
    try std.testing.expectEqual(TokenKind.meta_block_end, block_end.kind);

    const comment = try lexer.next();
    try std.testing.expectEqual(TokenKind.comment, comment.kind);

    const blank = try lexer.next();
    try std.testing.expectEqual(TokenKind.blank, blank.kind);
}

test "lexer handles crlf line endings" {
    var lexer = Lexer.init("entry:\r\nret\r\n");

    const label = try lexer.next();
    try std.testing.expectEqual(TokenKind.label, label.kind);
    try std.testing.expectEqualStrings("entry:", label.text);

    const ret = try lexer.next();
    try std.testing.expectEqual(TokenKind.isa_line, ret.kind);
    try std.testing.expectEqualStrings("ret", ret.text);
    try std.testing.expect(lexer.done());
}
