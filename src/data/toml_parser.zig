const std = @import("std");

const Allocator = std.mem.Allocator;

pub const ParseError = error{
    OutOfMemory,
    Syntax,
    InvalidUtf8,
    Overflow,
    DuplicateKey,
};

pub const Node = struct {
    tag: Tag,
    data: TomlValue,
    line: usize,
    col: usize,

    pub const Tag = enum {
        string,
        int64,
        fp64,
        boolean,
        timestamp,
        array,
        table,
    };

    pub const TomlValue = union(enum) {
        string: []const u8,
        int64: i64,
        fp64: f64,
        boolean: bool,
        timestamp: []const u8,
        array: []Node,
        table: []Entry,
    };

    pub const Entry = struct {
        key: []const u8,
        value: Node,
    };
};

pub const ParseResult = struct {
    node: Node,
    arena: std.heap.ArenaAllocator,

    pub fn deinit(self: *ParseResult) void {
        self.arena.deinit();
    }
};

pub fn parse(allocator: Allocator, source: []const u8) ParseError!ParseResult {
    var arena = std.heap.ArenaAllocator.init(allocator);
    errdefer arena.deinit();
    const aa = arena.allocator();

    var p = Parser{
        .source = source,
        .pos = 0,
        .line = 1,
        .col = 1,
    };
    const node = try p.parseDocument(aa);
    return ParseResult{ .node = node, .arena = arena };
}

const StoreValue = union(enum) {
    leaf: Node,
    table: *TableStore,
    array_table: std.ArrayListUnmanaged(*TableStore),
};

const StoreEntry = struct {
    key: []const u8,
    value: StoreValue,
};

const TableStore = struct {
    entries: std.ArrayListUnmanaged(StoreEntry),
};

