const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    eval_value_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!value_mod.Value,
};

/// Render text as a source string literal that reads back byte-for-byte.
///
/// Both this and `formatBytesValue` are used to freeze captured values as text
/// that is parsed again later, so quoting is not cosmetic: a backslash has to
/// be doubled or a value ending in `\` would turn the closing quote into an
/// escaped quote and the re-parse would run past the end of the literal.
pub fn formatStringLiteral(allocator: Allocator, text: []const u8) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.append(allocator, '"');
    for (text) |byte| {
        switch (byte) {
            '"' => try result.appendSlice(allocator, "\"\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            else => try result.append(allocator, byte),
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

pub fn formatBytesValue(allocator: Allocator, bytes: []const u8) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, "b\"");
    for (bytes) |byte| {
        switch (byte) {
            '"' => try result.appendSlice(allocator, "\"\""),
            '\\' => try result.appendSlice(allocator, "\\\\"),
            else => try result.append(allocator, byte),
        }
    }
    try result.append(allocator, '"');
    return result.toOwnedSlice(allocator);
}

pub fn formatDiagnosticMessage(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(allocator);

    for (call.args, 0..) |*arg, index| {
        if (index != 0) try message.append(allocator, ' ');
        const text = try formatDiagnosticArgument(allocator, module, context, active, arg, callbacks);
        defer allocator.free(text);
        try message.appendSlice(allocator, text);
    }

    return message.toOwnedSlice(allocator);
}

pub fn formatDiagnosticArgument(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    arg: *const ast.ApiArgument,
    callbacks: Callbacks,
) LowerError![]u8 {
    return switch (arg.*) {
        .string => |value| try allocator.dupe(u8, value),
        .expression => |*node| {
            var value = try callbacks.eval_value_at_context(allocator, module, context, active, node);
            defer value.deinit(allocator);
            return formatMetaValue(allocator, value);
        },
        .struct_literal => error.InvalidApiArgument,
    };
}

/// How deep a printed value is expanded before it is summarised instead. A value
/// built by a loop can nest arbitrarily, and a diagnostic that dumps thousands of
/// brackets helps nobody.
const max_rendered_depth: usize = 8;

/// Render a Meta value for `print`, `warn`, `err`, and failed `assert` messages.
///
/// Lists and maps are expanded with their contents, one entry per line, because
/// the point of printing a value is to see what is in it: `map#3` names a length
/// and hides the thing the reader is looking for. Past `max_rendered_depth` the
/// contents are summarised again so a cyclic-looking or very deep value cannot
/// produce a wall of text.
pub fn formatMetaValue(allocator: Allocator, value: value_mod.Value) LowerError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);
    try appendMetaValue(&out, allocator, value, 0);
    return out.toOwnedSlice(allocator);
}

fn appendMetaValue(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    value: value_mod.Value,
    depth: usize,
) LowerError!void {
    switch (value) {
        .void => try out.appendSlice(allocator, "void"),
        .integer => |integer| try out.print(allocator, "{}", .{integer.value}),
        .float32 => |stored| {
            const text = try value_mod.formatFloatLiteral(allocator, stored);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        },
        .float64 => |stored| {
            const text = try value_mod.formatFloatLiteral(allocator, stored);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        },
        .boolean => |boolean| try out.appendSlice(allocator, if (boolean) "true" else "false"),
        .string => |text| try out.appendSlice(allocator, text),
        .bytes => |bytes| {
            const text = try formatBytesValue(allocator, bytes);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        },
        .type => |id| try out.print(allocator, "type#{}", .{id.index}),
        .@"struct" => |struct_value| try out.print(allocator, "struct#{}", .{struct_value.type_id.index}),
        .list => |list| {
            if (list.items.len == 0) {
                try out.appendSlice(allocator, "[]");
                return;
            }
            if (depth >= max_rendered_depth) {
                try out.print(allocator, "list#{}", .{list.items.len});
                return;
            }
            try out.appendSlice(allocator, "[\n");
            for (list.items, 0..) |item, index| {
                try appendRenderedIndent(out, allocator, depth + 1);
                try appendMetaValue(out, allocator, item, depth + 1);
                if (index + 1 != list.items.len) try out.append(allocator, ',');
                try out.append(allocator, '\n');
            }
            try appendRenderedIndent(out, allocator, depth);
            try out.append(allocator, ']');
        },
        .map => |map| {
            if (map.entries.len == 0) {
                try out.appendSlice(allocator, "{}");
                return;
            }
            if (depth >= max_rendered_depth) {
                try out.print(allocator, "map#{}", .{map.entries.len});
                return;
            }
            try out.appendSlice(allocator, "{\n");
            for (map.entries, 0..) |entry, index| {
                try appendRenderedIndent(out, allocator, depth + 1);
                try out.appendSlice(allocator, entry.key);
                try out.appendSlice(allocator, ": ");
                try appendMetaValue(out, allocator, entry.value, depth + 1);
                if (index + 1 != map.entries.len) try out.append(allocator, ',');
                try out.append(allocator, '\n');
            }
            try appendRenderedIndent(out, allocator, depth);
            try out.append(allocator, '}');
        },
        .operand => |operand| {
            const text = try operand.text(allocator);
            defer allocator.free(text);
            try out.appendSlice(allocator, text);
        },
    }
}

fn appendRenderedIndent(out: *std.ArrayList(u8), allocator: Allocator, depth: usize) LowerError!void {
    var index: usize = 0;
    while (index < depth * 2) : (index += 1) try out.append(allocator, ' ');
}

test "literal formatting reads back byte-for-byte" {
    const allocator = std.testing.allocator;

    // The case that matters: a value ending in a backslash. Leaving it single
    // would put it in front of the closing quote, so re-parsing the frozen text
    // would read an escaped quote and run off the end of the literal.
    const string = try formatStringLiteral(allocator, "quote\"slash\\");
    defer allocator.free(string);
    try std.testing.expectEqualStrings("\"quote\"\"slash\\\\\"", string);
    var text_node = try expr.parseOwned(allocator, string);
    defer text_node.deinit(allocator);
    try std.testing.expectEqualStrings("quote\"slash\\", text_node.string_literal);

    const samples = [_][]const u8{
        "quote\"slash\\",
        "A\"B",
        "\\",
        "\\n",
        // Text that *looks* like a unicode escape has to survive the round trip
        // too: the renderer doubles backslashes, so `\u0041` comes back as the
        // six characters it is rather than as the letter A.
        "\\u0041",
        "\\\\u0041",
        "\n",
        "\x00A\n\"\\",
        "plain",
    };
    for (samples) |sample| {
        const rendered = try formatBytesValue(allocator, sample);
        defer allocator.free(rendered);
        var node = try expr.parseOwned(allocator, rendered);
        defer node.deinit(allocator);
        try std.testing.expectEqualStrings(sample, node.bytes_literal);
    }
}
