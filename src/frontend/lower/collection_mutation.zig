const std = @import("std");

const ast = @import("../ast.zig");
const module_mod = @import("../module.zig");
const value_mod = @import("../value.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;

pub const Callbacks = struct {
    value_arg_at_context: *const fn (
        allocator: Allocator,
        module: *module_mod.Module,
        context: *LowerContext,
        active: ActiveOutput,
        call: ast.ApiCallStatement,
        index: usize,
    ) LowerError!value_mod.Value,
};

pub const MutationKind = enum {
    list_push,
    list_set,
    map_set,
};

pub fn mutationKind(callee: []const u8) ?MutationKind {
    if (std.mem.eql(u8, callee, "list.push_mut")) return .list_push;
    if (std.mem.eql(u8, callee, "list.set_mut")) return .list_set;
    if (std.mem.eql(u8, callee, "map.set_mut")) return .map_set;
    return null;
}

pub fn lower(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    mutation: MutationKind,
    callbacks: Callbacks,
) LowerError!void {
    switch (mutation) {
        .list_push => {
            // api-matrix-lower: "list.push_mut"
            try requireArgCount(module, call, 2);
            var item = try callbacks.value_arg_at_context(module.allocator, module, context, active, call, 1);
            defer item.deinit(module.allocator);
            const target = try mutableTarget(module, context, call);
            switch (target.*) {
                .list => target.list.pushCloned(module.allocator, item) catch |err| switch (err) {
                    error.CollectionTooLarge => return fail(module, call, "list.push_mut target is too large"),
                    error.OutOfMemory => return error.OutOfMemory,
                },
                else => return fail(module, call, "list.push_mut target must have type list"),
            }
        },
        .list_set => {
            // api-matrix-lower: "list.set_mut"
            try requireArgCount(module, call, 3);
            const index = try integerArg(module, context, active, call, 1, callbacks);
            var item = try callbacks.value_arg_at_context(module.allocator, module, context, active, call, 2);
            defer item.deinit(module.allocator);
            const target = try mutableTarget(module, context, call);
            switch (target.*) {
                .list => target.list.setCloned(module.allocator, index, item) catch |err| switch (err) {
                    error.IndexOutOfBounds => return fail(module, call, "list.set_mut index is outside the target list"),
                    error.OutOfMemory => return error.OutOfMemory,
                },
                else => return fail(module, call, "list.set_mut target must have type list"),
            }
        },
        .map_set => {
            // api-matrix-lower: "map.set_mut"
            try requireArgCount(module, call, 3);
            var key_value = try callbacks.value_arg_at_context(module.allocator, module, context, active, call, 1);
            defer key_value.deinit(module.allocator);
            const key = switch (key_value) {
                .string => |text| text,
                else => return fail(module, call, "map.set_mut key must have type string"),
            };
            var item = try callbacks.value_arg_at_context(module.allocator, module, context, active, call, 2);
            defer item.deinit(module.allocator);
            const target = try mutableTarget(module, context, call);
            switch (target.*) {
                .map => target.map.setCloned(module.allocator, key, item) catch |err| switch (err) {
                    error.CollectionTooLarge => return fail(module, call, "map.set_mut target is too large"),
                    error.OutOfMemory => return error.OutOfMemory,
                },
                else => return fail(module, call, "map.set_mut target must have type map"),
            }
        },
    }
}

fn mutableTarget(
    module: *module_mod.Module,
    context: *LowerContext,
    call: ast.ApiCallStatement,
) LowerError!*value_mod.Value {
    const name = directSymbolArg(call, 0) orelse
        return fail(module, call, "collection mutation target must be a direct let binding");
    return switch (context_mod.lookupMutableLocalValue(context, name)) {
        .missing => if (context.value_function_depth != 0)
            fail(module, call, "collection mutation target must resolve to a local let binding")
        else switch (module.symbols.lookupMutableValue(name)) {
            .missing => fail(module, call, "collection mutation target must resolve to a let binding"),
            .immutable => fail(module, call, "cannot mutate a const collection binding"),
            .value => |value| value,
        },
        .immutable => fail(module, call, "cannot mutate a const collection binding"),
        .value => |value| value,
    };
}

fn directSymbolArg(call: ast.ApiCallStatement, index: usize) ?[]const u8 {
    if (index >= call.args.len) return null;
    return switch (call.args[index]) {
        .expression => |node| switch (node) {
            .symbol => |name| name,
            else => null,
        },
        .string, .struct_literal => null,
    };
}

fn integerArg(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
    callbacks: Callbacks,
) LowerError!usize {
    var value = try callbacks.value_arg_at_context(module.allocator, module, context, active, call, index);
    defer value.deinit(module.allocator);
    const raw = value.expectInteger() catch return fail(module, call, "list.set_mut index must have type integer");
    return std.math.cast(usize, raw) orelse return fail(module, call, "list.set_mut index is too large");
}

fn requireArgCount(module: *module_mod.Module, call: ast.ApiCallStatement, expected: usize) LowerError!void {
    if (call.args.len == expected) return;
    return fail(module, call, "invalid collection mutation argument count");
}

fn fail(module: *module_mod.Module, call: ast.ApiCallStatement, message: []const u8) LowerError {
    module.diagnostics.add(module.allocator, .err, call.span, message) catch return error.OutOfMemory;
    return error.FrontendDiagnostics;
}

test "mutation names map to one statement-only dispatch kind" {
    try std.testing.expectEqual(MutationKind.list_push, mutationKind("list.push_mut").?);
    try std.testing.expectEqual(MutationKind.list_set, mutationKind("list.set_mut").?);
    try std.testing.expectEqual(MutationKind.map_set, mutationKind("map.set_mut").?);
    try std.testing.expect(mutationKind("list.push") == null);
    try std.testing.expect(mutationKind("map.set") == null);
}