const Parser = struct {
    source: []const u8,
    pos: usize,
    line: usize,
    col: usize,

    fn parseDocument(self: *Parser, aa: Allocator) ParseError!Node {
        var root_store = TableStore{ .entries = .empty };
        var current: *TableStore = &root_store;

        while (true) {
            self.skipWhitespaceAndNewlines();
            if (self.pos >= self.source.len) break;

            const ch = self.peek();

            if (ch == '#') {
                self.skipComment();
                continue;
            }

            if (ch == '[') {
                const is_double = self.pos + 1 < self.source.len and self.source[self.pos + 1] == '[';
                if (is_double) {
                    self.pos += 2;
                    self.col += 2;
                    self.skipWhitespace();
                    const path = try self.parseKeyPath(aa);
                    self.skipWhitespace();
                    try self.expectChar(']');
                    try self.expectChar(']');
                    current = try resolveArrayTableStore(aa, &root_store, path);
                } else {
                    self.pos += 1;
                    self.col += 1;
                    self.skipWhitespace();
                    const path = try self.parseKeyPath(aa);
                    self.skipWhitespace();
                    try self.expectChar(']');
                    current = try resolveTableStore(aa, &root_store, path);
                }
                self.skipWhitespace();
                if (self.pos < self.source.len and self.peek() == '#') {
                    self.skipComment();
                }
                continue;
            }

            const key = try self.parseKey(aa);
            self.skipWhitespace();
            try self.expectChar('=');
            self.skipWhitespace();
            const value = try self.parseValue(aa);

            if (std.mem.lastIndexOfScalar(u8, key, '.')) |dot| {
                const parent_path = key[0..dot];
                const last_key = key[dot + 1 ..];
                const store = try resolveTableStore(aa, current, parent_path);
                const existing = findInStore(store, last_key);
                if (existing) |entry| {
                    entry.value = .{ .leaf = value };
                } else {
                    try store.entries.append(aa, .{ .key = last_key, .value = .{ .leaf = value } });
                }
            } else {
                const existing = findInStore(current, key);
                if (existing) |entry| {
                    entry.value = .{ .leaf = value };
                } else {
                    try current.entries.append(aa, .{ .key = key, .value = .{ .leaf = value } });
                }
            }

            self.skipWhitespace();
            if (self.pos < self.source.len and self.peek() == '#') {
                self.skipComment();
            }
        }

        return self.storeToNode(aa, &root_store, 1, 1);
    }

    fn storeToNode(
        self: *Parser,
        aa: Allocator,
        store: *TableStore,
        line: usize,
        col: usize,
    ) ParseError!Node {
        const count = store.entries.items.len;
        const entries = try aa.alloc(Node.Entry, count);
        for (store.entries.items, 0..) |src, i| {
            const val: Node = switch (src.value) {
                .leaf => |node| try self.convertNode(aa, &node),
                .table => |sub| try self.storeToNode(aa, sub, 0, 0),
                .array_table => |arr| blk: {
                    const nodes = try aa.alloc(Node, arr.items.len);
                    for (arr.items, 0..) |sub_store, j| {
                        nodes[j] = try self.storeToNode(aa, sub_store, 0, 0);
                    }
                    break :blk Node{ .tag = .array, .data = .{ .array = nodes }, .line = 0, .col = 0 };
                },
            };
            entries[i] = .{ .key = src.key, .value = val };
        }
        return Node{ .tag = .table, .data = .{ .table = entries }, .line = line, .col = col };
    }

    fn convertNode(self: *Parser, aa: Allocator, node: *const Node) ParseError!Node {
        switch (node.tag) {
            .string, .int64, .fp64, .boolean, .timestamp => return node.*,
            .array => {
                const items = try aa.alloc(Node, node.data.array.len);
                for (node.data.array, 0..) |*item, i| items[i] = try self.convertNode(aa, item);
                return Node{ .tag = .array, .data = .{ .array = items }, .line = node.line, .col = node.col };
            },
            .table => {
                const count = node.data.table.len;
                const entries = try aa.alloc(Node.Entry, count);
                for (node.data.table, 0..) |*entry, i| {
                    entries[i] = .{ .key = entry.key, .value = try self.convertNode(aa, &entry.value) };
                }
                return Node{ .tag = .table, .data = .{ .table = entries }, .line = node.line, .col = node.col };
            },
        }
    }

    fn parseValue(self: *Parser, aa: Allocator) ParseError!Node {
        self.skipWhitespace();
        if (self.pos >= self.source.len) return error.Syntax;

        const line = self.line;
        const col = self.col;
        const ch = self.peek();

        switch (ch) {
            '"' => return Node{ .tag = .string, .data = .{ .string = try self.parseBasicString(aa) }, .line = line, .col = col },
            '\'' => return Node{ .tag = .string, .data = .{ .string = try self.parseLiteralString(aa) }, .line = line, .col = col },
            't', 'f' => return Node{ .tag = .boolean, .data = .{ .boolean = try self.parseBool() }, .line = line, .col = col },
            '[' => return self.parseArray(aa, line, col),
            '{' => return self.parseInlineTable(aa, line, col),
            '+', '-', '0'...'9' => return self.parseNumberOrDate(aa, line, col),
            'i' => {
                if (self.pos + 2 < self.source.len and std.mem.eql(u8, self.source[self.pos..][0..3], "inf")) {
                    self.pos += 3;
                    self.col += 3;
                    return Node{ .tag = .fp64, .data = .{ .fp64 = std.math.inf(f64) }, .line = line, .col = col };
                }
                return error.Syntax;
            },
            'n' => {
                if (self.pos + 2 < self.source.len and std.mem.eql(u8, self.source[self.pos..][0..3], "nan")) {
                    self.pos += 3;
                    self.col += 3;
                    return Node{ .tag = .fp64, .data = .{ .fp64 = std.math.nan(f64) }, .line = line, .col = col };
                }
                return error.Syntax;
            },
            else => return error.Syntax,
        }
    }

    fn parseBool(self: *Parser) ParseError!bool {
        if (self.pos + 3 < self.source.len and std.mem.eql(u8, self.source[self.pos..][0..4], "true")) {
            self.pos += 4;
            self.col += 4;
            return true;
        }
        if (self.pos + 4 < self.source.len and std.mem.eql(u8, self.source[self.pos..][0..5], "false")) {
            self.pos += 5;
            self.col += 5;
            return false;
        }
        return error.Syntax;
    }

    fn parseNumberOrDate(self: *Parser, aa: Allocator, line: usize, col: usize) ParseError!Node {
        const s_line = line;
        const s_col = col;

        if (self.parseInfNan()) |inf_nan| {
            return Node{ .tag = .fp64, .data = .{ .fp64 = inf_nan }, .line = s_line, .col = s_col };
        }

        const raw = self.scanValueText();
        if (raw.len == 0) return error.Syntax;

        if (tryParseDate(raw)) |ts| {
            return Node{ .tag = .timestamp, .data = .{ .timestamp = try aa.dupe(u8, ts) }, .line = s_line, .col = s_col };
        }
        if (tryParseHexInt(raw)) |val| {
            return Node{ .tag = .int64, .data = .{ .int64 = val }, .line = s_line, .col = s_col };
        }
        if (tryParseOctInt(raw)) |val| {
            return Node{ .tag = .int64, .data = .{ .int64 = val }, .line = s_line, .col = s_col };
        }
        if (tryParseBinInt(raw)) |val| {
            return Node{ .tag = .int64, .data = .{ .int64 = val }, .line = s_line, .col = s_col };
        }
        if (isFloatString(raw)) {
            const val = tryParseFloat(raw) orelse return error.Overflow;
            return Node{ .tag = .fp64, .data = .{ .fp64 = val }, .line = s_line, .col = s_col };
        }
        if (isIntString(raw)) {
            const val = tryParseInt(raw) orelse return error.Overflow;
            return Node{ .tag = .int64, .data = .{ .int64 = val }, .line = s_line, .col = s_col };
        }
        return error.Syntax;
    }

    fn parseInfNan(self: *Parser) ?f64 {
        if (self.pos + 2 < self.source.len) {
            const slice = self.source[self.pos..];
            if (slice.len >= 4 and (slice[0] == '+' or slice[0] == '-')) {
                const sign = slice[0];
                const rest = slice[1..];
                if (std.mem.eql(u8, rest[0..3], "inf")) {
                    self.pos += 4;
                    self.col += 4;
                    return if (sign == '-') -std.math.inf(f64) else std.math.inf(f64);
                }
                if (std.mem.eql(u8, rest[0..3], "nan")) {
                    self.pos += 4;
                    self.col += 4;
                    return if (sign == '-') -std.math.nan(f64) else std.math.nan(f64);
                }
                return null;
            }
            if (std.mem.eql(u8, slice[0..3], "inf")) {
                self.pos += 3;
                self.col += 3;
                return std.math.inf(f64);
            }
            if (std.mem.eql(u8, slice[0..3], "nan")) {
                self.pos += 3;
                self.col += 3;
                return std.math.nan(f64);
            }
        }
        return null;
    }

    fn scanValueText(self: *Parser) []const u8 {
        const start = self.pos;
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                '0'...'9', '+', '-', '.', 'e', 'E', 'x', 'X', 'o', 'O', 'b', 'B', '_', ':', 'T', 't', 'Z', 'z', 'i', 'n', 'f', 'a', 'N', 'A', 'C', 'D', 'F', 'c', 'd' => {
                    self.pos += 1;
                    self.col += 1;
                },
                else => break,
            }
        }
        return self.source[start..self.pos];
    }

    fn parseArray(self: *Parser, aa: Allocator, line: usize, col: usize) ParseError!Node {
        try self.expectChar('[');
        self.skipWhitespaceNewlinesAndComments();

        if (self.pos < self.source.len and self.peek() == ']') {
            self.pos += 1;
            self.col += 1;
            return Node{ .tag = .array, .data = .{ .array = &.{} }, .line = line, .col = col };
        }

        var items: std.ArrayListUnmanaged(Node) = .empty;
        while (true) {
            self.skipWhitespaceNewlinesAndComments();
            const value = try self.parseValue(aa);
            try items.append(aa, value);
            self.skipWhitespaceNewlinesAndComments();

            if (self.pos < self.source.len and self.peek() == ',') {
                self.pos += 1;
                self.col += 1;
                self.skipWhitespaceNewlinesAndComments();
                if (self.pos < self.source.len and self.peek() == ']') {
                    self.pos += 1;
                    self.col += 1;
                    break;
                }
            } else if (self.pos < self.source.len and self.peek() == ']') {
                self.pos += 1;
                self.col += 1;
                break;
            } else {
                return error.Syntax;
            }
        }

        const owned = try aa.alloc(Node, items.items.len);
        @memcpy(owned, items.items);
        return Node{ .tag = .array, .data = .{ .array = owned }, .line = line, .col = col };
    }

    fn parseInlineTable(self: *Parser, aa: Allocator, line: usize, col: usize) ParseError!Node {
        try self.expectChar('{');
        self.skipWhitespace();

        var entries: std.ArrayListUnmanaged(Node.Entry) = .empty;

        if (self.pos < self.source.len and self.peek() == '}') {
            self.pos += 1;
            self.col += 1;
            return Node{ .tag = .table, .data = .{ .table = &.{} }, .line = line, .col = col };
        }

        while (true) {
            self.skipWhitespace();
            const key = try self.parseKey(aa);
            self.skipWhitespace();
            try self.expectChar('=');
            self.skipWhitespace();
            const value = try self.parseValue(aa);
            try entries.append(aa, .{ .key = key, .value = value });
            self.skipWhitespace();

            if (self.pos < self.source.len and self.peek() == ',') {
                self.pos += 1;
                self.col += 1;
            } else if (self.pos < self.source.len and self.peek() == '}') {
                self.pos += 1;
                self.col += 1;
                break;
            } else {
                return error.Syntax;
            }
        }

        const owned = try aa.alloc(Node.Entry, entries.items.len);
        @memcpy(owned, entries.items);
        return Node{ .tag = .table, .data = .{ .table = owned }, .line = line, .col = col };
    }

    fn emitUtf8(result: *std.ArrayListUnmanaged(u8), aa: Allocator, code: u21) !void {
        if (code < 0x80) {
            try result.append(aa, @as(u8, @intCast(code)));
        } else if (code < 0x800) {
            try result.append(aa, @as(u8, @intCast(0xC0 | (code >> 6))));
            try result.append(aa, @as(u8, @intCast(0x80 | (code & 0x3F))));
        } else if (code < 0x10000) {
            try result.append(aa, @as(u8, @intCast(0xE0 | (code >> 12))));
            try result.append(aa, @as(u8, @intCast(0x80 | ((code >> 6) & 0x3F))));
            try result.append(aa, @as(u8, @intCast(0x80 | (code & 0x3F))));
        } else {
            try result.append(aa, @as(u8, @intCast(0xF0 | (code >> 18))));
            try result.append(aa, @as(u8, @intCast(0x80 | ((code >> 12) & 0x3F))));
            try result.append(aa, @as(u8, @intCast(0x80 | ((code >> 6) & 0x3F))));
            try result.append(aa, @as(u8, @intCast(0x80 | (code & 0x3F))));
        }
    }

    fn parseBasicString(self: *Parser, aa: Allocator) ParseError![]const u8 {
        try self.expectChar('"');
        if (self.pos + 2 <= self.source.len and self.source[self.pos] == '"' and self.source[self.pos + 1] == '"') {
            self.pos += 2;
            self.col += 2;
            return self.parseMultilineBasicString(aa);
        }

        var result: std.ArrayListUnmanaged(u8) = .empty;
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '"') {
                self.pos += 1;
                self.col += 1;
                return result.toOwnedSlice(aa);
            }
            if (ch == '\n' or ch == '\r') return error.Syntax;
            if (ch == '\\') {
                self.pos += 1;
                self.col += 1;
                if (self.pos >= self.source.len) return error.Syntax;
                const esc = self.source[self.pos];
                self.pos += 1;
                self.col += 1;
                switch (esc) {
                    'b' => try result.append(aa, 0x08),
                    't' => try result.append(aa, '\t'),
                    'n' => try result.append(aa, '\n'),
                    'f' => try result.append(aa, 0x0c),
                    'r' => try result.append(aa, '\r'),
                    '"' => try result.append(aa, '"'),
                    '\\' => try result.append(aa, '\\'),
                    'u' => {
                        const code = try self.parseUnicodeEscape(4);
                        try emitUtf8(&result, aa, code);
                    },
                    'U' => {
                        const code = try self.parseUnicodeEscape(8);
                        try emitUtf8(&result, aa, code);
                    },
                    else => return error.Syntax,
                }
            } else {
                self.pos += 1;
                self.col += 1;
                try result.append(aa, ch);
            }
        }
        return error.Syntax;
    }

    fn parseMultilineBasicString(self: *Parser, aa: Allocator) ParseError![]const u8 {
        var result: std.ArrayListUnmanaged(u8) = .empty;
        if (self.pos < self.source.len and (self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
            if (self.source[self.pos] == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') self.pos += 2 else self.pos += 1;
            self.line += 1;
            self.col = 1;
        }
        while (self.pos < self.source.len) {
            const ch = self.source[self.pos];
            if (ch == '"') {
                if (self.pos + 2 <= self.source.len and self.source[self.pos + 1] == '"' and self.source[self.pos + 2] == '"') {
                    self.pos += 3;
                    self.col += 3;
                    return result.toOwnedSlice(aa);
                }
                self.pos += 1;
                self.col += 1;
                try result.append(aa, '"');
                continue;
            }
            if (ch == '\\') {
                self.pos += 1;
                self.col += 1;
                if (self.pos >= self.source.len) return error.Syntax;
                if (self.source[self.pos] == '\n' or self.source[self.pos] == '\r') {
                    if (self.source[self.pos] == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') self.pos += 2 else self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                    while (self.pos < self.source.len and (self.source[self.pos] == ' ' or self.source[self.pos] == '\t' or self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
                        if (self.source[self.pos] == '\n' or self.source[self.pos] == '\r') {
                            if (self.source[self.pos] == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') self.pos += 1;
                            self.line += 1;
                            self.col = 1;
                        }
                        self.pos += 1;
                        self.col += 1;
                    }
                    continue;
                }
                switch (self.source[self.pos]) {
                    'b' => try result.append(aa, 0x08),
                    't' => try result.append(aa, '\t'),
                    'n' => try result.append(aa, '\n'),
                    'f' => try result.append(aa, 0x0c),
                    'r' => try result.append(aa, '\r'),
                    '"' => try result.append(aa, '"'),
                    '\\' => try result.append(aa, '\\'),
                    'u' => {
                        self.pos += 1;
                        self.col += 1;
                        const code = try self.parseUnicodeEscape(4);
                        try emitUtf8(&result, aa, code);
                        self.pos -= 1;
                        self.col -= 1;
                    },
                    'U' => {
                        self.pos += 1;
                        self.col += 1;
                        const code = try self.parseUnicodeEscape(8);
                        try emitUtf8(&result, aa, code);
                        self.pos -= 1;
                        self.col -= 1;
                    },
                    else => return error.Syntax,
                }
                self.pos += 1;
                self.col += 1;
                continue;
            }
            if (ch == '\r') {
                self.pos += 1;
                self.line += 1;
                self.col = 1;
                try result.append(aa, '\r');
                continue;
            }
            self.pos += 1;
            if (ch == '\n') {
                self.line += 1;
                self.col = 1;
            } else {
                self.col += 1;
            }
            try result.append(aa, ch);
        }
        return error.Syntax;
    }

    fn parseLiteralString(self: *Parser, aa: Allocator) ParseError![]const u8 {
        try self.expectChar('\'');
        if (self.pos + 2 <= self.source.len and self.source[self.pos] == '\'' and self.source[self.pos + 1] == '\'') {
            self.pos += 2;
            self.col += 2;
            return self.parseMultilineLiteralString(aa);
        }
        const start = self.pos;
        while (self.pos < self.source.len) {
            if (self.source[self.pos] == '\'') {
                const slice = self.source[start..self.pos];
                self.pos += 1;
                self.col += 1;
                return try aa.dupe(u8, slice);
            }
            if (self.source[self.pos] == '\n' or self.source[self.pos] == '\r') return error.Syntax;
            self.pos += 1;
            self.col += 1;
        }
        return error.Syntax;
    }

    fn parseMultilineLiteralString(self: *Parser, aa: Allocator) ParseError![]const u8 {
        if (self.pos < self.source.len and (self.source[self.pos] == '\n' or self.source[self.pos] == '\r')) {
            if (self.source[self.pos] == '\r' and self.pos + 1 < self.source.len and self.source[self.pos + 1] == '\n') self.pos += 2 else self.pos += 1;
            self.line += 1;
            self.col = 1;
        }
        const start = self.pos;
        var end = self.pos;
        while (end < self.source.len) {
            if (self.source[end] == '\'') {
                if (end + 2 <= self.source.len and self.source[end + 1] == '\'' and self.source[end + 2] == '\'') {
                    const slice = self.source[start..end];
                    self.pos = end + 3;
                    self.col += (end + 3) - start;
                    return try aa.dupe(u8, slice);
                }
            }
            end += 1;
        }
        return error.Syntax;
    }

    fn parseUnicodeEscape(self: *Parser, digits: usize) ParseError!u21 {
        var code: u21 = 0;
        var i: usize = 0;
        while (i < digits) : (i += 1) {
            if (self.pos >= self.source.len) return error.Syntax;
            const ch = self.source[self.pos];
            self.pos += 1;
            self.col += 1;
            code <<= 4;
            code |= switch (ch) {
                '0'...'9' => ch - '0',
                'a'...'f' => ch - 'a' + 10,
                'A'...'F' => ch - 'A' + 10,
                else => return error.Syntax,
            };
        }
        if (code >= 0xD800 and code <= 0xDFFF) return error.Syntax;
        if (code > 0x10FFFF) return error.Syntax;
        return code;
    }

    fn parseKey(self: *Parser, aa: Allocator) ParseError![]const u8 {
        var segments: std.ArrayListUnmanaged([]const u8) = .empty;
        while (true) {
            const key = try self.parseSimpleKey(aa);
            try segments.append(aa, key);
            self.skipWhitespace();
            if (self.pos < self.source.len and self.peek() == '.') {
                self.pos += 1;
                self.col += 1;
                self.skipWhitespace();
            } else break;
        }
        if (segments.items.len == 1) return segments.items[0];
        var joined = try std.ArrayList(u8).initCapacity(aa, 64);
        for (segments.items, 0..) |seg, i| {
            if (i > 0) try joined.append(aa, '.');
            try joined.appendSlice(aa, seg);
        }
        return joined.toOwnedSlice(aa);
    }

    fn parseKeyPath(self: *Parser, aa: Allocator) ParseError![]const u8 {
        var segments: std.ArrayListUnmanaged([]const u8) = .empty;
        while (true) {
            self.skipWhitespace();
            if (self.pos >= self.source.len) break;
            if (self.peek() == ']') break;
            const key = try self.parseSimpleKey(aa);
            try segments.append(aa, key);
            self.skipWhitespace();
            if (self.pos < self.source.len and self.peek() == '.') {
                self.pos += 1;
                self.col += 1;
            } else break;
        }
        var joined = try std.ArrayList(u8).initCapacity(aa, 64);
        for (segments.items, 0..) |seg, i| {
            if (i > 0) try joined.append(aa, '.');
            try joined.appendSlice(aa, seg);
        }
        return joined.toOwnedSlice(aa);
    }

    fn parseSimpleKey(self: *Parser, aa: Allocator) ParseError![]const u8 {
        if (self.pos >= self.source.len) return error.Syntax;
        return switch (self.peek()) {
            '"' => self.parseBasicString(aa),
            '\'' => self.parseLiteralString(aa),
            else => self.parseBareKey(),
        };
    }

    fn parseBareKey(self: *Parser) []const u8 {
        const start = self.pos;
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                'A'...'Z', 'a'...'z', '0'...'9', '-', '_' => {
                    self.pos += 1;
                    self.col += 1;
                },
                else => break,
            }
        }
        return self.source[start..self.pos];
    }

    fn expectChar(self: *Parser, expected: u8) ParseError!void {
        if (self.pos >= self.source.len or self.source[self.pos] != expected) return error.Syntax;
        self.pos += 1;
        self.col += 1;
    }

    fn peek(self: *Parser) u8 {
        return self.source[self.pos];
    }

    fn skipWhitespace(self: *Parser) void {
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                ' ', '\t' => {
                    self.pos += 1;
                    self.col += 1;
                },
                else => break,
            }
        }
    }

    fn skipWhitespaceAndNewlines(self: *Parser) void {
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                ' ', '\t' => {
                    self.pos += 1;
                    self.col += 1;
                },
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                '\r' => {
                    self.pos += 1;
                    if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                else => break,
            }
        }
    }

    fn skipWhitespaceNewlinesAndComments(self: *Parser) void {
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                ' ', '\t' => {
                    self.pos += 1;
                    self.col += 1;
                },
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                '\r' => {
                    self.pos += 1;
                    if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                },
                '#' => {
                    self.skipComment();
                },
                else => break,
            }
        }
    }

    fn skipComment(self: *Parser) void {
        while (self.pos < self.source.len) {
            switch (self.source[self.pos]) {
                '\n' => {
                    self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                    return;
                },
                '\r' => {
                    self.pos += 1;
                    if (self.pos < self.source.len and self.source[self.pos] == '\n') self.pos += 1;
                    self.line += 1;
                    self.col = 1;
                    return;
                },
                else => {
                    self.pos += 1;
                    self.col += 1;
                },
            }
        }
    }
};

