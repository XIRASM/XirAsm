const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const fragment = @import("../fragment.zig");
const module_mod = @import("../module.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;
const OutputStoreTarget = contracts.OutputStoreTarget;

pub const Callbacks = struct {
    eval_integer_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, *const expr.Node) LowerError!u64,
};

pub fn resolveAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!OutputStoreTarget {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| switch (node.*) {
            .symbol => |name| targetFromName(module, context, active, node, name, callbacks),
            else => .{
                .section = try expressionSection(module, context, active, node),
                .address = try callbacks.eval_integer_at_context(module, context, active, node),
            },
        },
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn expressionSection(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
) LowerError!fragment.SectionId {
    if (try labelSection(module, context, node)) |section_id| return section_id;
    return active.section_id;
}

fn labelSection(
    module: *module_mod.Module,
    context: *LowerContext,
    node: *const expr.Node,
) LowerError!?fragment.SectionId {
    return switch (node.*) {
        .symbol => |name| blk: {
            if (context_mod.lookupLocalValue(context, name) != null) break :blk null;
            const symbol_id = module.symbols.lookup(name) orelse break :blk null;
            const stored = try module.symbols.get(symbol_id);
            break :blk switch (stored.binding) {
                .label => |label| label.section,
                .absolute, .value, .unknown => null,
            };
        },
        .unary => |unary| labelSection(module, context, unary.operand),
        .binary => |binary| blk: {
            const left = try labelSection(module, context, binary.left);
            const right = try labelSection(module, context, binary.right);
            if (left) |left_section| {
                if (right) |right_section| {
                    if (left_section.index != right_section.index) return error.InvalidApiArgument;
                }
                break :blk left_section;
            }
            break :blk right;
        },
        .field_access => |access| labelSection(module, context, access.object),
        .builtin_call, .integer, .float64, .boolean, .string_literal, .bytes_literal => null,
    };
}

fn targetFromName(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
    name: []const u8,
    callbacks: Callbacks,
) LowerError!OutputStoreTarget {
    if (context_mod.lookupLocalValue(context, name) != null) {
        return .{
            .section = active.section_id,
            .address = try callbacks.eval_integer_at_context(module, context, active, node),
        };
    }

    const symbol_id = module.symbols.lookup(name) orelse {
        return .{
            .section = active.section_id,
            .address = try callbacks.eval_integer_at_context(module, context, active, node),
        };
    };
    const stored = try module.symbols.get(symbol_id);
    return switch (stored.binding) {
        .label => |label| blk: {
            const label_section = try module.sections.get(label.section);
            break :blk .{
                .section = label.section,
                .address = std.math.add(u64, label_section.origin, label.offset) catch return error.OffsetOverflow,
            };
        },
        .absolute => |absolute| .{
            .section = active.section_id,
            .address = if (absolute < 0) return error.InvalidApiArgument else @intCast(absolute),
        },
        .value => .{
            .section = active.section_id,
            .address = try callbacks.eval_integer_at_context(module, context, active, node),
        },
        .unknown => error.InvalidApiArgument,
    };
}
