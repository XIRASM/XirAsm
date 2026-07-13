const std = @import("std");

const ast = @import("../ast.zig");
const fragment = @import("../fragment.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    value_arg_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError!value_mod.Value,
    integer_arg_at_context: *const fn (*module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError!u64,
    advance_active_output: *const fn (*ActiveOutput, fragment.Fragment) LowerError!void,
};

pub fn lowerEmitCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    byte_count: u8,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len == 0) return error.InvalidApiArity;

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(module.allocator);

    for (call.args, 0..) |_, index| {
        if (byte_count == 1) {
            var value = try callbacks.value_arg_at_context(module.allocator, module, context, active.*, call, index);
            defer value.deinit(module.allocator);
            switch (value) {
                .integer => |integer| try appendIntegerBytes(module.allocator, &bytes, integer.value, byte_count),
                .string => |text| try bytes.appendSlice(module.allocator, text),
                .bytes => |data| try bytes.appendSlice(module.allocator, data),
                .void, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            }
        } else {
            const value = try callbacks.integer_arg_at_context(module, context, active.*, call, index);
            try appendIntegerBytes(module.allocator, &bytes, value, byte_count);
        }
    }

    const fragment_id = try module.emitBytes(active.section_id, bytes.items, call.span);
    try callbacks.advance_active_output(active, module.fragments.items.items[fragment_id.index]);
}

pub fn lowerReserveCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    scale: u64,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len != 1) return error.InvalidApiArity;
    const count = try callbacks.integer_arg_at_context(module, context, active.*, call, 0);
    const byte_count = std.math.mul(u64, count, scale) catch return error.InvalidApiInteger;
    const fragment_id = try module.reserve(active.section_id, byte_count, 1, call.span);
    try callbacks.advance_active_output(active, module.fragments.items.items[fragment_id.index]);
}

pub fn packStructValue(
    module: *module_mod.Module,
    struct_value: value_mod.StructValue,
) LowerError![]u8 {
    return value_mod.packStructValue(module.allocator, &module.types, struct_value) catch |err| switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ExpectedStruct => error.InvalidApiArgument,
        error.IntegerOverflow => error.InvalidApiInteger,
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.InvalidIntegerBits => error.InvalidIntegerBits,
        error.InvalidType => error.InvalidType,
        error.MissingStructFieldValue => error.MissingStructFieldValue,
        error.FragmentTooLarge => error.FragmentTooLarge,
    };
}

fn appendIntegerBytes(
    allocator: Allocator,
    bytes: *std.ArrayList(u8),
    value: u64,
    byte_count: u8,
) LowerError!void {
    switch (byte_count) {
        1 => {
            if (value > std.math.maxInt(u8)) return error.InvalidApiInteger;
            try bytes.append(allocator, @intCast(value));
        },
        2 => {
            if (value > std.math.maxInt(u16)) return error.InvalidApiInteger;
            var encoded: [2]u8 = undefined;
            std.mem.writeInt(u16, &encoded, @intCast(value), .little);
            try bytes.appendSlice(allocator, &encoded);
        },
        4 => {
            if (value > std.math.maxInt(u32)) return error.InvalidApiInteger;
            var encoded: [4]u8 = undefined;
            std.mem.writeInt(u32, &encoded, @intCast(value), .little);
            try bytes.appendSlice(allocator, &encoded);
        },
        8 => {
            var encoded: [8]u8 = undefined;
            std.mem.writeInt(u64, &encoded, value, .little);
            try bytes.appendSlice(allocator, &encoded);
        },
        else => return error.InvalidApiArgument,
    }
}