fn findInStore(store: *TableStore, key: []const u8) ?*StoreEntry {
    for (store.entries.items) |*entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry;
    }
    return null;
}

fn resolveTableStore(aa: Allocator, root: *TableStore, path: []const u8) ParseError!*TableStore {
    var current = root;
    var start: usize = 0;
    while (start < path.len) {
        while (start < path.len and path[start] == '.') start += 1;
        if (start >= path.len) break;
        var end = start;
        while (end < path.len and path[end] != '.') end += 1;
        const segment = path[start..end];
        start = end;
        current = try navigateStore(aa, current, segment);
    }
    return current;
}

fn navigateStore(aa: Allocator, current: *TableStore, segment: []const u8) ParseError!*TableStore {
    const found = findInStore(current, segment);
    if (found) |entry| {
        switch (entry.value) {
            .table => return entry.value.table,
            .array_table => {
                const arr = &entry.value.array_table;
                if (arr.items.len == 0) {
                    const sub = try aa.create(TableStore);
                    sub.* = TableStore{ .entries = .empty };
                    try arr.append(aa, sub);
                    return sub;
                }
                return arr.items[arr.items.len - 1];
            },
            .leaf => return error.DuplicateKey,
        }
    }
    const sub = try aa.create(TableStore);
    sub.* = TableStore{ .entries = .empty };
    try current.entries.append(aa, .{ .key = segment, .value = .{ .table = sub } });
    return sub;
}

