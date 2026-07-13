const std = @import("std");

const ast = @import("../ast.zig");
const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const type_name = @import("../type_name.zig");
const types = @import("../types.zig");
const contracts = @import("contracts.zig");
const expression_bridge = @import("expression_bridge.zig");

const Allocator = std.mem.Allocator;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    eval_integer: *const fn (*module_mod.Module, *const expr.Node) LowerError!u64,
};

pub fn lower(
    allocator: Allocator,
    module: *module_mod.Module,
    declaration: ast.StructDeclarationStatement,
    callbacks: Callbacks,
) LowerError!void {
    const specs = try allocator.alloc(types.StructFieldSpec, declaration.fields.len);
    defer allocator.free(specs);

    for (declaration.fields, 0..) |field, index| {
        const field_type = (try type_name.resolveNamedOrFixedInteger(module, field.type_name)) orelse return error.UnknownTypeName;
        const default_value = if (field.default_value) |default_text| default: {
            const stored_type = try module.types.get(field_type);
            switch (stored_type.*) {
                .int => {},
                .void, .array, .pointer, .@"struct", .@"union" => return error.InvalidStructField,
            }
            break :default try lowerFieldDefault(allocator, module, default_text, callbacks);
        } else null;
        specs[index] = .{
            .name = field.name,
            .ty = field_type,
            .default_value = default_value,
        };
    }

    const layout_policy: types.StructLayoutPolicy = switch (declaration.policy) {
        .natural => .natural,
        .@"packed" => .@"packed",
    };
    const aggregate_ty = switch (declaration.kind) {
        .@"struct" => try module.addStructType(declaration.name, specs, layout_policy),
        .@"union" => try module.addUnionType(declaration.name, specs, layout_policy),
    };
    try module.registerTypeName(declaration.name, aggregate_ty);
}

fn lowerFieldDefault(
    allocator: Allocator,
    module: *module_mod.Module,
    default_value: []const u8,
    callbacks: Callbacks,
) LowerError!u64 {
    var expression = expr.parseOwned(allocator, default_value) catch |err| return expression_bridge.mapExpressionError(err);
    defer expression.deinit(allocator);
    return callbacks.eval_integer(module, &expression);
}
