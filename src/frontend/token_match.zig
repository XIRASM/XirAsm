const std = @import("std");

const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const Error = Allocator.Error || error{
    InvalidArgument,
    OutputTooLarge,
    TypeMismatch,
};

const max_pattern_pieces = 64;
const max_input_tokens = 256;
const max_match_attempts = 4096;
const max_bracket_depth = 64;

pub const TokenView = struct {
    items: []const []const u8,

    pub fn deinit(self: *TokenView, allocator: Allocator) void {
        for (self.items) |item| {
            allocator.free(item);
        }
        allocator.free(self.items);
        self.* = .{ .items = &.{} };
    }
};

const PatternPiece = union(enum) {
    literal: []const u8,
    capture: CaptureSpec,
};

const CaptureSpec = struct {
    name: []const u8,
    kind: CaptureKind,
};

const CaptureKind = enum {
    token,
    name,
    int,
    quoted,
    tokens,
};

const Capture = struct {
    name: []const u8,
    value: value_mod.Value,

    fn deinit(self: *Capture, allocator: Allocator) void {
        self.value.deinit(allocator);
        self.* = .{ .name = "", .value = .void };
    }
};

const MatchState = struct {
    attempts: usize = 0,
};

pub fn tokenizeValue(allocator: Allocator, input: value_mod.Value) Error!value_mod.Value {
    var view = try inputView(allocator, input);
    defer view.deinit(allocator);
    return tokensToListValue(allocator, view.items);
}

pub fn joinValue(allocator: Allocator, input: value_mod.Value) Error!value_mod.Value {
    var items = try listStringView(allocator, input);
    defer items.deinit(allocator);
    return .{ .string = try renderTokens(allocator, items.items) };
}

pub fn matchTokensValue(
    allocator: Allocator,
    pattern_value: value_mod.Value,
    input_value: value_mod.Value,
) Error!value_mod.Value {
    var pattern = try patternView(allocator, pattern_value);
    defer pattern.deinit(allocator);
    if (pattern.items.len > max_pattern_pieces) return error.InvalidArgument;

    var input = try inputView(allocator, input_value);
    defer input.deinit(allocator);
    if (input.items.len > max_input_tokens) return error.InvalidArgument;

    const pieces = try allocator.alloc(PatternPiece, pattern.items.len);
    defer allocator.free(pieces);
    for (pattern.items, 0..) |pattern_token, index| {
        pieces[index] = try parsePatternPiece(pattern_token);
    }
    try rejectDuplicateCaptures(pieces);

    var captures: std.ArrayList(Capture) = .empty;
    defer captures.deinit(allocator);
    defer deinitCaptures(allocator, captures.items);

    var state: MatchState = .{};
    const ok = try matchFrom(allocator, pieces, input.items, 0, 0, &captures, &state);
    return matchResult(allocator, ok, captures.items);
}

pub fn renderTokens(allocator: Allocator, tokens: []const []const u8) Error![]u8 {
    var output_len: usize = 0;
    for (tokens, 0..) |token, index| {
        if (index != 0 and needsSpace(tokens[index - 1], token)) {
            output_len = std.math.add(usize, output_len, 1) catch return error.OutputTooLarge;
        }
        output_len = std.math.add(usize, output_len, token.len) catch return error.OutputTooLarge;
    }

    const output = try allocator.alloc(u8, output_len);
    var write_index: usize = 0;
    for (tokens, 0..) |token, index| {
        if (index != 0 and needsSpace(tokens[index - 1], token)) {
            output[write_index] = ' ';
            write_index += 1;
        }
        @memcpy(output[write_index .. write_index + token.len], token);
        write_index += token.len;
    }
    return output;
}

fn inputView(allocator: Allocator, input: value_mod.Value) Error!TokenView {
    return switch (input) {
        .string => |text| .{ .items = try lexInputTokens(allocator, text) },
        .list => listStringView(allocator, input),
        .void, .integer, .boolean, .bytes, .type, .@"struct", .map => error.TypeMismatch,
    };
}