fn resolveArrayTableStore(aa: Allocator, root: *TableStore, path: []const u8) ParseError!*TableStore {
    var last_dot: ?usize = null;
    var i: usize = 0;
    while (i < path.len) {
        if (path[i] == '.') last_dot = i;
        i += 1;
    }

    const parent = if (last_dot) |idx|
        try resolveTableStore(aa, root, path[0..idx])
    else
        root;
    const segment = if (last_dot) |idx| path[idx + 1 ..] else path;

    const found = findInStore(parent, segment);
    if (found) |entry| {
        switch (entry.value) {
            .array_table => {
                const arr = &entry.value.array_table;
                const sub = try aa.create(TableStore);
                sub.* = TableStore{ .entries = .empty };
                try arr.append(aa, sub);
                return sub;
            },
            else => return error.DuplicateKey,
        }
    }

    var arr: std.ArrayListUnmanaged(*TableStore) = .empty;
    const sub = try aa.create(TableStore);
    sub.* = TableStore{ .entries = .empty };
    try arr.append(aa, sub);
    try parent.entries.append(aa, .{ .key = segment, .value = .{ .array_table = arr } });
    return sub;
}

fn tryParseDate(raw: []const u8) ?[]const u8 {
    // Local time: hh:mm:ss or hh:mm:ss.ffffff
    if (raw.len >= 5 and std.ascii.isDigit(raw[0]) and std.ascii.isDigit(raw[1]) and raw[2] == ':') {
        var i: usize = 3;
        if (i + 2 > raw.len or !std.ascii.isDigit(raw[i]) or !std.ascii.isDigit(raw[i + 1])) return null;
        i += 2;
        if (i >= raw.len) return raw;
        if (raw[i] != ':') return null;
        i += 1;
        if (i + 2 > raw.len or !std.ascii.isDigit(raw[i]) or !std.ascii.isDigit(raw[i + 1])) return null;
        i += 2;
        if (i < raw.len and raw[i] == '.') {
            i += 1;
            while (i < raw.len and std.ascii.isDigit(raw[i])) i += 1;
        }
        if (i == raw.len) return raw;
        return null;
    }

    // Full date/datetime: yyyy[-mm[-dd]][T hh:mm:ss[.fff]][ Z|+hh:mm|-hh:mm]
    if (raw.len < 10) return null;
    var i: usize = 0;
    if (i + 4 > raw.len or !isDigit4(raw[i..])) return null;
    i += 4;
    var has_date = false;
    var has_time = false;
    if (i < raw.len and raw[i] == '-') {
        i += 1;
        if (i + 2 > raw.len) return null;
        i += 2;
        if (i < raw.len and raw[i] == '-') {
            i += 1;
            if (i + 2 > raw.len) return null;
            i += 2;
            has_date = true;
        }
    }
    if (i < raw.len and (raw[i] == 'T' or raw[i] == 't')) {
        i += 1;
        has_time = true;
        if (i + 8 > raw.len) return null;
        i += 2;
        if (i >= raw.len or raw[i] != ':') return null;
        i += 1;
        i += 2;
        if (i >= raw.len or raw[i] != ':') return null;
        i += 1;
        i += 2;
        if (i < raw.len and raw[i] == '.') {
            i += 1;
            while (i < raw.len and std.ascii.isDigit(raw[i])) i += 1;
        }
    }
    if (i < raw.len and (raw[i] == 'Z' or raw[i] == 'z')) {
        i += 1;
    } else if (i < raw.len and (raw[i] == '+' or raw[i] == '-')) {
        i += 1;
        if (i + 5 > raw.len) return null;
        i += 2;
        if (i >= raw.len or raw[i] != ':') return null;
        i += 1;
        i += 2;
    }
    if (i != raw.len) return null;
    if (!has_date and !has_time) return null;
    return raw;
}

