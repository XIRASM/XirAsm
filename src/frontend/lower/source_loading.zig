const std = @import("std");

const ast = @import("../ast.zig");
const module_mod = @import("../module.zig");
const parser = @import("../parser.zig");
const source = @import("../source.zig");
const api_mod = @import("api.zig");
const contracts = @import("contracts.zig");
const context_mod = @import("context.zig");

const Allocator = std.mem.Allocator;
const ActiveOutput = contracts.ActiveOutput;
const LowerContext = context_mod.LowerContext;
const LowerError = contracts.LowerError;
const LowerOptions = contracts.LowerOptions;

const max_include_depth = 128;

pub const Callbacks = struct {
    lower_statements_into_context: *const fn (Allocator, *module_mod.Module, []const ast.Statement, *LowerContext) LowerError!void,
    add_lower_error_diagnostic: *const fn (Allocator, *module_mod.Module, source.SourceSpan, anyerror) Allocator.Error!void,
    source_path_arg_at_context: *const fn (Allocator, *module_mod.Module, *LowerContext, ActiveOutput, ast.ApiCallStatement, usize) LowerError![]u8,
    section_cursor: *const fn (*const module_mod.Module, contracts.SectionId) LowerError!u64,
    require_arg_count: *const fn (ast.ApiCallStatement, usize) LowerError!void,
};

pub fn lowerSource(
    allocator: Allocator,
    input: []const u8,
    options: LowerOptions,
    callbacks: Callbacks,
) LowerError!module_mod.Module {
    var module = try module_mod.Module.init(allocator, options.target);
    errdefer module.deinit();

    var context: LowerContext = .{ .include_resolver = options.include_resolver };
    defer context.deinit(allocator);

    try lowerIntoModuleInternal(allocator, &module, null, input, &context, callbacks);
    return module;
}

pub fn lowerIntoModule(
    allocator: Allocator,
    module: *module_mod.Module,
    input: []const u8,
    callbacks: Callbacks,
) LowerError!void {
    var context: LowerContext = .{};
    defer context.deinit(allocator);
    try lowerIntoModuleInternal(allocator, module, null, input, &context, callbacks);
}

pub fn lowerIntoModuleWithPath(
    allocator: Allocator,
    module: *module_mod.Module,
    path: []const u8,
    input: []const u8,
    options: ?LowerOptions,
    callbacks: Callbacks,
) LowerError!void {
    var context: LowerContext = .{ .include_resolver = if (options) |stored| stored.include_resolver else null };
    defer context.deinit(allocator);
    try lowerIntoModuleWithPathInternal(allocator, module, path, input, &context, callbacks);
}

pub fn lowerIncludeOrImportCall(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    call: ast.ApiCallStatement,
    context: *LowerContext,
    mode: api_mod.SourceLoadMode,
    callbacks: Callbacks,
) LowerError!void {
    try callbacks.require_arg_count(call, 1);
    if (output_stack.items.len != 0) return error.InvalidApiCall;
    if (mode == .import_once and context.scopes.items.len != 0) return error.InvalidMetaBlock;

    const include_path = try callbacks.source_path_arg_at_context(allocator, module, context, active.*, call, 0);
    defer allocator.free(include_path);

    const resolver = context.include_resolver orelse return error.IncludeNotAvailable;
    var include_source = try resolver.resolve(resolver.context, allocator, .{
        .path = include_path,
        .parent_path = context_mod.currentSourcePath(context),
        .span = call.span,
    });
    defer include_source.deinit(allocator);

    if (context_mod.sourceStackContains(context, include_source.path)) return error.IncludeCycle;

    if (mode == .import_once) {
        if (context_mod.sourceImported(context, include_source.path)) return;
        try context_mod.rememberImportedSource(allocator, context, include_source.path);
    }

    try lowerIntoModuleWithPathInternal(allocator, module, include_source.path, include_source.bytes, context, callbacks);
    active.offset = try callbacks.section_cursor(module, active.section_id);
    active.target = module.target;
}

fn lowerIntoModuleInternal(
    allocator: Allocator,
    module: *module_mod.Module,
    path: ?[]const u8,
    input: []const u8,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    if (path) |source_path| {
        try lowerIntoModuleWithPathInternal(allocator, module, source_path, input, context, callbacks);
        return;
    }

    var statements = try parser.parseSource(allocator, input);
    defer statements.deinit(allocator);
    try callbacks.lower_statements_into_context(allocator, module, statements.items.items, context);
}

fn lowerIntoModuleWithPathInternal(
    allocator: Allocator,
    module: *module_mod.Module,
    path: []const u8,
    input: []const u8,
    context: *LowerContext,
    callbacks: Callbacks,
) LowerError!void {
    if (context.source_stack.items.len >= max_include_depth) return error.IncludeTooDeep;
    if (context_mod.sourceStackContains(context, path)) return error.IncludeCycle;

    try context.source_stack.append(allocator, path);
    defer context.source_stack.shrinkRetainingCapacity(context.source_stack.items.len - 1);

    const source_id = try module.addSource(path, input);
    var statements = parser.parseSourceWithId(allocator, source_id, input) catch |err| {
        try callbacks.add_lower_error_diagnostic(allocator, module, .{
            .source = source_id,
            .start = 0,
            .end = 0,
        }, err);
        return err;
    };
    defer statements.deinit(allocator);
    try callbacks.lower_statements_into_context(allocator, module, statements.items.items, context);
}