fn patternView(allocator: Allocator, input: value_mod.Value) Error!TokenView {
    return switch (input) {
        .string => |text| .{ .items = try splitPatternText(allocator, text) },
        .list => listStringView(allocator, input),
        .void, .integer, .boolean, .bytes, .type, .@"struct", .map => error.TypeMismatch,
    };
}

fn listStringView(allocator: Allocator, input: value_mod.Value) Error!TokenView {
    const list = input.expectList() catch return error.TypeMismatch;
    const tokens = try allocator.alloc([]const u8, list.items.len);
    var initialized: usize = 0;
    errdefer {
        for (tokens[0..initialized]) |token| {
            allocator.free(token);
        }
        allocator.free(tokens);
    }

    for (list.items, 0..) |item, index| {
        const text = item.expectString() catch return error.TypeMismatch;
        tokens[index] = try allocator.dupe(u8, text);
        initialized += 1;
    }
    return .{ .items = tokens };
}

fn splitPatternText(allocator: Allocator, text: []const u8) Error![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (parts.items) |part| {
            allocator.free(part);
        }
        parts.deinit(allocator);
    }

    var iter = std.mem.tokenizeAny(u8, text, " \t\r\n");
    while (iter.next()) |part| {
        try parts.append(allocator, try allocator.dupe(u8, part));
    }
    return parts.toOwnedSlice(allocator);
}

fn lexInputTokens(allocator: Allocator, text: []const u8) Error![]const []const u8 {
    var parts: std.ArrayList([]const u8) = .empty;
    errdefer {
        for (parts.items) |part| {
            allocator.free(part);
        }
        parts.deinit(allocator);
    }

    var index: usize = 0;
    while (index < text.len) {
        const byte = text[index];
        if (std.ascii.isWhitespace(byte)) {
            index += 1;
            continue;
        }

        const start = index;
        if (byte == '"' or byte == '\'') {
            index = try quotedTokenEnd(text, index);
        } else if (operatorWidth(text[index..])) |width| {
            index += width;
        } else {
            while (index < text.len and
                !std.ascii.isWhitespace(text[index]) and
                text[index] != '"' and
                text[index] != '\'' and
                operatorWidth(text[index..]) == null)
            {
                index += 1;
            }
        }

        try parts.append(allocator, try allocator.dupe(u8, text[start..index]));
        if (parts.items.len > max_input_tokens) return error.InvalidArgument;
    }

    return parts.toOwnedSlice(allocator);
}

fn quotedTokenEnd(text: []const u8, start: usize) Error!usize {
    const quote = text[start];
    var index = start + 1;
    while (index < text.len) : (index += 1) {
        if (text[index] == '\\') {
            index += 1;
            if (index >= text.len) return error.InvalidArgument;
            continue;
        }
        if (text[index] == quote) return index + 1;
    }
    return error.InvalidArgument;
}

fn operatorWidth(text: []const u8) ?usize {
    if (text.len == 0) return null;
    if (text.len >= 2) {
        const two = text[0..2];
        if (std.mem.eql(u8, two, "==") or
            std.mem.eql(u8, two, "!=") or
            std.mem.eql(u8, two, "<=") or
            std.mem.eql(u8, two, ">=") or
            std.mem.eql(u8, two, "&&") or
            std.mem.eql(u8, two, "||") or
            std.mem.eql(u8, two, "<<") or
            std.mem.eql(u8, two, ">>") or
            std.mem.eql(u8, two, "->") or
            std.mem.eql(u8, two, "=>") or
            std.mem.eql(u8, two, "::"))
        {
            return 2;
        }
    }
    return if (isSingleOperator(text[0])) 1 else null;
}