fn tryParseHexInt(raw: []const u8) ?i64 {
    if (raw.len < 3 or raw[0] != '0' or (raw[1] != 'x' and raw[1] != 'X')) return null;
    var val: u64 = 0;
    for (raw[2..]) |ch| {
        if (ch == '_') continue;
        const d = switch (ch) {
            '0'...'9' => ch - '0',
            'a'...'f' => ch - 'a' + 10,
            'A'...'F' => ch - 'A' + 10,
            else => return null,
        };
        if (val > (std.math.maxInt(u64) >> 4)) return null;
        val = (val << 4) | d;
    }
    return if (val > std.math.maxInt(i64)) null else @as(i64, @intCast(val));
}

fn tryParseOctInt(raw: []const u8) ?i64 {
    if (raw.len < 3 or raw[0] != '0' or (raw[1] != 'o' and raw[1] != 'O')) return null;
    var val: u64 = 0;
    for (raw[2..]) |ch| {
        if (ch == '_') continue;
        const d = switch (ch) {
            '0'...'7' => ch - '0',
            else => return null,
        };
        if (val > (std.math.maxInt(u64) >> 3)) return null;
        val = (val << 3) | d;
    }
    return if (val > std.math.maxInt(i64)) null else @as(i64, @intCast(val));
}

