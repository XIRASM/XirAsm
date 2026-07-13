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

pub fn formatStringLiteral(allocator: Allocator, text: []const u8) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.append(allocator, '"');
    for (text) |byte| {
        if (byte == '"') {
            try result.appendSlice(allocator, "\"\"");
        } else {
            try result.append(allocator, byte);
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
        if (byte == '"') {
            try result.appendSlice(allocator, "\"\"");
        } else {
            try result.append(allocator, byte);
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

pub fn formatMetaValue(allocator: Allocator, value: value_mod.Value) LowerError![]u8 {
    return switch (value) {
        .void => try allocator.dupe(u8, "void"),
        .integer => |integer| try std.fmt.allocPrint(allocator, "{}", .{integer.value}),
        .boolean => |boolean| try allocator.dupe(u8, if (boolean) "true" else "false"),
        .string => |text| try allocator.dupe(u8, text),
        .bytes => |bytes| try formatBytesValue(allocator, bytes),
        .type => |id| try std.fmt.allocPrint(allocator, "type#{}", .{id.index}),
        .@"struct" => |struct_value| try std.fmt.allocPrint(allocator, "struct#{}", .{struct_value.type_id.index}),
        .list => |list| try std.fmt.allocPrint(allocator, "list#{}", .{list.items.len}),
        .map => |map| try std.fmt.allocPrint(allocator, "map#{}", .{map.entries.len}),
    };
}

test "literal formatting preserves XIRASM quote escaping" {
    const string = try formatStringLiteral(std.testing.allocator, "quote\"slash\\");
    defer std.testing.allocator.free(string);
    try std.testing.expectEqualStrings("\"quote\"\"slash\\\"", string);

    const bytes = try formatBytesValue(std.testing.allocator, "A\"B");
    defer std.testing.allocator.free(bytes);
    try std.testing.expectEqualStrings("b\"A\"\"B\"", bytes);
}