fn isSingleOperator(byte: u8) bool {
    return switch (byte) {
        ',', '(', ')', '[', ']', '{', '}', '<', '>', ':', '=', '+', '-', '*', '/', '%', '&', '|', '^', '~', '.', '!', '?', ';' => true,
        else => false,
    };
}

fn parsePatternPiece(token: []const u8) Error!PatternPiece {
    if (token.len == 0) return error.InvalidArgument;
    if (token[0] == '=') {
        if (token.len == 1) return error.InvalidArgument;
        return .{ .literal = token[1..] };
    }

    const split_index = std.mem.indexOfScalar(u8, token, ':') orelse return error.InvalidArgument;
    const name = token[0..split_index];
    const kind_text = token[split_index + 1 ..];
    if (!isName(name) or kind_text.len == 0) return error.InvalidArgument;

    const kind: CaptureKind = if (std.mem.eql(u8, kind_text, "token"))
        .token
    else if (std.mem.eql(u8, kind_text, "name"))
        .name
    else if (std.mem.eql(u8, kind_text, "int"))
        .int
    else if (std.mem.eql(u8, kind_text, "quoted"))
        .quoted
    else if (std.mem.eql(u8, kind_text, "tokens"))
        .tokens
    else
        return error.InvalidArgument;

    return .{ .capture = .{ .name = name, .kind = kind } };
}

fn rejectDuplicateCaptures(pieces: []const PatternPiece) Error!void {
    for (pieces, 0..) |piece, index| {
        const capture = switch (piece) {
            .literal => continue,
            .capture => |capture| capture,
        };
        for (pieces[0..index]) |previous| {
            switch (previous) {
                .literal => {},
                .capture => |previous_capture| {
                    if (std.mem.eql(u8, previous_capture.name, capture.name)) return error.InvalidArgument;
                },
            }
        }
    }
}

fn matchFrom(
    allocator: Allocator,
    pieces: []const PatternPiece,
    input: []const []const u8,
    pattern_index: usize,
    input_index: usize,
    captures: *std.ArrayList(Capture),
    state: *MatchState,
) Error!bool {
    state.attempts = std.math.add(usize, state.attempts, 1) catch return error.InvalidArgument;
    if (state.attempts > max_match_attempts) return error.InvalidArgument;

    if (pattern_index == pieces.len) return input_index == input.len;

    switch (pieces[pattern_index]) {
        .literal => |literal| {
            if (input_index >= input.len) return false;
            if (!std.mem.eql(u8, input[input_index], literal)) return false;
            return matchFrom(allocator, pieces, input, pattern_index + 1, input_index + 1, captures, state);
        },
        .capture => |capture| {
            if (capture.kind == .tokens) {
                var end = input_index;
                while (end <= input.len) : (end += 1) {
                    if (!tokensAreBalanced(input[input_index..end])) continue;
                    const mark = captures.items.len;
                    try appendTokensCapture(allocator, captures, capture.name, input[input_index..end]);
                    if (try matchFrom(allocator, pieces, input, pattern_index + 1, end, captures, state)) return true;
                    deinitCaptures(allocator, captures.items[mark..]);
                    captures.shrinkRetainingCapacity(mark);
                }
                return false;
            }

            if (input_index >= input.len) return false;
            var captured = (try captureSingleToken(allocator, capture.kind, input[input_index])) orelse return false;
            errdefer captured.deinit(allocator);

            const mark = captures.items.len;
            try captures.append(allocator, .{
                .name = capture.name,
                .value = captured,
            });
            captured = .void;

            if (try matchFrom(allocator, pieces, input, pattern_index + 1, input_index + 1, captures, state)) return true;
            deinitCaptures(allocator, captures.items[mark..]);
            captures.shrinkRetainingCapacity(mark);
            return false;
        },
    }
}