fn tryParseBinInt(raw: []const u8) ?i64 {
    if (raw.len < 3 or raw[0] != '0' or (raw[1] != 'b' and raw[1] != 'B')) return null;
    var val: u64 = 0;
    for (raw[2..]) |ch| {
        if (ch == '_') continue;
        const d = switch (ch) {
            '0', '1' => ch - '0',
            else => return null,
        };
        if (val > (std.math.maxInt(u64) >> 1)) return null;
        val = (val << 1) | d;
    }
    return if (val > std.math.maxInt(i64)) null else @as(i64, @intCast(val));
}

fn isFloatString(raw: []const u8) bool {
    for (raw) |ch| {
        switch (ch) {
            '.', 'e', 'E' => return true,
            else => {},
        }
    }
    return false;
}

fn isIntString(raw: []const u8) bool {
    if (raw.len == 0) return false;
    var i: usize = 0;
    if (raw[0] == '+' or raw[0] == '-') i += 1;
    if (i >= raw.len) return false;
    if (raw[i] == '0' and i + 1 < raw.len) {
        switch (raw[i + 1]) {
            'x', 'X', 'o', 'O', 'b', 'B' => return false,
            else => {},
        }
    }
    var has_digit = false;
    while (i < raw.len) {
        const ch = raw[i];
        if (ch == '_') {
            i += 1;
            continue;
        }
        if (!std.ascii.isDigit(ch)) return false;
        has_digit = true;
        i += 1;
    }
    return has_digit;
}

