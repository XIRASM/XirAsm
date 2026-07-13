const std = @import("std");

const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const target = @import("../target.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");
const expression_bridge = @import("expression_bridge.zig");

const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    eval_boolean_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!bool,
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
};

pub fn evaluate(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    condition: []const u8,
    callbacks: Callbacks,
) LowerError!bool {
    const trimmed = std.mem.trim(u8, condition, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidMetaIf;

    if (parseBoolLiteral(trimmed)) |value| return value;

    if (std.mem.startsWith(u8, trimmed, "defined(")) {
        const name = try parseNameCallArg(trimmed, "defined");
        return context_mod.lookupLocalValue(context, name) != null or
            module.symbols.lookup(name) != null or
            module.lookupTypeName(name) != null;
    }

    if (try evalTargetCondition(module, context, active, trimmed, callbacks)) |value| return value;

    var condition_expr = expr.parseOwned(module.allocator, trimmed) catch |err| return mapMetaConditionParseError(err);
    defer condition_expr.deinit(module.allocator);
    return callbacks.eval_boolean_at_context(module, context, active, &condition_expr) catch |err| return switch (err) {
        error.InvalidExpression => error.InvalidMetaIf,
        else => err,
    };
}

fn mapMetaConditionParseError(err: expr.ExpressionError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidToken,
        error.InvalidCharacter,
        error.InvalidNumber,
        error.UnexpectedEof,
        => error.UnknownMetaCondition,
        error.DivisionByZero,
        error.FragmentTooLarge,
        error.InvalidApiArgument,
        error.InvalidApiInteger,
        error.InvalidIntegerBits,
        error.InvalidArgument,
        error.InvalidType,
        error.FileNotAvailable,
        error.InvalidOperand,
        error.InvalidFragment,
        error.InvalidSection,
        error.MissingEvaluationContext,
        error.MissingStructFieldValue,
        error.OffsetOverflow,
        error.TypeMismatch,
        error.UndefinedSymbol,
        error.UnknownTypeName,
        error.UnknownField,
        => expression_bridge.mapExpressionError(err),
    };
}

fn parseBoolLiteral(text: []const u8) ?bool {
    if (std.mem.eql(u8, text, "true")) return true;
    if (std.mem.eql(u8, text, "false")) return false;
    return null;
}

fn parseNameCallArg(text: []const u8, name: []const u8) LowerError![]const u8 {
    if (!std.mem.startsWith(u8, text, name)) return error.InvalidMetaIf;
    var rest = std.mem.trim(u8, text[name.len..], " \t");
    if (rest.len < 2 or rest[0] != '(' or rest[rest.len - 1] != ')') return error.InvalidMetaIf;
    rest = std.mem.trim(u8, rest[1 .. rest.len - 1], " \t");
    if (rest.len == 0) return error.InvalidMetaIf;

    if (rest.len >= 2 and rest[0] == '"' and rest[rest.len - 1] == '"') {
        const unquoted = rest[1 .. rest.len - 1];
        if (!isMetaName(unquoted)) return error.InvalidMetaIf;
        return unquoted;
    }

    if (!isMetaName(rest)) return error.InvalidMetaIf;
    return rest;
}

fn evalTargetCondition(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    condition: []const u8,
    callbacks: Callbacks,
) LowerError!?bool {
    const comparison = splitComparison(condition) orelse return null;
    if (std.mem.eql(u8, comparison.left, "target.bits") or
        std.mem.eql(u8, comparison.left, "target.xlen"))
    {
        var expected_expression = expr.parseOwned(module.allocator, comparison.right) catch |err| return expression_bridge.mapExpressionError(err);
        defer expected_expression.deinit(module.allocator);
        const expected_bits = try callbacks.eval_integer_at_context(module, context, active, &expected_expression);
        const active_bits = active.target.bits() orelse return error.InvalidMetaIf;
        const is_equal = active_bits == expected_bits;
        return if (comparison.equal) is_equal else !is_equal;
    }

    if (std.mem.eql(u8, comparison.left, "target.isa")) {
        const expected_isa = try parseIsaLiteral(comparison.right);
        const is_equal = active.target.isa() == expected_isa;
        return if (comparison.equal) is_equal else !is_equal;
    }

    return null;
}

const Comparison = struct {
    left: []const u8,
    right: []const u8,
    equal: bool,
};

fn splitComparison(condition: []const u8) ?Comparison {
    if (std.mem.indexOf(u8, condition, "==")) |index| {
        return .{
            .left = std.mem.trim(u8, condition[0..index], " \t"),
            .right = std.mem.trim(u8, condition[index + 2 ..], " \t"),
            .equal = true,
        };
    }
    if (std.mem.indexOf(u8, condition, "!=")) |index| {
        return .{
            .left = std.mem.trim(u8, condition[0..index], " \t"),
            .right = std.mem.trim(u8, condition[index + 2 ..], " \t"),
            .equal = false,
        };
    }
    return null;
}

fn parseIsaLiteral(text: []const u8) LowerError!target.Isa {
    var trimmed = std.mem.trim(u8, text, " \t");
    if (trimmed.len >= 2 and trimmed[0] == '"' and trimmed[trimmed.len - 1] == '"') {
        trimmed = trimmed[1 .. trimmed.len - 1];
    } else if (trimmed.len >= 2 and trimmed[0] == '.') {
        trimmed = trimmed[1..];
    }

    if (std.mem.eql(u8, trimmed, "x86_64")) return .x86_64;
    if (std.mem.eql(u8, trimmed, "riscv64")) return .riscv64;
    if (std.mem.eql(u8, trimmed, "spirv")) return .spirv;
    return error.InvalidMetaIf;
}

fn isMetaName(text: []const u8) bool {
    if (text.len == 0) return false;
    if (!(std.ascii.isAlphabetic(text[0]) or text[0] == '_' or text[0] == '.')) return false;
    for (text[1..]) |byte| {
        if (!(std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '.' or byte == '$')) return false;
    }
    return true;
}