fn appendTokensCapture(
    allocator: Allocator,
    captures: *std.ArrayList(Capture),
    name: []const u8,
    tokens: []const []const u8,
) Error!void {
    var value = try tokensToListValue(allocator, tokens);
    errdefer value.deinit(allocator);
    try captures.append(allocator, .{
        .name = name,
        .value = value,
    });
    value = .void;
}

fn captureSingleToken(allocator: Allocator, kind: CaptureKind, token: []const u8) Error!?value_mod.Value {
    return switch (kind) {
        .token => .{ .string = try allocator.dupe(u8, token) },
        .name => if (isName(token))
            .{ .string = try allocator.dupe(u8, token) }
        else
            null,
        .int => if (std.fmt.parseInt(u64, token, 0)) |value|
            .{ .integer = .{ .value = value } }
        else |_|
            null,
        .quoted => if (token.len >= 2 and
            (token[0] == '"' or token[0] == '\'') and
            token[token.len - 1] == token[0])
            .{ .string = try unquoteToken(allocator, token) }
        else
            null,
        .tokens => error.InvalidArgument,
    };
}

fn unquoteToken(allocator: Allocator, token: []const u8) Error![]u8 {
    if (token.len < 2) return error.InvalidArgument;
    const quote = token[0];
    if ((quote != '"' and quote != '\'') or token[token.len - 1] != quote) return error.InvalidArgument;

    var output: std.ArrayList(u8) = .empty;
    errdefer output.deinit(allocator);
    var index: usize = 1;
    while (index + 1 < token.len) : (index += 1) {
        if (token[index] == '\\') {
            index += 1;
            if (index + 1 > token.len) return error.InvalidArgument;
            const escaped = switch (token[index]) {
                'n' => '\n',
                'r' => '\r',
                't' => '\t',
                '\\' => '\\',
                '"' => '"',
                '\'' => '\'',
                else => token[index],
            };
            try output.append(allocator, escaped);
            continue;
        }
        try output.append(allocator, token[index]);
    }
    return output.toOwnedSlice(allocator);
}

fn tokensToListValue(allocator: Allocator, tokens: []const []const u8) Error!value_mod.Value {
    const items = try allocator.alloc(value_mod.Value, tokens.len);
    var initialized: usize = 0;
    errdefer {
        for (items[0..initialized]) |*item| {
            item.deinit(allocator);
        }
        allocator.free(items);
    }

    for (tokens, 0..) |token, index| {
        items[index] = .{ .string = try allocator.dupe(u8, token) };
        initialized += 1;
    }
    return .{ .list = .{ .items = items } };
}

fn matchResult(allocator: Allocator, ok: bool, captures: []const Capture) Error!value_mod.Value {
    var captures_value = try capturesMapValue(allocator, captures);
    errdefer captures_value.deinit(allocator);

    const entries = try allocator.alloc(value_mod.MapEntry, 2);
    var initialized: usize = 0;
    errdefer {
        for (entries[0..initialized]) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    entries[0] = try ownedEntryTakeValue(allocator, "ok", .{ .boolean = ok });
    initialized += 1;
    entries[1] = try ownedEntryTakeValue(allocator, "captures", captures_value);
    captures_value = .void;
    initialized += 1;

    return .{ .map = .{ .entries = entries } };
}

fn capturesMapValue(allocator: Allocator, captures: []const Capture) Error!value_mod.Value {
    const entries = try allocator.alloc(value_mod.MapEntry, captures.len);
    var initialized: usize = 0;
    errdefer {
        for (entries[0..initialized]) |*entry| {
            entry.deinit(allocator);
        }
        allocator.free(entries);
    }

    for (captures, 0..) |capture, index| {
        entries[index] = try ownedEntryCloneValue(allocator, capture.name, capture.value);
        initialized += 1;
    }
    return .{ .map = .{ .entries = entries } };
}

fn ownedEntryCloneValue(allocator: Allocator, key: []const u8, value: value_mod.Value) Error!value_mod.MapEntry {
    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);
    return .{
        .key = owned_key,
        .value = try value.clone(allocator),
    };
}