fn tryParseInt(raw: []const u8) ?i64 {
    const trimmed = std.mem.trim(u8, raw, "_");
    return if (trimmed.len == 0) null else std.fmt.parseInt(i64, trimmed, 10) catch null;
}

fn tryParseFloat(raw: []const u8) ?f64 {
    const trimmed = std.mem.trim(u8, raw, "_");
    return if (trimmed.len == 0) null else std.fmt.parseFloat(f64, trimmed) catch null;
}

fn isDigit4(s: []const u8) bool {
    return s.len >= 4 and std.ascii.isDigit(s[0]) and std.ascii.isDigit(s[1]) and std.ascii.isDigit(s[2]) and std.ascii.isDigit(s[3]);
}

fn getEntry(node: Node, key: []const u8) ?Node {
    if (node.tag != .table) return null;
    for (node.data.table) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry.value;
    }
    return null;
}

test "toml parser: basic key-value" {
    const testing = std.testing;
    const source =
        \\title = "TOML Example"
        \\name = "Aero"
        \\weight = 40
        \\species = "Beagle"
    ;
    var result = try parse(testing.allocator, source);
    defer result.deinit();
    const node = result.node;

    try testing.expect(node.tag == .table);
    try testing.expectEqualStrings("TOML Example", getEntry(node, "title").?.data.string);
    try testing.expectEqual(@as(i64, 40), getEntry(node, "weight").?.data.int64);
}

