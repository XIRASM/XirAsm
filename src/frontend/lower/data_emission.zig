const std = @import("std");

const ast = @import("../ast.zig");
const fragment = @import("../fragment.zig");
const meta_data = @import("../meta_data.zig");
const meta_io = @import("../meta_io.zig");
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
    file_resolver: *const fn (*LowerContext) ?meta_io.FileResolver,
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
                .void, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            }
        } else {
            const value = try callbacks.integer_arg_at_context(module, context, active.*, call, index);
            try appendIntegerBytes(module.allocator, &bytes, value, byte_count);
        }
    }

    const fragment_id = try module.emitBytes(active.section_id, bytes.items, call.span);
    try callbacks.advance_active_output(active, module.fragments.items.items[fragment_id.index]);
}

pub fn lowerFloatCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    byte_count: u8,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len != 1) return error.InvalidApiArity;
    var value = try callbacks.value_arg_at_context(module.allocator, module, context, active.*, call, 0);
    defer value.deinit(module.allocator);

    var encoded: [8]u8 = undefined;
    const bytes: []const u8 = switch (byte_count) {
        4 => blk: {
            const bits: u32 = @bitCast(value.expectFloat32() catch return error.InvalidApiArgument);
            std.mem.writeInt(u32, encoded[0..4], bits, .little);
            break :blk encoded[0..4];
        },
        8 => blk: {
            const bits: u64 = @bitCast(value.expectFloat64() catch return error.InvalidApiArgument);
            std.mem.writeInt(u64, &encoded, bits, .little);
            break :blk &encoded;
        },
        else => return error.InvalidApiArgument,
    };
    const fragment_id = try module.emitBytes(active.section_id, bytes, call.span);
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

pub fn lowerFileCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    callbacks: Callbacks,
) LowerError!void {
    if (call.args.len != 1 and call.args.len != 3) return error.InvalidApiArity;
    var path_value = try callbacks.value_arg_at_context(module.allocator, module, context, active.*, call, 0);
    defer path_value.deinit(module.allocator);
    const path = switch (path_value) {
        .string => |text| text,
        .void, .integer, .float32, .float64, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
    };
    const range: ?meta_data.ByteRange = if (call.args.len == 3) .{
        .offset = try integerArgAsUsize(module, context, active.*, call, 1, callbacks),
        .count = try integerArgAsUsize(module, context, active.*, call, 2, callbacks),
    } else null;
    const resolver = callbacks.file_resolver(context) orelse return error.FileNotAvailable;
    const bytes = meta_data.readBytes(
        module.allocator,
        resolver,
        path,
        context_mod.currentSourcePath(context),
        call.span,
        range,
    ) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotAvailable => return error.FileNotAvailable,
        error.InvalidApiInteger => return error.InvalidApiInteger,
    };
    defer module.allocator.free(bytes);

    const fragment_id = try module.emitBytes(active.section_id, bytes, call.span);
    try callbacks.advance_active_output(active, module.fragments.items.items[fragment_id.index]);
}

fn integerArgAsUsize(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!usize {
    const value = try callbacks.integer_arg_at_context(module, context, active, call, index);
    if (value > std.math.maxInt(usize)) return error.InvalidApiInteger;
    return @intCast(value);
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
    if (byte_count == 0 or byte_count > 64) return error.InvalidApiArgument;
    if (byte_count < @sizeOf(u64)) {
        const bit_count: u6 = @intCast(byte_count * 8);
        const limit = @as(u64, 1) << bit_count;
        if (value >= limit) return error.InvalidApiInteger;
    }

    var encoded: [8]u8 = undefined;
    std.mem.writeInt(u64, &encoded, value, .little);
    const encoded_count: usize = @min(byte_count, encoded.len);
    try bytes.appendSlice(allocator, encoded[0..encoded_count]);
    const zero_count: usize = byte_count - encoded_count;
    const zeros: [64]u8 = @splat(0);
    try bytes.appendSlice(allocator, zeros[0..zero_count]);
}

test "integer data emission checks narrow widths and zero extends wide widths" {
    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(std.testing.allocator);

    try appendIntegerBytes(std.testing.allocator, &bytes, 0x010203040506, 6);
    try std.testing.expectEqualSlices(u8, &.{ 0x06, 0x05, 0x04, 0x03, 0x02, 0x01 }, bytes.items);
    try std.testing.expectError(
        error.InvalidApiInteger,
        appendIntegerBytes(std.testing.allocator, &bytes, 0x01000000000000, 6),
    );

    bytes.clearRetainingCapacity();
    try appendIntegerBytes(std.testing.allocator, &bytes, 0x0807, 10);
    try std.testing.expectEqualSlices(u8, &.{ 0x07, 0x08, 0, 0, 0, 0, 0, 0, 0, 0 }, bytes.items);
}