fn ownedEntryTakeValue(allocator: Allocator, key: []const u8, value: value_mod.Value) Error!value_mod.MapEntry {
    const owned_key = try allocator.dupe(u8, key);
    errdefer allocator.free(owned_key);
    return .{
        .key = owned_key,
        .value = value,
    };
}

fn deinitCaptures(allocator: Allocator, captures: []Capture) void {
    for (captures) |*capture| {
        capture.deinit(allocator);
    }
}

fn tokensAreBalanced(tokens: []const []const u8) bool {
    var stack: [max_bracket_depth]u8 = undefined;
    var stack_len: usize = 0;
    for (tokens) |token| {
        if (matchingCloseBracket(token)) |close| {
            if (stack_len == stack.len) return false;
            stack[stack_len] = close;
            stack_len += 1;
            continue;
        }
        if (isCloseBracket(token)) {
            if (stack_len == 0) return false;
            if (token.len != 1 or stack[stack_len - 1] != token[0]) return false;
            stack_len -= 1;
        }
    }
    return stack_len == 0;
}

fn matchingCloseBracket(token: []const u8) ?u8 {
    if (token.len != 1) return null;
    return switch (token[0]) {
        '(' => ')',
        '[' => ']',
        '{' => '}',
        else => null,
    };
}

fn isCloseBracket(token: []const u8) bool {
    return token.len == 1 and switch (token[0]) {
        ')', ']', '}' => true,
        else => false,
    };
}

fn needsSpace(left: []const u8, right: []const u8) bool {
    if (isOpeningRenderToken(left)) return false;
    if (isClosingRenderToken(right)) return false;
    if (isTightRenderToken(left) or isTightRenderToken(right)) return false;
    return true;
}

fn isOpeningRenderToken(token: []const u8) bool {
    return token.len == 1 and switch (token[0]) {
        '(', '[', '{' => true,
        else => false,
    };
}

fn isClosingRenderToken(token: []const u8) bool {
    return token.len == 1 and switch (token[0]) {
        ',', ')', ']', '}', ';' => true,
        else => false,
    };
}

fn isTightRenderToken(token: []const u8) bool {
    return std.mem.eql(u8, token, ".") or
        std.mem.eql(u8, token, ":") or
        std.mem.eql(u8, token, "=") or
        std.mem.eql(u8, token, "==") or
        std.mem.eql(u8, token, "!=") or
        std.mem.eql(u8, token, "<") or
        std.mem.eql(u8, token, ">") or
        std.mem.eql(u8, token, "<=") or
        std.mem.eql(u8, token, ">=") or
        std.mem.eql(u8, token, "&&") or
        std.mem.eql(u8, token, "||") or
        std.mem.eql(u8, token, "<<") or
        std.mem.eql(u8, token, ">>") or
        std.mem.eql(u8, token, "+") or
        std.mem.eql(u8, token, "-") or
        std.mem.eql(u8, token, "*") or
        std.mem.eql(u8, token, "/") or
        std.mem.eql(u8, token, "%") or
        std.mem.eql(u8, token, "&") or
        std.mem.eql(u8, token, "|") or
        std.mem.eql(u8, token, "^") or
        std.mem.eql(u8, token, "~") or
        std.mem.eql(u8, token, "!");
}

fn isName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!(std.ascii.isAlphabetic(text[0]) or text[0] == '_')) return false;
    for (text[1..]) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '_')) return false;
    }
    return true;
}