test "toml parser: integer variants" {
    const testing = std.testing;
    const source = "int1 = +99\nint2 = 42\nint3 = -17\nint4 = 1_000\nhex1 = 0xDEADBEEF\noct1 = 0o755\nbin1 = 0b11010110\n";
    var result = try parse(testing.allocator, source);
    defer result.deinit();
    const node = result.node;
    try testing.expectEqual(@as(i64, 99), getEntry(node, "int1").?.data.int64);
    try testing.expectEqual(@as(i64, 0xDEADBEEF), getEntry(node, "hex1").?.data.int64);
    try testing.expectEqual(@as(i64, 0o755), getEntry(node, "oct1").?.data.int64);
    try testing.expectEqual(@as(i64, 0b11010110), getEntry(node, "bin1").?.data.int64);
}

test "toml parser: floats" {
    const testing = std.testing;
    const source = "flt1 = +1.0\nflt2 = 3.1415\nflt4 = 5e+22\nflt5 = 1e06\n";
    var result = try parse(testing.allocator, source);
    defer result.deinit();
    const node = result.node;
    try testing.expectEqual(@as(f64, 1.0), getEntry(node, "flt1").?.data.fp64);
    try testing.expectEqual(@as(f64, 5e22), getEntry(node, "flt4").?.data.fp64);
}

test "toml parser: booleans" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "bool1 = true\nbool2 = false\n");
    defer result.deinit();
    const node = result.node;
    try testing.expectEqual(true, getEntry(node, "bool1").?.data.boolean);
    try testing.expectEqual(false, getEntry(node, "bool2").?.data.boolean);
}

test "toml parser: dotted keys" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "apple.type = \"fruit\"\napple.skin = \"thin\"\n");
    defer result.deinit();
    const node = result.node;
    const apple = getEntry(node, "apple") orelse return error.UnexpectedTestResult;
    try testing.expect(apple.tag == .table);
    try testing.expectEqualStrings("fruit", getEntry(apple, "type").?.data.string);
}

test "toml parser: arrays" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "integers = [ 1, 2, 3 ]\n");
    defer result.deinit();
    const node = result.node;
    const arr = getEntry(node, "integers").?.data.array;
    try testing.expectEqual(@as(usize, 3), arr.len);
    try testing.expectEqual(@as(i64, 1), arr[0].data.int64);
}

test "toml parser: tables" {
    const testing = std.testing;
    const source = "[table-1]\nkey1 = \"some string\"\nkey2 = 123\n";
    var result = try parse(testing.allocator, source);
    defer result.deinit();
    const node = result.node;
    const t1 = getEntry(node, "table-1") orelse return error.UnexpectedTestResult;
    try testing.expect(t1.tag == .table);
    try testing.expectEqualStrings("some string", getEntry(t1, "key1").?.data.string);
}

test "toml parser: inline tables" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "name = { first = \"Tom\", last = \"Preston-Werner\" }\n");
    defer result.deinit();
    const node = result.node;
    const name = getEntry(node, "name") orelse return error.UnexpectedTestResult;
    try testing.expect(name.tag == .table);
    try testing.expectEqualStrings("Tom", getEntry(name, "first").?.data.string);
}

test "toml parser: datetimes" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "odt1 = 1979-05-27T07:32:00Z\nld1 = 1979-05-27\nlt1 = 07:32:00\n");
    defer result.deinit();
    const node = result.node;
    try testing.expectEqualStrings("1979-05-27T07:32:00Z", getEntry(node, "odt1").?.data.timestamp);
    try testing.expectEqualStrings("1979-05-27", getEntry(node, "ld1").?.data.timestamp);
    try testing.expectEqualStrings("07:32:00", getEntry(node, "lt1").?.data.timestamp);
}

test "toml parser: arrays of tables" {
    const testing = std.testing;
    const source = "[[arr]]\n[arr.subtab]\nval=1\n[[arr]]\n[arr.subtab]\nval=2\n";
    var result = try parse(testing.allocator, source);
    defer result.deinit();
    const node = result.node;
    const arr = getEntry(node, "arr") orelse return error.UnexpectedTestResult;
    try testing.expect(arr.tag == .array);
    try testing.expectEqual(@as(usize, 2), arr.data.array.len);
}

test "toml parser: empty arrays" {
    const testing = std.testing;
    var result = try parse(testing.allocator, "empty = []\n");
    defer result.deinit();
    const node = result.node;
    try testing.expectEqual(@as(usize, 0), getEntry(node, "empty").?.data.array.len);
}

test "toml parser: syntax error" {
    const testing = std.testing;
    try testing.expectError(error.Syntax, parse(testing.allocator, "key = "));
    try testing.expectError(error.Syntax, parse(testing.allocator, "= value"));
}