test "tokenize and join ISA-shaped input" {
    var text = [_]u8{ 'm', 'o', 'v', ' ', 'r', 'a', 'x', ',', ' ', '[', 'r', 'b', 'x', '+', '4', ']' };
    var tokens = try tokenizeValue(std.testing.allocator, .{ .string = &text });
    defer tokens.deinit(std.testing.allocator);
    const list = try tokens.expectList();
    try std.testing.expectEqual(@as(usize, 8), list.items.len);
    try std.testing.expectEqualStrings("mov", try list.items[0].expectString());
    try std.testing.expectEqualStrings(",", try list.items[2].expectString());
    try std.testing.expectEqualStrings("[", try list.items[3].expectString());

    var rendered = try joinValue(std.testing.allocator, tokens);
    defer rendered.deinit(std.testing.allocator);
    try std.testing.expectEqualStrings("mov rax, [rbx+4]", try rendered.expectString());
}

test "match tokens captures typed fields and balanced token ranges" {
    var pattern_text = [_]u8{ '=', 'm', 'o', 'v', ' ', 'd', 's', 't', ':', 'n', 'a', 'm', 'e', ' ', '=', ',', ' ', 's', 'r', 'c', ':', 't', 'o', 'k', 'e', 'n', 's' };
    var input_text = [_]u8{ 'm', 'o', 'v', ' ', 'r', 'a', 'x', ',', ' ', '[', 'r', 'b', 'x', '+', '4', ']' };
    var result = try matchTokensValue(std.testing.allocator, .{ .string = &pattern_text }, .{ .string = &input_text });
    defer result.deinit(std.testing.allocator);

    const result_map = try result.expectMap();
    try std.testing.expect(try result_map.entryByKey("ok").?.value.expectBoolean());
    const captures = try result_map.entryByKey("captures").?.value.expectMap();
    try std.testing.expectEqualStrings("rax", try captures.entryByKey("dst").?.value.expectString());
    const src = try captures.entryByKey("src").?.value.expectList();
    try std.testing.expectEqual(@as(usize, 5), src.items.len);
    try std.testing.expectEqualStrings("[", try src.items[0].expectString());
    try std.testing.expectEqualStrings("]", try src.items[4].expectString());
}

test "match tokens captures integer and quoted tokens" {
    var int_pattern = [_]u8{ '=', 'l', 'o', 'a', 'd', ' ', 'r', 'd', ':', 'n', 'a', 'm', 'e', ' ', '=', ',', ' ', 'i', 'm', 'm', ':', 'i', 'n', 't' };
    var int_input = [_]u8{ 'l', 'o', 'a', 'd', ' ', 'r', '1', ',', ' ', '4', '2' };
    var int_result = try matchTokensValue(std.testing.allocator, .{ .string = &int_pattern }, .{ .string = &int_input });
    defer int_result.deinit(std.testing.allocator);
    const int_captures = try (try int_result.expectMap()).entryByKey("captures").?.value.expectMap();
    try std.testing.expectEqualStrings("r1", try int_captures.entryByKey("rd").?.value.expectString());
    try std.testing.expectEqual(@as(u64, 42), try int_captures.entryByKey("imm").?.value.expectInteger());

    var quoted_pattern = [_]u8{ '=', 'd', 'b', ' ', 't', 'e', 'x', 't', ':', 'q', 'u', 'o', 't', 'e', 'd' };
    var quoted_input = [_]u8{ 'd', 'b', ' ', '"', 'O', 'K', '"' };
    var quoted_result = try matchTokensValue(std.testing.allocator, .{ .string = &quoted_pattern }, .{ .string = &quoted_input });
    defer quoted_result.deinit(std.testing.allocator);
    const quoted_captures = try (try quoted_result.expectMap()).entryByKey("captures").?.value.expectMap();
    try std.testing.expectEqualStrings("OK", try quoted_captures.entryByKey("text").?.value.expectString());
}

test "typed capture mismatches are misses and token ranges backtrack" {
    const allocator = std.testing.allocator;
    const pattern_text = try allocator.dupe(u8, "prefix:tokens value:int");
    defer allocator.free(pattern_text);
    const input_text = try allocator.dupe(u8, "name 42");
    defer allocator.free(input_text);

    var result = try matchTokensValue(allocator, .{ .string = pattern_text }, .{ .string = input_text });
    defer result.deinit(allocator);
    const result_map = try result.expectMap();
    try std.testing.expect(try result_map.entryByKey("ok").?.value.expectBoolean());
    const captures = try result_map.entryByKey("captures").?.value.expectMap();
    const prefix = try captures.entryByKey("prefix").?.value.expectList();
    try std.testing.expectEqual(@as(usize, 1), prefix.items.len);
    try std.testing.expectEqualStrings("name", try prefix.items[0].expectString());
    try std.testing.expectEqual(@as(u64, 42), try captures.entryByKey("value").?.value.expectInteger());

    const miss_pattern = try allocator.dupe(u8, "value:int");
    defer allocator.free(miss_pattern);
    const miss_input = try allocator.dupe(u8, "name");
    defer allocator.free(miss_input);
    var miss = try matchTokensValue(allocator, .{ .string = miss_pattern }, .{ .string = miss_input });
    defer miss.deinit(allocator);
    try std.testing.expect(!try (try miss.expectMap()).entryByKey("ok").?.value.expectBoolean());
}

test "balanced token ranges accept comparison operators" {
    const allocator = std.testing.allocator;
    const pattern_text = try allocator.dupe(u8, "expr:tokens");
    defer allocator.free(pattern_text);
    const input_text = try allocator.dupe(u8, "left < right");
    defer allocator.free(input_text);

    var result = try matchTokensValue(allocator, .{ .string = pattern_text }, .{ .string = input_text });
    defer result.deinit(allocator);
    const result_map = try result.expectMap();
    try std.testing.expect(try result_map.entryByKey("ok").?.value.expectBoolean());
    const captures = try result_map.entryByKey("captures").?.value.expectMap();
    var rendered = try joinValue(allocator, captures.entryByKey("expr").?.value);
    defer rendered.deinit(allocator);
    try std.testing.expectEqualStrings("left<right", try rendered.expectString());
}

test "logical operators remain single literal tokens" {
    const allocator = std.testing.allocator;
    const input_text = try allocator.dupe(u8, "left && middle || right");
    defer allocator.free(input_text);

    var tokens = try tokenizeValue(allocator, .{ .string = input_text });
    defer tokens.deinit(allocator);
    const token_list = try tokens.expectList();
    try std.testing.expectEqual(@as(usize, 5), token_list.items.len);
    try std.testing.expectEqualStrings("&&", try token_list.items[1].expectString());
    try std.testing.expectEqualStrings("||", try token_list.items[3].expectString());

    const pattern_text = try allocator.dupe(u8, "left:name =&& middle:name =|| right:name");
    defer allocator.free(pattern_text);
    var result = try matchTokensValue(allocator, .{ .string = pattern_text }, .{ .string = input_text });
    defer result.deinit(allocator);
    try std.testing.expect(try (try result.expectMap()).entryByKey("ok").?.value.expectBoolean());
}

test "match tokens reports misses and rejects duplicate captures" {
    var pattern_text = [_]u8{ '=', 'a', 'd', 'd', ' ', 'd', 's', 't', ':', 'n', 'a', 'm', 'e' };
    var input_text = [_]u8{ 'm', 'o', 'v', ' ', 'r', 'a', 'x' };
    var result = try matchTokensValue(std.testing.allocator, .{ .string = &pattern_text }, .{ .string = &input_text });
    defer result.deinit(std.testing.allocator);
    const result_map = try result.expectMap();
    try std.testing.expect(!try result_map.entryByKey("ok").?.value.expectBoolean());

    var duplicate_pattern = [_]u8{ 'a', ':', 'n', 'a', 'm', 'e', ' ', 'a', ':', 't', 'o', 'k', 'e', 'n' };
    try std.testing.expectError(error.InvalidArgument, matchTokensValue(std.testing.allocator, .{ .string = &duplicate_pattern }, .{ .string = &input_text }));
}
