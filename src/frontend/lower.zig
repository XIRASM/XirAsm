const std = @import("std");

const ast = @import("ast.zig");
const expr = @import("expr.zig");
const fixup = @import("fixup.zig");
const fragment = @import("fragment.zig");
const identifier = @import("identifier.zig");
const isa_text = @import("isa_text.zig");
const meta_function = @import("meta_function.zig");
const meta_io = @import("meta_io.zig");
const diagnostic = @import("diagnostic.zig");
const module_mod = @import("module.zig");
const output_mod = @import("output/root.zig");
const pass = @import("pass.zig");
const parser = @import("parser.zig");
const source = @import("source.zig");
const target = @import("target.zig");
const typecheck = @import("typecheck.zig");
const types = @import("types.zig");
const value_mod = @import("value.zig");

const Allocator = std.mem.Allocator;

pub const LowerError = Allocator.Error || error{
    SourceTooLarge,
    TooManySources,
    FrontendDiagnostics,
    InvalidLabel,
    InvalidApiCall,
    InvalidApiArgument,
    InvalidApiArity,
    InvalidApiInteger,
    FileNotAvailable,
    IncludeNotAvailable,
    IncludeCycle,
    IncludeTooDeep,
    InvalidExpression,
    InvalidValueDeclaration,
    InvalidAlignment,
    InvalidStructDeclaration,
    InvalidStructField,
    DuplicateMetaFunction,
    InvalidMetaBlock,
    InvalidMetaDefer,
    InvalidLateLayout,
    InvalidMetaFor,
    InvalidMetaFunction,
    InvalidMetaIf,
    InvalidMetaWhile,
    MetaCallDepthExceeded,
    MetaLoopLimitExceeded,
    InvalidModeBits,
    UnexpectedEndOfMetaBlock,
    UnexpectedEndOfMetaDefer,
    UnexpectedEndOfLateLayout,
    UnexpectedEndOfMetaFor,
    UnexpectedEndOfMetaFunction,
    UnexpectedEndOfStruct,
    UnexpectedEndOfMetaIf,
    UnexpectedEndOfMetaWhile,
    UnexpectedEndOfStatement,
    InvalidFieldName,
    InvalidIntegerBits,
    InvalidType,
    IntegerOverflow,
    DuplicateFieldName,
    DuplicateTypeName,
    TooManyTypes,
    UnknownTypeName,
    UnknownField,
    ExpectedStruct,
    MissingStructFieldValue,
    UnknownApiCall,
    UnknownMetaFunction,
    UnknownMetaCondition,
    MetaFunctionReturned,
    MissingMetaReturn,
    SideEffectInValueFunction,
    UnmatchedVirtualEnd,
    UnclosedVirtualOutput,
    DivisionByZero,
    TooManyStatements,
    TooManySections,
    TooManyFragments,
    TooManyFixups,
    TooManySymbols,
    InvalidFixup,
    InvalidSymbol,
    InvalidSection,
    InvalidFragment,
    LateLayoutDidNotConverge,
    DuplicateSymbol,
    FragmentTooLarge,
    OffsetOverflow,
    OutputRegionClosed,
    FinalizerCannotChangeLayout,
};

pub const LowerOptions = struct {
    target: target.Target = target.Target.default,
    include_resolver: ?IncludeResolver = null,
};

pub const LateLayoutResult = struct {
    iterations: usize,
    executed_blocks: usize,
};

pub const IncludeResolver = struct {
    context: *anyopaque,
    resolve: *const fn (context: *anyopaque, allocator: Allocator, request: IncludeRequest) LowerError!IncludeSource,
};

pub const IncludeRequest = struct {
    path: []const u8,
    parent_path: ?[]const u8,
    span: source.SourceSpan,
};

pub const IncludeSource = struct {
    path: []u8,
    bytes: []u8,

    pub fn deinit(self: *IncludeSource, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.path);
        self.* = undefined;
    }
};

const ActiveOutput = struct {
    section_id: fragment.SectionId,
    offset: u64,
    file_offset: u64,
    file_aligned: bool = false,
    target: target.Target,
};

pub const LowerContext = struct {
    include_resolver: ?IncludeResolver = null,
    source_stack: std.ArrayList([]const u8) = .empty,
    imported_sources: std.ArrayList([]u8) = .empty,
    functions: meta_function.Store = .{},
    scopes: std.ArrayList(MetaScope) = .empty,
    call_depth: u32 = 0,
    value_function_depth: u32 = 0,
    return_value: ?value_mod.Value = null,
    unique_symbol_counter: u64 = 0,

    pub fn deinit(self: *LowerContext, allocator: Allocator) void {
        if (self.return_value) |*stored| {
            stored.deinit(allocator);
        }
        for (self.scopes.items) |*scope| {
            scope.deinit(allocator);
        }
        self.scopes.deinit(allocator);
        self.functions.deinit(allocator);
        for (self.imported_sources.items) |path| {
            allocator.free(path);
        }
        self.imported_sources.deinit(allocator);
        self.source_stack.deinit(allocator);
        self.* = undefined;
    }
};

const max_include_depth = 128;
const max_meta_call_depth = 128;
const max_meta_loop_iterations = 1_000_000;
pub const max_finalizer_loop_iterations = max_meta_loop_iterations;

const MetaLocal = struct {
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,

    fn deinit(self: *MetaLocal, allocator: Allocator) void {
        self.value.deinit(allocator);
        self.* = undefined;
    }
};

const MetaScope = struct {
    locals: std.ArrayList(MetaLocal) = .empty,

    fn deinit(self: *MetaScope, allocator: Allocator) void {
        for (self.locals.items) |*local| {
            local.deinit(allocator);
        }
        self.locals.deinit(allocator);
        self.* = undefined;
    }
};

pub fn lowerSource(
    allocator: Allocator,
    input: []const u8,
    options: LowerOptions,
) LowerError!module_mod.Module {
    var module = try module_mod.Module.init(allocator, options.target);
    errdefer module.deinit();

    var context: LowerContext = .{ .include_resolver = options.include_resolver };
    defer context.deinit(allocator);

    try lowerSourceIntoModuleInternal(allocator, &module, null, input, &context);
    return module;
}

pub fn lowerSourceIntoModule(
    allocator: Allocator,
    module: *module_mod.Module,
    input: []const u8,
) LowerError!void {
    var context: LowerContext = .{};
    defer context.deinit(allocator);

    try lowerSourceIntoModuleInternal(allocator, module, null, input, &context);
}

pub fn lowerSourceIntoModuleWithPath(
    allocator: Allocator,
    module: *module_mod.Module,
    path: []const u8,
    input: []const u8,
) LowerError!void {
    var context: LowerContext = .{};
    defer context.deinit(allocator);

    try lowerSourceIntoModuleWithPathInternal(allocator, module, path, input, &context);
}

pub fn lowerSourceIntoModuleWithPathOptions(
    allocator: Allocator,
    module: *module_mod.Module,
    path: []const u8,
    input: []const u8,
    options: LowerOptions,
) LowerError!void {
    var context: LowerContext = .{ .include_resolver = options.include_resolver };
    defer context.deinit(allocator);

    try lowerSourceIntoModuleWithPathInternal(allocator, module, path, input, &context);
}

fn lowerSourceIntoModuleInternal(
    allocator: Allocator,
    module: *module_mod.Module,
    path: ?[]const u8,
    input: []const u8,
    context: *LowerContext,
) LowerError!void {
    if (path) |source_path| {
        try lowerSourceIntoModuleWithPathInternal(allocator, module, source_path, input, context);
        return;
    }

    var statements = try parser.parseSource(allocator, input);
    defer statements.deinit(allocator);

    try lowerStatementsIntoModuleContext(allocator, module, statements.items.items, context);
}

fn lowerSourceIntoModuleWithPathInternal(
    allocator: Allocator,
    module: *module_mod.Module,
    path: []const u8,
    input: []const u8,
    context: *LowerContext,
) LowerError!void {
    if (context.source_stack.items.len >= max_include_depth) return error.IncludeTooDeep;
    if (sourceStackContains(context, path)) return error.IncludeCycle;

    try context.source_stack.append(allocator, path);
    defer context.source_stack.shrinkRetainingCapacity(context.source_stack.items.len - 1);

    const source_id = try module.addSource(path, input);
    var statements = parser.parseSourceWithId(allocator, source_id, input) catch |err| {
        try addLowerErrorDiagnostic(allocator, module, .{
            .source = source_id,
            .start = 0,
            .end = 0,
        }, err);
        return err;
    };
    defer statements.deinit(allocator);

    try lowerStatementsIntoModuleContext(allocator, module, statements.items.items, context);
}

pub fn lowerStatements(
    allocator: Allocator,
    statements: []const ast.Statement,
    options: LowerOptions,
) LowerError!module_mod.Module {
    var module = try module_mod.Module.init(allocator, options.target);
    errdefer module.deinit();

    var context: LowerContext = .{ .include_resolver = options.include_resolver };
    defer context.deinit(allocator);

    try lowerStatementsIntoModuleContext(allocator, &module, statements, &context);
    return module;
}

pub fn lowerStatementsIntoModule(
    allocator: Allocator,
    module: *module_mod.Module,
    statements: []const ast.Statement,
) LowerError!void {
    var context: LowerContext = .{};
    defer context.deinit(allocator);

    try lowerStatementsIntoModuleContext(allocator, module, statements, &context);
}

fn lowerStatementsIntoModuleContext(
    allocator: Allocator,
    module: *module_mod.Module,
    statements: []const ast.Statement,
    context: *LowerContext,
) LowerError!void {
    var active: ActiveOutput = .{
        .section_id = module.default_section,
        .offset = try sectionCursor(module, module.default_section),
        .file_offset = try sectionFileCursor(module, module.default_section),
        .file_aligned = false,
        .target = module.target,
    };
    var output_stack: std.ArrayList(ActiveOutput) = .empty;
    defer output_stack.deinit(allocator);

    try lowerStatementSlice(allocator, module, &active, &output_stack, statements, context);

    if (output_stack.items.len != 0) return error.UnclosedVirtualOutput;
}

fn lowerStatementSlice(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    statements: []const ast.Statement,
    context: *LowerContext,
) LowerError!void {
    for (statements) |statement| {
        lowerStatement(allocator, module, active, output_stack, statement, context) catch |err| {
            if (err == error.MetaFunctionReturned) return err;
            if (err == error.FrontendDiagnostics) return err;
            try addLowerErrorDiagnostic(allocator, module, statement.span(), err);
            return err;
        };
    }
}

fn lowerScopedStatementSlice(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    statements: []const ast.Statement,
    context: *LowerContext,
) LowerError!void {
    try context.scopes.append(allocator, .{});
    defer discardLastScope(context, allocator);

    try lowerStatementSlice(allocator, module, active, output_stack, statements, context);
}

pub fn runLateLayoutPhase(
    allocator: Allocator,
    module: *module_mod.Module,
) LowerError!void {
    if (module.late_layout.items.items.len == 0) {
        return;
    }

    try runLateLayoutBlocksOnce(allocator, module);
}

fn runLateLayoutBlocksOnce(
    allocator: Allocator,
    module: *module_mod.Module,
) LowerError!void {
    var context: LowerContext = .{};
    defer context.deinit(allocator);

    var active: ActiveOutput = .{
        .section_id = module.default_section,
        .offset = try sectionCursor(module, module.default_section),
        .file_offset = try sectionFileCursor(module, module.default_section),
        .target = module.target,
    };
    var output_stack: std.ArrayList(ActiveOutput) = .empty;
    defer output_stack.deinit(allocator);

    for (module.late_layout.items.items) |block| {
        try runLateLayoutStatements(allocator, module, &active, &output_stack, &context, block.body);
    }

    if (output_stack.items.len != 0) return error.UnclosedVirtualOutput;
}

fn runLateLayoutStatements(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    context: *LowerContext,
    statements: []const output_mod.LateLayoutStatement,
) LowerError!void {
    for (statements) |statement| {
        try runLateLayoutStatement(allocator, module, active, output_stack, context, statement);
    }
}

fn runLateLayoutStatement(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    context: *LowerContext,
    statement: output_mod.LateLayoutStatement,
) LowerError!void {
    switch (statement) {
        .api_call => |call| try runLateLayoutApiCall(allocator, module, active, output_stack, context, call),
        .meta_if => |meta_if| {
            if (try evalLateLayoutCondition(module, context, active.*, meta_if.condition)) {
                try runLateLayoutStatements(allocator, module, active, output_stack, context, meta_if.body);
            } else {
                try runLateLayoutStatements(allocator, module, active, output_stack, context, meta_if.else_body);
            }
        },
    }
}

fn runLateLayoutApiCall(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    context: *LowerContext,
    call: output_mod.ApiCall,
) LowerError!void {
    var parsed = parser.parseApiCallText(allocator, call.text, call.span) catch |err| return mapParseError(err);
    defer parsed.deinit(allocator);
    try lowerApiCall(allocator, module, active, output_stack, parsed, context);
}

fn evalLateLayoutCondition(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    condition: []const u8,
) LowerError!bool {
    return evalMetaCondition(module, context, active, condition);
}

fn lowerStatement(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    statement: ast.Statement,
    context: *LowerContext,
) LowerError!void {
    switch (statement) {
        .label => |label| {
            if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
            try requireOpenOutputRegion(active.*);
            const fragment_position = try activeFragmentPosition(module, active.section_id);
            const label_id = try module.defineAnchoredLabel(label.name, active.section_id, active.offset, fragment_position, label.span);
            if (label_id.index >= module.symbols.items.items.len) return error.InvalidSymbol;
        },
        .value_decl => |declaration| {
            try lowerValueDeclaration(module, context, active.*, declaration);
        },
        .assignment => |assignment| {
            try lowerAssignment(module, context, active.*, assignment);
        },
        .isa_instruction => |instruction| {
            if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
            try requireOpenOutputRegion(active.*);
            const lowered_text = try lowerIsaText(allocator, module, context, active.*, instruction.text);
            defer allocator.free(lowered_text);
            const fragment_id = try module.appendIsaInstruction(
                active.section_id,
                active.target,
                lowered_text,
                instruction.span,
            );
            try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        },
        .struct_decl => |declaration| {
            try lowerStructDeclaration(allocator, module, declaration);
        },
        .api_call => |call| {
            if (context.value_function_depth != 0 and apiCallHasOutputSideEffect(call.callee)) return error.SideEffectInValueFunction;
            try lowerApiCall(allocator, module, active, output_stack, call, context);
        },
        .legacy_directive => |directive| {
            try module.diagnostics.add(
                allocator,
                .err,
                directive.span,
                "legacy assembler directive is not supported; use modern XIRASM API syntax",
            );
        },
        .meta_if => |meta_if| {
            if (try evalMetaCondition(module, context, active.*, meta_if.condition)) {
                try lowerScopedStatementSlice(allocator, module, active, output_stack, meta_if.body, context);
            } else {
                try lowerScopedStatementSlice(allocator, module, active, output_stack, meta_if.else_body, context);
            }
        },
        .meta_while => |meta_while| {
            try lowerMetaWhile(allocator, module, active, output_stack, meta_while, context);
        },
        .meta_for_range => |meta_for| {
            try lowerMetaForRange(allocator, module, active, output_stack, meta_for, context);
        },
        .meta_fn => |meta_fn| {
            if (context.scopes.items.len != 0) return error.InvalidMetaFunction;
            if (meta_fn.return_type_name == null) {
                try context.functions.define(allocator, meta_fn);
            } else {
                try module.value_functions.define(allocator, meta_fn);
            }
        },
        .meta_return => |meta_return| {
            if (context.value_function_depth == 0) return error.InvalidMetaFunction;
            if (context.return_value) |*previous| {
                previous.deinit(allocator);
                context.return_value = null;
            }
            context.return_value = try evalValueAtContext(allocator, module, context, active.*, &meta_return.value);
            return error.MetaFunctionReturned;
        },
        .meta_block => |meta_block| {
            try lowerScopedStatementSlice(allocator, module, active, output_stack, meta_block.body, context);
        },
        .meta_defer => |meta_defer| {
            if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
            if (output_stack.items.len != 0) return error.InvalidMetaDefer;
            var block = if (context.scopes.items.len == 0)
                try cloneDeferredBlockFromAst(allocator, meta_defer)
            else
                try freezeDeferredBlockFromAst(allocator, module, context, active.*, meta_defer);
            errdefer block.deinit(allocator);
            try module.appendDeferredBlock(block);
        },
        .late_layout => |late_layout| {
            if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
            if (output_stack.items.len != 0) return error.InvalidLateLayout;
            var block = if (context.scopes.items.len == 0)
                try cloneLateLayoutBlockFromAst(allocator, late_layout)
            else
                try freezeLateLayoutBlockFromAst(allocator, module, context, active.*, late_layout);
            errdefer block.deinit(allocator);
            try module.appendLateLayoutBlock(block);
        },
        .meta_line, .meta_block_start, .meta_block_end => {},
    }
}

fn apiCallHasOutputSideEffect(callee: []const u8) bool {
    return std.mem.eql(u8, callee, "isa") or
        std.mem.eql(u8, callee, "emit.u8") or
        std.mem.eql(u8, callee, "emit.u16") or
        std.mem.eql(u8, callee, "emit.u32") or
        std.mem.eql(u8, callee, "emit.u64") or
        dataEmitByteCount(callee) != null or
        dataReserveScale(callee) != null or
        std.mem.eql(u8, callee, "region.begin") or
        std.mem.eql(u8, callee, "region.file_align") or
        std.mem.eql(u8, callee, "emit.bytes") or
        std.mem.eql(u8, callee, "emit.struct") or
        std.mem.eql(u8, callee, "pad") or
        std.mem.eql(u8, callee, "pad_to") or
        std.mem.eql(u8, callee, "align") or
        std.mem.eql(u8, callee, "reserve") or
        std.mem.eql(u8, callee, "label.define") or
        std.mem.eql(u8, callee, "virtual.begin") or
        std.mem.eql(u8, callee, "virtual.end") or
        std.mem.startsWith(u8, callee, "store.");
}

fn lowerMetaWhile(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    meta_while: ast.MetaWhileStatement,
    context: *LowerContext,
) LowerError!void {
    var iterations: usize = 0;
    while (try evalMetaCondition(module, context, active.*, meta_while.condition)) {
        if (iterations >= max_meta_loop_iterations) return error.MetaLoopLimitExceeded;
        try lowerScopedStatementSlice(allocator, module, active, output_stack, meta_while.body, context);
        iterations += 1;
    }
}

fn lowerMetaForRange(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    meta_for: ast.MetaForRangeStatement,
    context: *LowerContext,
) LowerError!void {
    switch (meta_for.source) {
        .range => |*range| try lowerMetaForIntegerRange(allocator, module, active, output_stack, meta_for.name, range.start, range.end, meta_for.body, context),
        .list => |*node| try lowerMetaForList(allocator, module, active, output_stack, meta_for.name, node, meta_for.body, context),
    }
}

fn lowerMetaForIntegerRange(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    name: []const u8,
    start_node: expr.Node,
    end_node: expr.Node,
    body: []const ast.Statement,
    context: *LowerContext,
) LowerError!void {
    const start = try evalIntegerAtContext(module, context, active.*, &start_node);
    const end = try evalIntegerAtContext(module, context, active.*, &end_node);
    if (end < start) return error.InvalidMetaFor;

    const iteration_count = end - start;
    if (iteration_count > max_meta_loop_iterations) return error.MetaLoopLimitExceeded;

    var value = start;
    while (value < end) : (value += 1) {
        try context.scopes.append(allocator, .{});
        {
            defer discardLastScope(context, allocator);
            try defineLocalValue(context, allocator, name, value_mod.Value.int(value), .@"const");
            try lowerStatementSlice(allocator, module, active, output_stack, body, context);
        }
    }
}

fn lowerMetaForList(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    name: []const u8,
    node: *const expr.Node,
    body: []const ast.Statement,
    context: *LowerContext,
) LowerError!void {
    var value = try evalValueAtContext(allocator, module, context, active.*, node);
    defer value.deinit(allocator);
    const list = value.expectList() catch return error.InvalidMetaFor;
    if (list.items.len > max_meta_loop_iterations) return error.MetaLoopLimitExceeded;

    for (list.items) |item| {
        try context.scopes.append(allocator, .{});
        {
            defer discardLastScope(context, allocator);
            var local_value = try item.clone(allocator);
            var local_owned_by_scope = false;
            errdefer if (!local_owned_by_scope) local_value.deinit(allocator);
            try defineLocalValue(context, allocator, name, local_value, .@"const");
            local_owned_by_scope = true;
            try lowerStatementSlice(allocator, module, active, output_stack, body, context);
        }
    }
}

fn addLowerErrorDiagnostic(
    allocator: Allocator,
    module: *module_mod.Module,
    span: source.SourceSpan,
    err: anyerror,
) Allocator.Error!void {
    const message = try std.fmt.allocPrint(allocator, "lowering failed: {s}", .{@errorName(err)});
    defer allocator.free(message);
    try module.diagnostics.add(allocator, .err, span, message);
}

fn lowerValueDeclaration(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    declaration: ast.ValueDeclarationStatement,
) LowerError!void {
    var evaluated = try lowerValueInitializer(module, context, active, declaration.value);
    errdefer evaluated.deinit(module.allocator);
    const annotation = try typecheck.annotationFromName(module, declaration.type_name);
    if (declaration.type_name != null and annotation == null) return error.InvalidValueDeclaration;
    try typecheck.coerceValueToAnnotation(module, &evaluated, annotation);

    if (context.scopes.items.len != 0) {
        try defineLocalValue(context, module.allocator, declaration.name, evaluated, declaration.mutability);
        return;
    }

    const symbol_id = try module.defineValue(
        declaration.name,
        evaluated,
        declaration.mutability,
        declaration.span,
    );
    if (symbol_id.index >= module.symbols.items.items.len) return error.InvalidSymbol;
}

fn lowerAssignment(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    assignment: ast.AssignmentStatement,
) LowerError!void {
    var evaluated = try lowerValueInitializer(module, context, active, assignment.value);
    errdefer evaluated.deinit(module.allocator);

    if (try setLocalValue(context, module.allocator, assignment.name, evaluated)) {
        return;
    }

    if (context.value_function_depth != 0) return error.SideEffectInValueFunction;
    try module.setValue(assignment.name, evaluated);
}

fn lowerValueInitializer(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    initializer: ast.ValueInitializer,
) LowerError!value_mod.Value {
    return switch (initializer) {
        .expression => |*node| evalValueAtContext(module.allocator, module, context, active, node),
        .struct_literal => |literal| .{ .@"struct" = try structValueFromLiteral(module.allocator, module, context, active, literal) },
    };
}

fn lowerStructDeclaration(
    allocator: Allocator,
    module: *module_mod.Module,
    declaration: ast.StructDeclarationStatement,
) LowerError!void {
    var specs = try allocator.alloc(types.StructFieldSpec, declaration.fields.len);
    defer allocator.free(specs);

    for (declaration.fields, 0..) |field, index| {
        const field_type = try lowerTypeName(module, field.type_name);
        const default_value = if (field.default_value) |default_text| default: {
            const stored_type = try module.types.get(field_type);
            switch (stored_type.*) {
                .int => {},
                .void, .array, .pointer, .@"struct", .@"union" => return error.InvalidStructField,
            }
            break :default try lowerStructFieldDefault(allocator, module, default_text);
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

fn lowerStructFieldDefault(
    allocator: Allocator,
    module: *module_mod.Module,
    default_value: ?[]const u8,
) LowerError!?u64 {
    const text = default_value orelse return null;
    var expression = expr.parseOwned(allocator, text) catch |err| return mapExpressionError(err);
    defer expression.deinit(allocator);
    return try evalInteger(module, &expression);
}

fn lowerTypeName(module: *module_mod.Module, name: []const u8) LowerError!types.TypeId {
    if (module.lookupTypeName(name)) |id| return id;
    if (std.mem.eql(u8, name, "u8")) return module.getOrAddIntType("u8", 8, .unsigned);
    if (std.mem.eql(u8, name, "u16")) return module.getOrAddIntType("u16", 16, .unsigned);
    if (std.mem.eql(u8, name, "u32")) return module.getOrAddIntType("u32", 32, .unsigned);
    if (std.mem.eql(u8, name, "u64")) return module.getOrAddIntType("u64", 64, .unsigned);
    if (std.mem.eql(u8, name, "i8")) return module.getOrAddIntType("i8", 8, .signed);
    if (std.mem.eql(u8, name, "i16")) return module.getOrAddIntType("i16", 16, .signed);
    if (std.mem.eql(u8, name, "i32")) return module.getOrAddIntType("i32", 32, .signed);
    if (std.mem.eql(u8, name, "i64")) return module.getOrAddIntType("i64", 64, .signed);
    return error.UnknownTypeName;
}

fn lowerApiCall(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    call: ast.ApiCallStatement,
    context: *LowerContext,
) LowerError!void {
    if (std.mem.eql(u8, call.callee, "include")) {
        try lowerIncludeOrImportCall(allocator, module, active, output_stack, call, context, .include);
        return;
    }

    if (std.mem.eql(u8, call.callee, "import")) {
        try lowerIncludeOrImportCall(allocator, module, active, output_stack, call, context, .import_once);
        return;
    }

    if (context.functions.lookupIndex(call.callee)) |function_index| {
        try lowerMetaFunctionCall(allocator, module, active, output_stack, context, function_index, call);
        return;
    }

    if (std.mem.eql(u8, call.callee, "print")) {
        try lowerDiagnosticCall(allocator, module, context, active.*, call, .note);
        return;
    }

    if (std.mem.eql(u8, call.callee, "warn")) {
        try lowerDiagnosticCall(allocator, module, context, active.*, call, .warning);
        return;
    }

    if (std.mem.eql(u8, call.callee, "err")) {
        try lowerDiagnosticCall(allocator, module, context, active.*, call, .err);
        return error.FrontendDiagnostics;
    }

    if (std.mem.eql(u8, call.callee, "assert")) {
        try lowerAssertCall(allocator, module, context, active.*, call);
        return;
    }

    if (std.mem.eql(u8, call.callee, "isa")) {
        try lowerIsaCall(module, context, active, call);
        return;
    }

    if (std.mem.eql(u8, call.callee, "label.define")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var value = try valueArgAtContext(module.allocator, module, context, active.*, call, 0);
        defer value.deinit(module.allocator);
        const name = switch (value) {
            .string => |text| text,
            .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
        };
        if (!identifier.isName(name)) return error.InvalidApiArgument;
        const fragment_position = try activeFragmentPosition(module, active.section_id);
        const label_id = try module.defineAnchoredLabel(name, active.section_id, active.offset, fragment_position, call.span);
        if (label_id.index >= module.symbols.items.items.len) return error.InvalidSymbol;
        return;
    }

    if (std.mem.eql(u8, call.callee, "origin")) {
        try requireArgCount(call, 1);
        try module.setOrigin(active.section_id, try integerArgAtContext(module, context, active.*, call, 0));
        return;
    }

    if (std.mem.eql(u8, call.callee, "region.begin")) {
        try requireArgCount(call, 3);
        const name = try sourcePathArgAtContext(module.allocator, module, context, active.*, call, 0);
        defer module.allocator.free(name);
        const origin = try integerArgAtContext(module, context, active.*, call, 1);
        const file_offset = try integerArgAtContext(module, context, active.*, call, 2);
        active.* = .{
            .section_id = try module.createOutputSection(name, origin, file_offset),
            .offset = 0,
            .file_offset = 0,
            .file_aligned = false,
            .target = active.target,
        };
        return;
    }

    if (std.mem.eql(u8, call.callee, "region.file_align")) {
        try requireArgCount(call, 1);
        try syncActiveOutputOffsetForLayoutApi(module, active);
        const alignment = try integerArgAtContext(module, context, active.*, call, 0);
        if (!isPowerOfTwoNonZero(alignment)) return error.InvalidAlignment;
        try module.setFileSizeAlignment(active.section_id, alignment);
        active.file_offset = try alignForward(active.file_offset, alignment);
        active.file_aligned = true;
        return;
    }

    if (std.mem.eql(u8, call.callee, "output.org") or
        std.mem.eql(u8, call.callee, "output.section"))
    {
        try requireArgCount(call, 2);
        try requireOpenOutputRegion(active.*);
        try syncActiveOutputOffsetForLayoutApi(module, active);

        const current_section = try module.sections.get(active.section_id);
        if (current_section.kind != .main) return error.InvalidApiCall;

        const name = try sourcePathArgAtContext(module.allocator, module, context, active.*, call, 0);
        defer module.allocator.free(name);
        const origin = try integerArgAtContext(module, context, active.*, call, 1);
        const relative_file_offset = if (std.mem.eql(u8, call.callee, "output.org"))
            active.offset
        else
            active.file_offset;
        const file_offset = try checkedAdd(current_section.file_offset, relative_file_offset);
        active.* = .{
            .section_id = try module.createOutputSection(name, origin, file_offset),
            .offset = 0,
            .file_offset = 0,
            .file_aligned = false,
            .target = active.target,
        };
        return;
    }

    if (std.mem.eql(u8, call.callee, "virtual.begin")) {
        if (call.args.len != 0 and call.args.len != 1) return error.InvalidApiArity;
        const origin = if (call.args.len == 1)
            try integerArgAtContext(module, context, active.*, call, 0)
        else
            try activeAddress(module, active.*);
        try output_stack.append(module.allocator, active.*);
        errdefer discardLastActiveOutput(output_stack);
        active.* = .{
            .section_id = try module.createVirtualSection(origin),
            .offset = 0,
            .file_offset = 0,
            .file_aligned = false,
            .target = active.target,
        };
        return;
    }

    if (std.mem.eql(u8, call.callee, "virtual.end")) {
        try requireArgCount(call, 0);
        active.* = output_stack.pop() orelse return error.UnmatchedVirtualEnd;
        module.target = active.target;
        return;
    }

    if (std.mem.eql(u8, call.callee, "x86.use16")) {
        try requireArgCount(call, 0);
        active.target = try target.Target.initX86(16);
        module.target = active.target;
        return;
    }

    if (std.mem.eql(u8, call.callee, "x86.use32")) {
        try requireArgCount(call, 0);
        active.target = try target.Target.initX86(32);
        module.target = active.target;
        return;
    }

    if (std.mem.eql(u8, call.callee, "x86.use64")) {
        try requireArgCount(call, 0);
        active.target = try target.Target.initX86(64);
        module.target = active.target;
        return;
    }

    if (std.mem.eql(u8, call.callee, "riscv.use32")) {
        try requireArgCount(call, 0);
        active.target = try target.Target.initRiscv(32);
        module.target = active.target;
        return;
    }

    if (std.mem.eql(u8, call.callee, "riscv.use64")) {
        try requireArgCount(call, 0);
        active.target = try target.Target.initRiscv(64);
        module.target = active.target;
        return;
    }

    if (dataEmitByteCount(call.callee)) |byte_count| {
        try requireOpenOutputRegion(active.*);
        try lowerDataEmitCall(module, context, active, call, byte_count);
        return;
    }

    if (dataReserveScale(call.callee)) |scale| {
        try requireOpenOutputRegion(active.*);
        try lowerDataReserveCall(module, context, active, call, scale);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.u8")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        const value = try u8ArgAtContext(module, context, active.*, call, 0);
        const fragment_id = try module.emitBytes(active.section_id, &.{value}, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.u16")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var bytes: [2]u8 = undefined;
        std.mem.writeInt(u16, &bytes, try u16ArgAtContext(module, context, active.*, call, 0), .little);
        const fragment_id = try module.emitBytes(active.section_id, &bytes, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.u32")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var bytes: [4]u8 = undefined;
        std.mem.writeInt(u32, &bytes, try u32ArgAtContext(module, context, active.*, call, 0), .little);
        const fragment_id = try module.emitBytes(active.section_id, &bytes, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.u64")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var bytes: [8]u8 = undefined;
        std.mem.writeInt(u64, &bytes, try integerArgAtContext(module, context, active.*, call, 0), .little);
        const fragment_id = try module.emitBytes(active.section_id, &bytes, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.bytes")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var value = try valueArgAtContext(module.allocator, module, context, active.*, call, 0);
        defer value.deinit(module.allocator);
        const bytes = switch (value) {
            .bytes => |data| data,
            .string => |text| text,
            .void, .integer, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
        };
        const fragment_id = try module.emitBytes(active.section_id, bytes, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "emit.struct")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        var value = try valueArgAtContext(module.allocator, module, context, active.*, call, 0);
        defer value.deinit(module.allocator);
        const struct_value = switch (value) {
            .@"struct" => |stored| stored,
            .void, .integer, .boolean, .string, .bytes, .type, .list, .map => return error.InvalidApiArgument,
        };
        const bytes = try emitStructValue(module, struct_value);
        defer module.allocator.free(bytes);
        const fragment_id = try module.emitBytes(active.section_id, bytes, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "store.u8") or
        std.mem.eql(u8, call.callee, "store.u16") or
        std.mem.eql(u8, call.callee, "store.u32") or
        std.mem.eql(u8, call.callee, "store.u64"))
    {
        const byte_count = storeByteCount(call.callee) orelse return error.InvalidApiCall;
        try requireArgCount(call, 2);
        try materializeInstructionBytesForOutputAccess(module);
        const store_target = try outputStoreTargetAtContext(module, context, active.*, call, 0);
        const value = try integerArgAtContext(module, context, active.*, call, 1);
        try module.storeIntegerAt(store_target.section, store_target.address, value, byte_count);
        return;
    }

    if (std.mem.eql(u8, call.callee, "store.bytes")) {
        try requireArgCount(call, 2);
        try materializeInstructionBytesForOutputAccess(module);
        const store_target = try outputStoreTargetAtContext(module, context, active.*, call, 0);
        var value = try valueArgAtContext(module.allocator, module, context, active.*, call, 1);
        defer value.deinit(module.allocator);
        const bytes = switch (value) {
            .bytes => |data| data,
            .string => |text| text,
            .void, .integer, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
        };
        try module.storeBytesAt(store_target.section, store_target.address, bytes);
        return;
    }

    if (std.mem.eql(u8, call.callee, "reserve")) {
        try requireOpenOutputRegion(active.*);
        try requireArgCount(call, 1);
        const fragment_id = try module.reserve(active.section_id, try integerArgAtContext(module, context, active.*, call, 0), 1, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "pad")) {
        try requireOpenOutputRegion(active.*);
        if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
        try syncActiveOutputOffsetForLayoutApi(module, active);
        const size = try integerArgAtContext(module, context, active.*, call, 0);
        const fill = if (call.args.len == 2) try u8ArgAtContext(module, context, active.*, call, 1) else 0;
        const fragment_id = try module.emitRepeatedByte(active.section_id, fill, size, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "pad_to")) {
        try requireOpenOutputRegion(active.*);
        if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
        try syncActiveOutputOffsetForLayoutApi(module, active);
        const target_offset = try integerArgAtContext(module, context, active.*, call, 0);
        const materialized_offset = try materializedOffset(active.offset, active.file_offset);
        if (target_offset < materialized_offset) return error.InvalidApiInteger;
        const fill = if (call.args.len == 2) try u8ArgAtContext(module, context, active.*, call, 1) else 0;
        const size = target_offset - materialized_offset;
        const fragment_id = try module.emitRepeatedByte(active.section_id, fill, size, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    if (std.mem.eql(u8, call.callee, "align")) {
        try requireOpenOutputRegion(active.*);
        if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
        try syncActiveOutputOffsetForLayoutApi(module, active);
        const alignment = try integerArgAtContext(module, context, active.*, call, 0);
        if (!isPowerOfTwoNonZero(alignment)) return error.InvalidAlignment;
        const fill = if (call.args.len == 2) try u8ArgAtContext(module, context, active.*, call, 1) else 0;
        const fragment_id = try module.addAlignment(active.section_id, alignment, fill, call.span);
        try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
        return;
    }

    return error.UnknownApiCall;
}

fn lowerIsaCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
) LowerError!void {
    try requireOpenOutputRegion(active.*);
    try requireArgCount(call, 1);
    var value = try valueArgAtContext(module.allocator, module, context, active.*, call, 0);
    defer value.deinit(module.allocator);
    const text = switch (value) {
        .string => |stored| stored,
        .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
    };
    if (text.len == 0 or std.mem.indexOfAny(u8, text, "\r\n") != null) return error.InvalidApiArgument;

    const lowered_text = try lowerIsaText(module.allocator, module, context, active.*, text);
    defer module.allocator.free(lowered_text);
    const fragment_id = try module.appendIsaInstruction(
        active.section_id,
        active.target,
        lowered_text,
        call.span,
    );
    try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
}

fn lowerDataEmitCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    byte_count: u8,
) LowerError!void {
    if (call.args.len == 0) return error.InvalidApiArity;

    var bytes: std.ArrayList(u8) = .empty;
    defer bytes.deinit(module.allocator);

    for (call.args, 0..) |_, index| {
        if (byte_count == 1) {
            var value = try valueArgAtContext(module.allocator, module, context, active.*, call, index);
            defer value.deinit(module.allocator);
            switch (value) {
                .integer => |integer| try appendIntegerBytes(module.allocator, &bytes, integer.value, byte_count),
                .string => |text| try bytes.appendSlice(module.allocator, text),
                .bytes => |data| try bytes.appendSlice(module.allocator, data),
                .void, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            }
        } else {
            const value = try integerArgAtContext(module, context, active.*, call, index);
            try appendIntegerBytes(module.allocator, &bytes, value, byte_count);
        }
    }

    const fragment_id = try module.emitBytes(active.section_id, bytes.items, call.span);
    try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
}

fn lowerDataReserveCall(
    module: *module_mod.Module,
    context: *LowerContext,
    active: *ActiveOutput,
    call: ast.ApiCallStatement,
    scale: u64,
) LowerError!void {
    try requireArgCount(call, 1);
    const count = try integerArgAtContext(module, context, active.*, call, 0);
    const byte_count = std.math.mul(u64, count, scale) catch return error.InvalidApiInteger;
    const fragment_id = try module.reserve(active.section_id, byte_count, 1, call.span);
    try advanceActiveOutput(active, module.fragments.items.items[fragment_id.index]);
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

fn lowerDiagnosticCall(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    severity: diagnostic.Severity,
) LowerError!void {
    if (call.args.len == 0) return error.InvalidApiArity;

    const message = try formatDiagnosticMessage(allocator, module, context, active, call);
    defer allocator.free(message);
    try module.diagnostics.add(allocator, severity, call.span, message);
}

fn lowerAssertCall(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
) LowerError!void {
    if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
    const condition = try booleanArgAtContext(module, context, active, call, 0);
    if (condition) return;

    const message = if (call.args.len == 2)
        try formatDiagnosticArgument(allocator, module, context, active, &call.args[1])
    else
        try allocator.dupe(u8, "assertion failed");
    defer allocator.free(message);

    try module.diagnostics.add(allocator, .err, call.span, message);
    return error.FrontendDiagnostics;
}

fn lowerMetaFunctionCall(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    context: *LowerContext,
    function_index: usize,
    call: ast.ApiCallStatement,
) LowerError!void {
    const function = try context.functions.get(function_index);
    if (function.return_type_name != null) return error.InvalidMetaFunction;
    const params = function.params;
    const body = function.body;

    if (call.args.len != params.len) return error.InvalidApiArity;
    if (context.call_depth >= max_meta_call_depth) return error.MetaCallDepthExceeded;

    context.call_depth += 1;
    defer context.call_depth -= 1;

    try context.scopes.append(allocator, .{});
    defer discardLastScope(context, allocator);

    for (params, 0..) |param, index| {
        const annotation = try typecheck.annotationFromName(module, param.type_name);
        if (param.type_name != null and annotation == null) return error.InvalidMetaFunction;
        var value = try valueArgAtContext(allocator, module, context, active.*, call, index);
        errdefer value.deinit(allocator);
        try typecheck.coerceValueToAnnotation(module, &value, annotation);
        try defineLocalValue(context, allocator, param.name, value, .@"const");
    }

    try lowerStatementSlice(allocator, module, active, output_stack, body, context);
}

fn evalUserValueFunction(
    context: *anyopaque,
    allocator: Allocator,
    name: []const u8,
    args: []const expr.BuiltinArgument,
    eval_ctx: *expr.EvalContext,
) expr.ExpressionError!value_mod.Value {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const function_index = eval_ctx.module.value_functions.lookupIndex(name) orelse return error.InvalidOperand;
    const active_section = eval_ctx.active_section orelse return error.MissingEvaluationContext;
    const active: ActiveOutput = .{
        .section_id = active_section,
        .offset = eval_ctx.active_offset,
        .file_offset = eval_ctx.active_file_offset orelse eval_ctx.active_offset,
        .target = eval_ctx.module.target,
    };
    var output_stack: std.ArrayList(ActiveOutput) = .empty;
    defer output_stack.deinit(allocator);
    return evalUserValueFunctionAt(allocator, eval_ctx.module, lower_context, active, &output_stack, function_index, args) catch |err| return mapLowerErrorToExpression(err);
}

fn evalStructLiteralValue(
    context: *anyopaque,
    allocator: Allocator,
    text: []const u8,
    eval_ctx: *expr.EvalContext,
) expr.ExpressionError!value_mod.Value {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const active_section = eval_ctx.active_section orelse return error.MissingEvaluationContext;
    const active: ActiveOutput = .{
        .section_id = active_section,
        .offset = eval_ctx.active_offset,
        .file_offset = eval_ctx.active_file_offset orelse eval_ctx.active_offset,
        .target = eval_ctx.module.target,
    };
    var literal = parser.parseStructLiteralText(allocator, text) catch |err| return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.InvalidApiArgument,
    };
    defer literal.deinit(allocator);
    return .{ .@"struct" = structValueFromLiteral(allocator, eval_ctx.module, lower_context, active, literal) catch |err| return mapLowerErrorToExpression(err) };
}

pub fn evalModuleValueFunction(
    context: *anyopaque,
    allocator: Allocator,
    name: []const u8,
    args: []const expr.BuiltinArgument,
    eval_ctx: *expr.EvalContext,
) expr.ExpressionError!value_mod.Value {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const function_index = eval_ctx.module.value_functions.lookupIndex(name) orelse return error.InvalidOperand;
    const active_section = eval_ctx.active_section orelse return error.MissingEvaluationContext;
    const active: ActiveOutput = .{
        .section_id = active_section,
        .offset = eval_ctx.active_offset,
        .file_offset = eval_ctx.active_file_offset orelse eval_ctx.active_offset,
        .target = eval_ctx.module.target,
    };
    var output_stack: std.ArrayList(ActiveOutput) = .empty;
    defer output_stack.deinit(allocator);
    return evalUserValueFunctionAt(allocator, eval_ctx.module, lower_context, active, &output_stack, function_index, args) catch |err| return mapLowerErrorToExpression(err);
}

pub fn evalModuleStructLiteralValue(
    context: *anyopaque,
    allocator: Allocator,
    text: []const u8,
    eval_ctx: *expr.EvalContext,
) expr.ExpressionError!value_mod.Value {
    return evalStructLiteralValue(context, allocator, text, eval_ctx);
}

fn evalUserValueFunctionAt(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    function_index: usize,
    args: []const expr.BuiltinArgument,
) LowerError!value_mod.Value {
    const function = try module.value_functions.get(function_index);
    const return_type_name = function.return_type_name orelse return error.InvalidMetaFunction;
    if (args.len != function.params.len) return error.InvalidApiArity;
    if (context.call_depth >= max_meta_call_depth) return error.MetaCallDepthExceeded;

    context.call_depth += 1;
    defer context.call_depth -= 1;
    context.value_function_depth += 1;
    defer context.value_function_depth -= 1;

    const previous_return = context.return_value;
    context.return_value = null;
    defer {
        if (context.return_value) |*stored| {
            stored.deinit(allocator);
        }
        context.return_value = previous_return;
    }

    var scoped_active = active;
    try context.scopes.append(allocator, .{});
    defer discardLastScope(context, allocator);

    var eval_ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = fileResolver(context),
        .source_path = currentSourcePath(context),
        .local_context = context,
        .resolve_local = resolveLocalValue,
        .next_unique_symbol = nextUniqueSymbol,
        .call_user_function = evalUserValueFunction,
        .evaluate_struct_literal = evalStructLiteralValue,
    };
    for (function.params, 0..) |param, index| {
        const annotation = try typecheck.annotationFromName(module, param.type_name);
        if (param.type_name != null and annotation == null) return error.InvalidMetaFunction;
        var value = expr.evaluateBuiltinValueArg(allocator, args[index], &eval_ctx) catch |err| return mapExpressionError(err);
        errdefer value.deinit(allocator);
        try typecheck.coerceValueToAnnotation(module, &value, annotation);
        try defineLocalValue(context, allocator, param.name, value, .@"const");
    }

    lowerStatementSlice(allocator, module, &scoped_active, output_stack, function.body, context) catch |err| {
        if (err != error.MetaFunctionReturned) return err;
    };
    var result = context.return_value orelse return error.MissingMetaReturn;
    context.return_value = null;
    errdefer result.deinit(allocator);

    const annotation = (try typecheck.annotationFromName(module, return_type_name)) orelse return error.InvalidMetaFunction;
    try typecheck.coerceValueToAnnotation(module, &result, annotation);
    return result;
}

fn mapLowerErrorToExpression(err: LowerError) expr.ExpressionError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnknownTypeName => error.UnknownTypeName,
        error.UnknownField => error.UnknownField,
        error.DivisionByZero => error.DivisionByZero,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.InvalidIntegerBits => error.InvalidIntegerBits,
        error.InvalidType => error.InvalidType,
        error.InvalidSection => error.InvalidSection,
        error.MissingStructFieldValue => error.MissingStructFieldValue,
        error.OffsetOverflow => error.OffsetOverflow,
        error.FileNotAvailable => error.FileNotAvailable,
        error.InvalidValueDeclaration,
        error.InvalidExpression,
        error.InvalidApiArity,
        error.InvalidMetaFunction,
        error.MissingMetaReturn,
        error.SideEffectInValueFunction,
        => error.InvalidOperand,
        else => error.InvalidOperand,
    };
}

fn discardLastScope(context: *LowerContext, allocator: Allocator) void {
    if (context.scopes.items.len == 0) return;
    const last_index = context.scopes.items.len - 1;
    var scope = context.scopes.items[last_index];
    context.scopes.shrinkRetainingCapacity(last_index);
    scope.deinit(allocator);
}

pub fn pushMetaScope(context: *LowerContext, allocator: Allocator) Allocator.Error!void {
    try context.scopes.append(allocator, .{});
}

pub fn popMetaScope(context: *LowerContext, allocator: Allocator) void {
    discardLastScope(context, allocator);
}

pub fn defineFinalLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,
) LowerError!void {
    try defineLocalValue(context, allocator, name, value, mutability);
}

pub fn setFinalLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
) LowerError!bool {
    return setLocalValue(context, allocator, name, value);
}

fn defineLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    value: value_mod.Value,
    mutability: value_mod.Mutability,
) LowerError!void {
    if (context.scopes.items.len == 0) return error.InvalidMetaBlock;
    var scope = &context.scopes.items[context.scopes.items.len - 1];
    for (scope.locals.items) |local| {
        if (std.mem.eql(u8, local.name, name)) return error.DuplicateSymbol;
    }
    try scope.locals.append(allocator, .{
        .name = name,
        .value = value,
        .mutability = mutability,
    });
}

fn setLocalValue(
    context: *LowerContext,
    allocator: Allocator,
    name: []const u8,
    new_value: value_mod.Value,
) LowerError!bool {
    var scope_index = context.scopes.items.len;
    while (scope_index != 0) {
        scope_index -= 1;
        const scope = &context.scopes.items[scope_index];
        var local_index = scope.locals.items.len;
        while (local_index != 0) {
            local_index -= 1;
            const local = &scope.locals.items[local_index];
            if (std.mem.eql(u8, local.name, name)) {
                if (local.mutability != .let) return error.InvalidValueDeclaration;
                local.value.deinit(allocator);
                local.value = new_value;
                return true;
            }
        }
    }
    return false;
}

fn lookupLocalValue(context: *const LowerContext, name: []const u8) ?*const value_mod.Value {
    var scope_index = context.scopes.items.len;
    while (scope_index != 0) {
        scope_index -= 1;
        const scope = &context.scopes.items[scope_index];
        var local_index = scope.locals.items.len;
        while (local_index != 0) {
            local_index -= 1;
            const local = &scope.locals.items[local_index];
            if (std.mem.eql(u8, local.name, name)) return &local.value;
        }
    }
    return null;
}

pub fn resolveLocalValue(context: *anyopaque, allocator: Allocator, name: []const u8) expr.ExpressionError!?value_mod.Value {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const local = lookupLocalValue(lower_context, name) orelse return null;
    return try local.clone(allocator);
}

fn nextUniqueSymbol(context: *anyopaque, allocator: Allocator, prefix: []const u8) expr.ExpressionError![]u8 {
    const lower_context: *LowerContext = @ptrCast(@alignCast(context));
    const index = lower_context.unique_symbol_counter;
    lower_context.unique_symbol_counter = std.math.add(u64, lower_context.unique_symbol_counter, 1) catch return error.InvalidNumber;
    return std.fmt.allocPrint(allocator, "{s}__{}", .{ prefix, index });
}

const SourceLoadMode = enum {
    include,
    import_once,
};

fn lowerIncludeOrImportCall(
    allocator: Allocator,
    module: *module_mod.Module,
    active: *ActiveOutput,
    output_stack: *std.ArrayList(ActiveOutput),
    call: ast.ApiCallStatement,
    context: *LowerContext,
    mode: SourceLoadMode,
) LowerError!void {
    try requireArgCount(call, 1);
    if (output_stack.items.len != 0) return error.InvalidApiCall;
    if (mode == .import_once and context.scopes.items.len != 0) return error.InvalidMetaBlock;

    const include_path = try sourcePathArgAtContext(allocator, module, context, active.*, call, 0);
    defer allocator.free(include_path);

    const resolver = context.include_resolver orelse return error.IncludeNotAvailable;
    var include_source = try resolver.resolve(resolver.context, allocator, .{
        .path = include_path,
        .parent_path = currentSourcePath(context),
        .span = call.span,
    });
    defer include_source.deinit(allocator);

    if (sourceStackContains(context, include_source.path)) return error.IncludeCycle;

    if (mode == .import_once) {
        if (sourceImported(context, include_source.path)) return;
        try rememberImportedSource(allocator, context, include_source.path);
    }

    try lowerSourceIntoModuleWithPathInternal(allocator, module, include_source.path, include_source.bytes, context);
    active.offset = try sectionCursor(module, active.section_id);
    active.target = module.target;
}

fn currentSourcePath(context: *const LowerContext) ?[]const u8 {
    if (context.source_stack.items.len == 0) return null;
    return context.source_stack.items[context.source_stack.items.len - 1];
}

fn sourceStackContains(context: *const LowerContext, path: []const u8) bool {
    for (context.source_stack.items) |stored_path| {
        if (std.mem.eql(u8, stored_path, path)) return true;
    }
    return false;
}

fn sourceImported(context: *const LowerContext, path: []const u8) bool {
    for (context.imported_sources.items) |stored_path| {
        if (std.mem.eql(u8, stored_path, path)) return true;
    }
    return false;
}

fn rememberImportedSource(
    allocator: Allocator,
    context: *LowerContext,
    path: []const u8,
) Allocator.Error!void {
    const owned_path = try allocator.dupe(u8, path);
    errdefer allocator.free(owned_path);
    try context.imported_sources.append(allocator, owned_path);
}

fn activeAddress(module: *const module_mod.Module, active: ActiveOutput) LowerError!u64 {
    const active_section = try module.sections.get(active.section_id);
    return std.math.add(u64, active_section.origin, active.offset) catch error.OffsetOverflow;
}

fn requireOpenOutputRegion(active: ActiveOutput) LowerError!void {
    if (active.file_aligned) return error.OutputRegionClosed;
}

fn requireArgCount(call: ast.ApiCallStatement, expected: usize) LowerError!void {
    if (call.args.len != expected) return error.InvalidApiArity;
}

fn integerArg(module: *module_mod.Module, call: ast.ApiCallStatement, index: usize) LowerError!u64 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| evalInteger(module, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn integerArgAt(
    module: *module_mod.Module,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u64 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| evalIntegerAt(module, active, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn integerArgAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u64 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| evalIntegerAtContext(module, context, active, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn valueArgAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!value_mod.Value {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| evalValueAtContext(allocator, module, context, active, node),
        .string => |text| .{ .string = try allocator.dupe(u8, text) },
        .struct_literal => |literal| .{ .@"struct" = try structValueFromLiteral(allocator, module, context, active, literal) },
    };
}

fn booleanArgAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!bool {
    var value = try valueArgAtContext(module.allocator, module, context, active, call, index);
    defer value.deinit(module.allocator);
    return value.expectBoolean() catch error.InvalidApiArgument;
}

fn u8Arg(module: *module_mod.Module, call: ast.ApiCallStatement, index: usize) LowerError!u8 {
    const value = try integerArg(module, call, index);
    if (value > std.math.maxInt(u8)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u8ArgAt(
    module: *module_mod.Module,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u8 {
    const value = try integerArgAt(module, active, call, index);
    if (value > std.math.maxInt(u8)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u8ArgAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u8 {
    const value = try integerArgAtContext(module, context, active, call, index);
    if (value > std.math.maxInt(u8)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u16Arg(module: *module_mod.Module, call: ast.ApiCallStatement, index: usize) LowerError!u16 {
    const value = try integerArg(module, call, index);
    if (value > std.math.maxInt(u16)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u16ArgAt(
    module: *module_mod.Module,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u16 {
    const value = try integerArgAt(module, active, call, index);
    if (value > std.math.maxInt(u16)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u16ArgAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u16 {
    const value = try integerArgAtContext(module, context, active, call, index);
    if (value > std.math.maxInt(u16)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u32Arg(module: *module_mod.Module, call: ast.ApiCallStatement, index: usize) LowerError!u32 {
    const value = try integerArg(module, call, index);
    if (value > std.math.maxInt(u32)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u32ArgAt(
    module: *module_mod.Module,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u32 {
    const value = try integerArgAt(module, active, call, index);
    if (value > std.math.maxInt(u32)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn u32ArgAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!u32 {
    const value = try integerArgAtContext(module, context, active, call, index);
    if (value > std.math.maxInt(u32)) return error.InvalidApiInteger;
    return @intCast(value);
}

fn bytesArg(call: ast.ApiCallStatement, index: usize) LowerError![]const u8 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .string => |value| value,
        .expression, .struct_literal => error.InvalidApiArgument,
    };
}

fn sourcePathArgAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError![]u8 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .string => |text| try allocator.dupe(u8, text),
        .expression, .struct_literal => {
            var value = try valueArgAtContext(allocator, module, context, active, call, index);
            defer value.deinit(allocator);
            const text = switch (value) {
                .string => |stored| stored,
                .void, .integer, .boolean, .bytes, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
            };
            return allocator.dupe(u8, text);
        },
    };
}

const OutputStoreTarget = struct {
    section: fragment.SectionId,
    address: u64,
};

fn outputStoreTargetAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
    index: usize,
) LowerError!OutputStoreTarget {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| switch (node.*) {
            .symbol => |name| outputStoreTargetFromName(module, context, active, node, name),
            else => .{
                .section = try outputStoreExpressionSection(module, context, active, node),
                .address = try evalIntegerAtContext(module, context, active, node),
            },
        },
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn outputStoreExpressionSection(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
) LowerError!fragment.SectionId {
    if (try outputStoreLabelSection(module, context, node)) |section_id| return section_id;
    return active.section_id;
}

fn outputStoreLabelSection(
    module: *module_mod.Module,
    context: *LowerContext,
    node: *const expr.Node,
) LowerError!?fragment.SectionId {
    return switch (node.*) {
        .symbol => |name| blk: {
            if (lookupLocalValue(context, name) != null) break :blk null;
            const symbol_id = module.symbols.lookup(name) orelse break :blk null;
            const stored = try module.symbols.get(symbol_id);
            break :blk switch (stored.binding) {
                .label => |label| label.section,
                .absolute, .value, .unknown => null,
            };
        },
        .unary => |unary| outputStoreLabelSection(module, context, unary.operand),
        .binary => |binary| blk: {
            const left = try outputStoreLabelSection(module, context, binary.left);
            const right = try outputStoreLabelSection(module, context, binary.right);
            if (left) |left_section| {
                if (right) |right_section| {
                    if (left_section.index != right_section.index) return error.InvalidApiArgument;
                }
                break :blk left_section;
            }
            break :blk right;
        },
        .field_access => |access| outputStoreLabelSection(module, context, access.object),
        .builtin_call, .integer, .boolean, .string_literal, .bytes_literal => null,
    };
}

fn outputStoreTargetFromName(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
    name: []const u8,
) LowerError!OutputStoreTarget {
    if (lookupLocalValue(context, name) != null) {
        return .{
            .section = active.section_id,
            .address = try evalIntegerAtContext(module, context, active, node),
        };
    }

    const symbol_id = module.symbols.lookup(name) orelse {
        return .{
            .section = active.section_id,
            .address = try evalIntegerAtContext(module, context, active, node),
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
            .address = try evalIntegerAtContext(module, context, active, node),
        },
        .unknown => error.InvalidApiArgument,
    };
}

fn storeByteCount(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "store.u8")) return 1;
    if (std.mem.eql(u8, name, "store.u16")) return 2;
    if (std.mem.eql(u8, name, "store.u32")) return 4;
    if (std.mem.eql(u8, name, "store.u64")) return 8;
    return null;
}

fn dataEmitByteCount(name: []const u8) ?u8 {
    // api-matrix-lower: "db"
    // api-matrix-lower: "dw"
    // api-matrix-lower: "dd"
    // api-matrix-lower: "dq"
    if (std.mem.eql(u8, name, "db")) return 1;
    if (std.mem.eql(u8, name, "dw")) return 2;
    if (std.mem.eql(u8, name, "dd")) return 4;
    if (std.mem.eql(u8, name, "dq")) return 8;
    return null;
}

fn dataReserveScale(name: []const u8) ?u64 {
    // api-matrix-lower: "rb"
    // api-matrix-lower: "rw"
    // api-matrix-lower: "rd"
    // api-matrix-lower: "rq"
    if (std.mem.eql(u8, name, "rb")) return 1;
    if (std.mem.eql(u8, name, "rw")) return 2;
    if (std.mem.eql(u8, name, "rd")) return 4;
    if (std.mem.eql(u8, name, "rq")) return 8;
    return null;
}

fn cloneDeferredBlockFromAst(
    allocator: Allocator,
    meta_defer: ast.MetaDeferStatement,
) LowerError!output_mod.DeferredBlock {
    const body = try cloneDeferredStatementSlice(allocator, meta_defer.body);
    return .{
        .body = body,
        .span = meta_defer.span,
    };
}

fn freezeDeferredBlockFromAst(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    meta_defer: ast.MetaDeferStatement,
) LowerError!output_mod.DeferredBlock {
    const body = try freezeDeferredStatementSlice(allocator, module, context, active, meta_defer.body);
    return .{
        .body = body,
        .span = meta_defer.span,
    };
}

fn cloneDeferredStatementSlice(
    allocator: Allocator,
    statements: []const ast.Statement,
) LowerError![]output_mod.DeferredStatement {
    const cloned = try allocator.alloc(output_mod.DeferredStatement, statements.len);
    var cloned_len: usize = 0;
    errdefer {
        for (cloned[0..cloned_len]) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(cloned);
    }

    for (statements, 0..) |statement, index| {
        cloned[index] = try cloneDeferredStatement(allocator, statement);
        cloned_len += 1;
    }
    return cloned;
}

fn freezeDeferredStatementSlice(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statements: []const ast.Statement,
) LowerError![]output_mod.DeferredStatement {
    var frozen: std.ArrayList(output_mod.DeferredStatement) = .empty;
    errdefer {
        for (frozen.items) |*statement| {
            statement.deinit(allocator);
        }
        frozen.deinit(allocator);
    }

    for (statements) |statement| {
        try freezeDeferredStatementAppend(allocator, module, context, active, statement, &frozen);
    }

    return frozen.toOwnedSlice(allocator);
}

fn cloneDeferredStatement(
    allocator: Allocator,
    statement: ast.Statement,
) LowerError!output_mod.DeferredStatement {
    return switch (statement) {
        .api_call => |call| .{ .api_call = try cloneDeferredApiCall(allocator, call) },
        .meta_if => |meta_if| .{ .meta_if = try cloneDeferredMetaIf(allocator, meta_if) },
        // api-matrix-output: DeferredStatement.value_decl
        .value_decl => |declaration| .{ .value_decl = try cloneDeferredValueDeclaration(allocator, declaration) },
        // api-matrix-output: DeferredStatement.assignment
        .assignment => |assignment| .{ .assignment = try cloneDeferredAssignment(allocator, assignment) },
        // api-matrix-output: DeferredStatement.meta_while
        .meta_while => |meta_while| .{ .meta_while = try cloneDeferredMetaWhile(allocator, meta_while) },
        .label,
        .isa_instruction,
        .struct_decl,
        .legacy_directive,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => error.FinalizerCannotChangeLayout,
    };
}

fn freezeDeferredStatementAppend(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statement: ast.Statement,
    frozen: *std.ArrayList(output_mod.DeferredStatement),
) LowerError!void {
    switch (statement) {
        .api_call => |call| {
            var frozen_call = try freezeDeferredApiCall(allocator, context, call);
            errdefer frozen_call.deinit(allocator);
            try frozen.append(allocator, .{ .api_call = frozen_call });
        },
        // api-matrix-output: DeferredStatement.value_decl
        .value_decl => |declaration| {
            var frozen_declaration = try freezeDeferredValueDeclaration(allocator, context, declaration);
            errdefer frozen_declaration.deinit(allocator);
            try frozen.append(allocator, .{ .value_decl = frozen_declaration });
        },
        // api-matrix-output: DeferredStatement.assignment
        .assignment => |assignment| {
            var frozen_assignment = try freezeDeferredAssignment(allocator, context, assignment);
            errdefer frozen_assignment.deinit(allocator);
            try frozen.append(allocator, .{ .assignment = frozen_assignment });
        },
        .meta_if => |meta_if| {
            var frozen_if = try freezeDeferredMetaIf(allocator, module, context, active, meta_if);
            errdefer frozen_if.deinit(allocator);
            try frozen.append(allocator, .{ .meta_if = frozen_if });
        },
        // api-matrix-output: DeferredStatement.meta_while
        .meta_while => |meta_while| {
            var frozen_while = try freezeDeferredMetaWhile(allocator, module, context, active, meta_while);
            errdefer frozen_while.deinit(allocator);
            try frozen.append(allocator, .{ .meta_while = frozen_while });
        },
        .label,
        .isa_instruction,
        .struct_decl,
        .legacy_directive,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => return error.FinalizerCannotChangeLayout,
    }
}

fn freezeDeferredStatementSliceInto(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statements: []const ast.Statement,
    frozen: *std.ArrayList(output_mod.DeferredStatement),
) LowerError!void {
    for (statements) |statement| {
        try freezeDeferredStatementAppend(allocator, module, context, active, statement, frozen);
    }
}

fn cloneDeferredApiCall(
    allocator: Allocator,
    call: ast.ApiCallStatement,
) LowerError!output_mod.ApiCall {
    if (!isAllowedDeferredApi(call.callee)) return error.FinalizerCannotChangeLayout;
    return .{
        .text = try allocator.dupe(u8, call.text),
        .span = call.span,
    };
}

fn cloneDeferredValueDeclaration(
    allocator: Allocator,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const cloned = try cloneDeferredValueDeclarationWithContext(allocator, null, declaration);
    return .{
        .name = cloned.name,
        .type_name = cloned.type_name,
        .mutability = cloned.mutability,
        .value_text = cloned.value_text,
        .span = declaration.span,
    };
}

fn cloneDeferredAssignment(
    allocator: Allocator,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const cloned = try cloneDeferredAssignmentWithContext(allocator, null, assignment);
    return .{
        .name = cloned.name,
        .value_text = cloned.value_text,
        .span = assignment.span,
    };
}

fn freezeDeferredValueDeclaration(
    allocator: Allocator,
    context: *LowerContext,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const cloned = try cloneDeferredValueDeclarationWithContext(allocator, context, declaration);
    return .{
        .name = cloned.name,
        .type_name = cloned.type_name,
        .mutability = cloned.mutability,
        .value_text = cloned.value_text,
        .span = declaration.span,
    };
}

fn freezeDeferredAssignment(
    allocator: Allocator,
    context: *LowerContext,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const cloned = try cloneDeferredAssignmentWithContext(allocator, context, assignment);
    return .{
        .name = cloned.name,
        .value_text = cloned.value_text,
        .span = assignment.span,
    };
}

fn cloneDeferredValueDeclarationWithContext(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    declaration: ast.ValueDeclarationStatement,
) LowerError!output_mod.ValueDeclaration {
    const name = try allocator.dupe(u8, declaration.name);
    errdefer allocator.free(name);

    const type_name = if (declaration.type_name) |parsed_type|
        try allocator.dupe(u8, parsed_type)
    else
        null;
    errdefer if (type_name) |owned| allocator.free(owned);

    const value_text = try renderDeferredInitializer(allocator, maybe_context, declaration.value);
    return .{
        .name = name,
        .type_name = type_name,
        .mutability = declaration.mutability,
        .value_text = value_text,
        .span = declaration.span,
    };
}

fn cloneDeferredAssignmentWithContext(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    assignment: ast.AssignmentStatement,
) LowerError!output_mod.Assignment {
    const name = try allocator.dupe(u8, assignment.name);
    errdefer allocator.free(name);

    const value_text = try renderDeferredInitializer(allocator, maybe_context, assignment.value);
    return .{
        .name = name,
        .value_text = value_text,
        .span = assignment.span,
    };
}

fn freezeDeferredApiCall(
    allocator: Allocator,
    context: *LowerContext,
    call: ast.ApiCallStatement,
) LowerError!output_mod.ApiCall {
    if (!isAllowedDeferredApi(call.callee)) return error.FinalizerCannotChangeLayout;

    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);

    try text.appendSlice(allocator, call.callee);
    try text.append(allocator, '(');
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try text.appendSlice(allocator, ", ");
        const rendered = try renderFrozenDeferredArgument(allocator, context, arg);
        defer allocator.free(rendered);
        try text.appendSlice(allocator, rendered);
    }
    try text.append(allocator, ')');

    return .{
        .text = try text.toOwnedSlice(allocator),
        .span = call.span,
    };
}

fn cloneDeferredMetaIf(
    allocator: Allocator,
    meta_if: ast.MetaIfStatement,
) LowerError!output_mod.MetaIf {
    const condition = try allocator.dupe(u8, meta_if.condition);
    errdefer allocator.free(condition);
    const body = try cloneDeferredStatementSlice(allocator, meta_if.body);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }
    const else_body = try cloneDeferredStatementSlice(allocator, meta_if.else_body);
    return .{
        .condition = condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn cloneDeferredMetaWhile(
    allocator: Allocator,
    meta_while: ast.MetaWhileStatement,
) LowerError!output_mod.MetaWhile {
    const condition = try allocator.dupe(u8, meta_while.condition);
    errdefer allocator.free(condition);
    const body = try cloneDeferredStatementSlice(allocator, meta_while.body);
    return .{
        .condition = condition,
        .body = body,
        .span = meta_while.span,
    };
}

fn freezeDeferredMetaIf(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    meta_if: ast.MetaIfStatement,
) LowerError!output_mod.MetaIf {
    const condition = try renderDeferredCondition(allocator, context, meta_if.condition);
    errdefer allocator.free(condition);
    const body = try freezeDeferredStatementSlice(allocator, module, context, active, meta_if.body);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }
    const else_body = try freezeDeferredStatementSlice(allocator, module, context, active, meta_if.else_body);
    return .{
        .condition = condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn freezeDeferredMetaWhile(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    meta_while: ast.MetaWhileStatement,
) LowerError!output_mod.MetaWhile {
    const condition = try renderDeferredCondition(allocator, context, meta_while.condition);
    errdefer allocator.free(condition);
    const body = try freezeDeferredStatementSlice(allocator, module, context, active, meta_while.body);
    return .{
        .condition = condition,
        .body = body,
        .span = meta_while.span,
    };
}

fn isAllowedDeferredApi(callee: []const u8) bool {
    return std.mem.eql(u8, callee, "print") or
        std.mem.eql(u8, callee, "warn") or
        std.mem.eql(u8, callee, "err") or
        std.mem.eql(u8, callee, "assert") or
        std.mem.eql(u8, callee, "store.bytes") or
        storeByteCount(callee) != null;
}

fn cloneLateLayoutBlockFromAst(
    allocator: Allocator,
    late_layout: ast.LateLayoutStatement,
) LowerError!output_mod.LateLayoutBlock {
    const body = try cloneLateLayoutStatementSlice(allocator, late_layout.body);
    return .{
        .body = body,
        .span = late_layout.span,
    };
}

fn freezeLateLayoutBlockFromAst(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    late_layout: ast.LateLayoutStatement,
) LowerError!output_mod.LateLayoutBlock {
    const body = try freezeLateLayoutStatementSlice(allocator, module, context, active, late_layout.body);
    return .{
        .body = body,
        .span = late_layout.span,
    };
}

fn cloneLateLayoutStatementSlice(
    allocator: Allocator,
    statements: []const ast.Statement,
) LowerError![]output_mod.LateLayoutStatement {
    const cloned = try allocator.alloc(output_mod.LateLayoutStatement, statements.len);
    var cloned_len: usize = 0;
    errdefer {
        for (cloned[0..cloned_len]) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(cloned);
    }

    for (statements, 0..) |statement, index| {
        cloned[index] = try cloneLateLayoutStatement(allocator, statement);
        cloned_len += 1;
    }
    return cloned;
}

fn freezeLateLayoutStatementSlice(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statements: []const ast.Statement,
) LowerError![]output_mod.LateLayoutStatement {
    var frozen: std.ArrayList(output_mod.LateLayoutStatement) = .empty;
    errdefer {
        for (frozen.items) |*statement| {
            statement.deinit(allocator);
        }
        frozen.deinit(allocator);
    }

    for (statements) |statement| {
        try freezeLateLayoutStatementAppend(allocator, module, context, active, statement, &frozen);
    }

    return frozen.toOwnedSlice(allocator);
}

fn cloneLateLayoutStatement(
    allocator: Allocator,
    statement: ast.Statement,
) LowerError!output_mod.LateLayoutStatement {
    return switch (statement) {
        .api_call => |call| .{ .api_call = try cloneLateLayoutApiCall(allocator, call) },
        .meta_if => |meta_if| .{ .meta_if = try cloneLateLayoutMetaIf(allocator, meta_if) },
        .label,
        .isa_instruction,
        .value_decl,
        .assignment,
        .struct_decl,
        .legacy_directive,
        .meta_while,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => error.InvalidLateLayout,
    };
}

fn freezeLateLayoutStatementAppend(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statement: ast.Statement,
    frozen: *std.ArrayList(output_mod.LateLayoutStatement),
) LowerError!void {
    switch (statement) {
        .api_call => |call| {
            var frozen_call = try freezeLateLayoutApiCall(allocator, context, call);
            errdefer frozen_call.deinit(allocator);
            try frozen.append(allocator, .{ .api_call = frozen_call });
        },
        .meta_if => |meta_if| {
            if (try evalMetaCondition(module, context, active, meta_if.condition)) {
                try freezeLateLayoutStatementSliceInto(allocator, module, context, active, meta_if.body, frozen);
            } else {
                try freezeLateLayoutStatementSliceInto(allocator, module, context, active, meta_if.else_body, frozen);
            }
        },
        .label,
        .isa_instruction,
        .value_decl,
        .assignment,
        .struct_decl,
        .legacy_directive,
        .meta_while,
        .meta_for_range,
        .meta_fn,
        .meta_return,
        .meta_block,
        .meta_defer,
        .late_layout,
        .meta_line,
        .meta_block_start,
        .meta_block_end,
        => return error.InvalidLateLayout,
    }
}

fn freezeLateLayoutStatementSliceInto(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    statements: []const ast.Statement,
    frozen: *std.ArrayList(output_mod.LateLayoutStatement),
) LowerError!void {
    for (statements) |statement| {
        try freezeLateLayoutStatementAppend(allocator, module, context, active, statement, frozen);
    }
}

fn cloneLateLayoutApiCall(
    allocator: Allocator,
    call: ast.ApiCallStatement,
) LowerError!output_mod.ApiCall {
    if (!isAllowedLateLayoutApi(call.callee)) return error.InvalidLateLayout;
    return .{
        .text = try allocator.dupe(u8, call.text),
        .span = call.span,
    };
}

fn freezeLateLayoutApiCall(
    allocator: Allocator,
    context: *LowerContext,
    call: ast.ApiCallStatement,
) LowerError!output_mod.ApiCall {
    if (!isAllowedLateLayoutApi(call.callee)) return error.InvalidLateLayout;

    var text: std.ArrayList(u8) = .empty;
    errdefer text.deinit(allocator);

    try text.appendSlice(allocator, call.callee);
    try text.append(allocator, '(');
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try text.appendSlice(allocator, ", ");
        const rendered = try renderFrozenDeferredArgument(allocator, context, arg);
        defer allocator.free(rendered);
        try text.appendSlice(allocator, rendered);
    }
    try text.append(allocator, ')');

    return .{
        .text = try text.toOwnedSlice(allocator),
        .span = call.span,
    };
}

fn cloneLateLayoutMetaIf(
    allocator: Allocator,
    meta_if: ast.MetaIfStatement,
) LowerError!output_mod.LateLayoutMetaIf {
    const condition = try allocator.dupe(u8, meta_if.condition);
    errdefer allocator.free(condition);
    const body = try cloneLateLayoutStatementSlice(allocator, meta_if.body);
    errdefer {
        for (body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(body);
    }
    const else_body = try cloneLateLayoutStatementSlice(allocator, meta_if.else_body);
    return .{
        .condition = condition,
        .body = body,
        .else_body = else_body,
        .span = meta_if.span,
    };
}

fn isAllowedLateLayoutApi(callee: []const u8) bool {
    return std.mem.eql(u8, callee, "print") or
        std.mem.eql(u8, callee, "warn") or
        std.mem.eql(u8, callee, "err") or
        std.mem.eql(u8, callee, "assert") or
        std.mem.eql(u8, callee, "origin") or
        std.mem.eql(u8, callee, "region.begin") or
        std.mem.eql(u8, callee, "region.file_align") or
        std.mem.eql(u8, callee, "output.org") or
        std.mem.eql(u8, callee, "output.section") or
        std.mem.eql(u8, callee, "virtual.begin") or
        std.mem.eql(u8, callee, "virtual.end") or
        std.mem.eql(u8, callee, "emit.u8") or
        std.mem.eql(u8, callee, "emit.u16") or
        std.mem.eql(u8, callee, "emit.u32") or
        std.mem.eql(u8, callee, "emit.u64") or
        std.mem.eql(u8, callee, "emit.bytes") or
        std.mem.eql(u8, callee, "emit.struct") or
        std.mem.eql(u8, callee, "store.bytes") or
        std.mem.eql(u8, callee, "reserve") or
        std.mem.eql(u8, callee, "pad") or
        std.mem.eql(u8, callee, "pad_to") or
        std.mem.eql(u8, callee, "align") or
        dataEmitByteCount(callee) != null or
        dataReserveScale(callee) != null or
        storeByteCount(callee) != null;
}

fn renderFrozenDeferredArgument(
    allocator: Allocator,
    context: *LowerContext,
    arg: *const ast.ApiArgument,
) LowerError![]u8 {
    return switch (arg.*) {
        .expression => |*node| renderFrozenDeferredExpression(allocator, context, node),
        .string => |text| formatStringLiteral(allocator, text),
        .struct_literal => return error.InvalidApiArgument,
    };
}

fn renderDeferredCondition(allocator: Allocator, maybe_context: ?*LowerContext, condition: []const u8) LowerError![]u8 {
    const trimmed = std.mem.trim(u8, condition, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidMetaIf;
    const context = maybe_context orelse return allocator.dupe(u8, trimmed);

    var node = expr.parseOwned(allocator, trimmed) catch |err| return mapExpressionError(err);
    defer node.deinit(allocator);
    return renderFrozenDeferredExpression(allocator, context, &node);
}

fn renderDeferredInitializer(
    allocator: Allocator,
    maybe_context: ?*LowerContext,
    initializer: ast.ValueInitializer,
) LowerError![]u8 {
    return switch (initializer) {
        .expression => |*node| if (maybe_context) |context|
            renderFrozenDeferredExpression(allocator, context, node)
        else
            renderExpressionSource(allocator, null, node),
        .struct_literal => error.InvalidApiArgument,
    };
}

fn renderFrozenDeferredValue(allocator: Allocator, value: value_mod.Value) LowerError![]u8 {
    return switch (value) {
        .integer => |integer| try std.fmt.allocPrint(allocator, "{}", .{integer.value}),
        .boolean => |boolean| try allocator.dupe(u8, if (boolean) "true" else "false"),
        .string => |text| try formatStringLiteral(allocator, text),
        .bytes => |bytes| try formatBytesValue(allocator, bytes),
        .void, .type, .@"struct", .list, .map => error.InvalidApiArgument,
    };
}

fn renderFrozenDeferredExpression(
    allocator: Allocator,
    context: *LowerContext,
    node: *const expr.Node,
) LowerError![]u8 {
    switch (node.*) {
        .symbol => |name| {
            if (lookupLocalValue(context, name)) |value| {
                return renderFrozenDeferredValue(allocator, value.*);
            }
        },
        else => {},
    }
    return renderExpressionSource(allocator, context, node);
}

fn renderExpressionSource(allocator: Allocator, maybe_context: ?*LowerContext, node: *const expr.Node) LowerError![]u8 {
    return switch (node.*) {
        .integer => |value| std.fmt.allocPrint(allocator, "{}", .{value}),
        .boolean => |value| allocator.dupe(u8, if (value) "true" else "false"),
        .string_literal => |text| formatStringLiteral(allocator, text),
        .bytes_literal => |bytes| formatBytesValue(allocator, bytes),
        .symbol => |name| allocator.dupe(u8, name),
        .field_access => |access| renderFieldAccessSource(allocator, maybe_context, access),
        .builtin_call => |call| renderBuiltinCallSource(allocator, maybe_context, call),
        .unary => |unary| renderUnarySource(allocator, maybe_context, unary),
        .binary => |binary| renderBinarySource(allocator, maybe_context, binary),
    };
}

fn renderFieldAccessSource(allocator: Allocator, maybe_context: ?*LowerContext, access: expr.FieldAccess) LowerError![]u8 {
    const object = if (maybe_context) |context|
        try renderFrozenDeferredExpression(allocator, context, access.object)
    else
        try renderExpressionSource(allocator, null, access.object);
    defer allocator.free(object);
    return std.fmt.allocPrint(allocator, "{s}.{s}", .{ object, access.field_name });
}

fn renderBuiltinCallSource(allocator: Allocator, maybe_context: ?*LowerContext, call: expr.BuiltinCall) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    try result.appendSlice(allocator, call.name);
    try result.append(allocator, '(');
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try result.appendSlice(allocator, ", ");
        const text = try renderBuiltinArgumentSource(allocator, maybe_context, arg);
        defer allocator.free(text);
        try result.appendSlice(allocator, text);
    }
    try result.append(allocator, ')');
    return result.toOwnedSlice(allocator);
}

fn renderBuiltinArgumentSource(allocator: Allocator, maybe_context: ?*LowerContext, arg: *const expr.BuiltinArgument) LowerError![]u8 {
    return switch (arg.*) {
        .expression => |*node| if (maybe_context) |context|
            renderFrozenDeferredExpression(allocator, context, node)
        else
            renderExpressionSource(allocator, null, node),
        .identifier => |name| {
            if (maybe_context) |context| {
                if (lookupLocalValue(context, name)) |value| {
                    return renderFrozenDeferredValue(allocator, value.*);
                }
            }
            return allocator.dupe(u8, name);
        },
        .struct_literal => return error.InvalidApiArgument,
    };
}

fn renderUnarySource(allocator: Allocator, maybe_context: ?*LowerContext, unary: expr.Unary) LowerError![]u8 {
    const operand = if (maybe_context) |context|
        try renderFrozenDeferredExpression(allocator, context, unary.operand)
    else
        try renderExpressionSource(allocator, null, unary.operand);
    defer allocator.free(operand);
    return switch (unary.op) {
        .plus => std.fmt.allocPrint(allocator, "(+{s})", .{operand}),
        .neg => std.fmt.allocPrint(allocator, "(-{s})", .{operand}),
        .bit_not => std.fmt.allocPrint(allocator, "(~{s})", .{operand}),
        .logical_not => std.fmt.allocPrint(allocator, "(!{s})", .{operand}),
        .lengthof => std.fmt.allocPrint(allocator, "(lengthof {s})", .{operand}),
    };
}

fn renderBinarySource(allocator: Allocator, maybe_context: ?*LowerContext, binary: expr.Binary) LowerError![]u8 {
    const left = if (maybe_context) |context|
        try renderFrozenDeferredExpression(allocator, context, binary.left)
    else
        try renderExpressionSource(allocator, null, binary.left);
    defer allocator.free(left);
    const right = if (maybe_context) |context|
        try renderFrozenDeferredExpression(allocator, context, binary.right)
    else
        try renderExpressionSource(allocator, null, binary.right);
    defer allocator.free(right);
    return std.fmt.allocPrint(allocator, "({s} {s} {s})", .{ left, binaryOperatorText(binary.op), right });
}

fn binaryOperatorText(op: expr.BinaryOp) []const u8 {
    return switch (op) {
        .logical_or => "||",
        .logical_and => "&&",
        .equal => "==",
        .not_equal => "!=",
        .less_than => "<",
        .less_equal => "<=",
        .greater_than => ">",
        .greater_equal => ">=",
        .add => "+",
        .sub => "-",
        .mul => "*",
        .div => "/",
        .mod => "%",
        .shl => "<<",
        .shr => ">>",
        .bit_and => "&",
        .bit_or => "|",
        .bit_xor => "^",
    };
}

fn formatStringLiteral(allocator: Allocator, text: []const u8) LowerError![]u8 {
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

fn formatDiagnosticMessage(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    call: ast.ApiCallStatement,
) LowerError![]u8 {
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(allocator);

    for (call.args, 0..) |*arg, index| {
        if (index != 0) try message.append(allocator, ' ');
        const text = try formatDiagnosticArgument(allocator, module, context, active, arg);
        defer allocator.free(text);
        try message.appendSlice(allocator, text);
    }

    return message.toOwnedSlice(allocator);
}

fn formatDiagnosticArgument(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    arg: *const ast.ApiArgument,
) LowerError![]u8 {
    return switch (arg.*) {
        .string => |value| try allocator.dupe(u8, value),
        .expression => |*node| {
            var value = try evalValueAtContext(allocator, module, context, active, node);
            defer value.deinit(allocator);
            return formatMetaValue(allocator, value);
        },
        .struct_literal => error.InvalidApiArgument,
    };
}

fn formatMetaValue(allocator: Allocator, value: value_mod.Value) LowerError![]u8 {
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

fn formatBytesValue(allocator: Allocator, bytes: []const u8) LowerError![]u8 {
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

fn structValueFromLiteral(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    literal: ast.StructLiteralArgument,
) LowerError!value_mod.StructValue {
    const type_id = module.lookupTypeName(literal.type_name) orelse return error.UnknownTypeName;
    const stored_type = try module.types.get(type_id);

    return switch (stored_type.*) {
        .@"struct" => |*struct_type| structValueFromStructLiteral(allocator, module, context, active, type_id, struct_type, literal),
        .@"union" => |*union_type| structValueFromUnionLiteral(allocator, module, context, active, type_id, union_type, literal),
        .void, .int, .array, .pointer => error.ExpectedStruct,
    };
}

fn structValueFromStructLiteral(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    type_id: types.TypeId,
    struct_type: *const types.StructType,
    literal: ast.StructLiteralArgument,
) LowerError!value_mod.StructValue {
    try validateStructLiteralFields(struct_type, literal);

    const fields = try allocator.alloc(value_mod.StructFieldValue, struct_type.fields.items.len);
    var fields_len: usize = 0;
    errdefer {
        for (fields[0..fields_len]) |*field| {
            field.deinit(allocator);
        }
        allocator.free(fields);
    }

    for (struct_type.fields.items, 0..) |field, index| {
        const owned_name = try allocator.dupe(u8, field.name);
        errdefer allocator.free(owned_name);

        var field_value = try valueFromLiteralField(
            allocator,
            module,
            context,
            active,
            field,
            lookupStructLiteralField(literal, field.name),
        );
        errdefer field_value.deinit(allocator);
        fields[index] = .{
            .name = owned_name,
            .value = field_value,
        };
        field_value = .void;
        fields_len += 1;
    }

    return .{
        .type_id = type_id,
        .fields = fields,
    };
}

fn structValueFromUnionLiteral(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    type_id: types.TypeId,
    union_type: *const types.UnionType,
    literal: ast.StructLiteralArgument,
) LowerError!value_mod.StructValue {
    try validateStructLiteralFields(union_type, literal);
    if (literal.fields.len != 1) return error.InvalidValueDeclaration;

    const literal_field = literal.fields[0];
    const field = union_type.fieldByName(literal_field.name) orelse return error.UnknownField;

    const fields = try allocator.alloc(value_mod.StructFieldValue, 1);
    errdefer allocator.free(fields);

    const owned_name = try allocator.dupe(u8, field.name);
    errdefer allocator.free(owned_name);

    var field_value = try valueFromLiteralField(allocator, module, context, active, field.*, &literal_field.value);
    errdefer field_value.deinit(allocator);

    fields[0] = .{
        .name = owned_name,
        .value = field_value,
    };
    field_value = .void;

    return .{
        .type_id = type_id,
        .fields = fields,
    };
}

fn valueFromLiteralField(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    field: types.StructField,
    literal_value: ?*const ast.StructLiteralValue,
) LowerError!value_mod.Value {
    const ty = try module.types.get(field.ty);
    return switch (ty.*) {
        .int => |int_type| blk: {
            const raw_value = if (literal_value) |value| switch (value.*) {
                .expression => |*node| try evalIntegerAtContext(module, context, active, node),
                .struct_literal => return error.InvalidValueDeclaration,
            } else field.default_value orelse return error.MissingStructFieldValue;
            try value_mod.validateIntegerForIntType(raw_value, int_type);
            break :blk value_mod.Value.typedInteger(raw_value, field.ty);
        },
        .@"struct", .@"union" => blk: {
            const value = literal_value orelse return error.MissingStructFieldValue;
            var aggregate_value = switch (value.*) {
                .struct_literal => |nested| value_mod.Value{ .@"struct" = try structValueFromLiteral(allocator, module, context, active, nested) },
                .expression => |*node| try evalValueAtContext(allocator, module, context, active, node),
            };
            errdefer aggregate_value.deinit(allocator);
            const stored = switch (aggregate_value) {
                .@"struct" => |stored| stored,
                .void, .integer, .boolean, .string, .bytes, .type, .list, .map => return error.InvalidValueDeclaration,
            };
            if (stored.type_id.index != field.ty.index) return error.InvalidValueDeclaration;
            break :blk aggregate_value;
        },
        .void, .array, .pointer => error.InvalidType,
    };
}

fn emitStructValue(
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

fn validateStructLiteralFields(
    struct_type: *const types.StructType,
    literal: ast.StructLiteralArgument,
) LowerError!void {
    for (literal.fields, 0..) |literal_field, index| {
        if (lookupStructLiteralFieldAfter(literal, literal_field.name, index + 1) != null) {
            return error.DuplicateFieldName;
        }
        if (struct_type.fieldByName(literal_field.name) == null) {
            return error.UnknownField;
        }
    }
}

fn lookupStructLiteralField(literal: ast.StructLiteralArgument, name: []const u8) ?*const ast.StructLiteralValue {
    for (literal.fields) |field| {
        if (std.mem.eql(u8, field.name, name)) return &field.value;
    }
    return null;
}

fn lookupStructLiteralFieldAfter(
    literal: ast.StructLiteralArgument,
    name: []const u8,
    start: usize,
) ?*const ast.StructLiteralValue {
    for (literal.fields[start..]) |field| {
        if (std.mem.eql(u8, field.name, name)) return &field.value;
    }
    return null;
}

fn sizeofType(module: *module_mod.Module, name: []const u8) LowerError!u64 {
    const id = module.lookupTypeName(name) orelse return error.UnknownTypeName;
    return (try module.typeLayout(id)).size;
}

fn evalMetaCondition(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    condition: []const u8,
) LowerError!bool {
    const trimmed = std.mem.trim(u8, condition, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidMetaIf;

    if (parseBoolLiteral(trimmed)) |value| return value;

    if (std.mem.startsWith(u8, trimmed, "defined(")) {
        const name = try parseNameCallArg(trimmed, "defined");
        return lookupLocalValue(context, name) != null or
            module.symbols.lookup(name) != null or
            module.lookupTypeName(name) != null;
    }

    if (try evalTargetCondition(module, context, active, trimmed)) |value| return value;

    var condition_expr = expr.parseOwned(module.allocator, trimmed) catch |err| return mapMetaConditionParseError(err);
    defer condition_expr.deinit(module.allocator);
    return evalBooleanAtContext(module, context, active, &condition_expr) catch |err| return switch (err) {
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
        => mapExpressionError(err),
    };
}

fn evalBooleanAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
) LowerError!bool {
    var ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = fileResolver(context),
        .source_path = currentSourcePath(context),
        .local_context = context,
        .resolve_local = resolveLocalValue,
        .next_unique_symbol = nextUniqueSymbol,
        .call_user_function = evalUserValueFunction,
        .evaluate_struct_literal = evalStructLiteralValue,
    };
    return expr.evaluateBoolean(node, &ctx) catch |err| return mapExpressionError(err);
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
) LowerError!?bool {
    const comparison = splitComparison(condition) orelse return null;
    if (std.mem.eql(u8, comparison.left, "target.bits") or
        std.mem.eql(u8, comparison.left, "target.xlen"))
    {
        var expected_expression = expr.parseOwned(module.allocator, comparison.right) catch |err| return mapExpressionError(err);
        defer expected_expression.deinit(module.allocator);
        const expected_bits = try evalIntegerAtContext(module, context, active, &expected_expression);
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

fn evalInteger(module: *module_mod.Module, node: *const expr.Node) LowerError!u64 {
    var ctx: expr.EvalContext = .{ .module = module };
    return expr.evaluateInteger(node, &ctx) catch |err| return mapExpressionError(err);
}

fn evalIntegerAt(module: *module_mod.Module, active: ActiveOutput, node: *const expr.Node) LowerError!u64 {
    try materializeInstructionBytesForExpression(module, node);
    var ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
    };
    return expr.evaluateInteger(node, &ctx) catch |err| return mapExpressionError(err);
}

fn evalIntegerAtContext(
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
) LowerError!u64 {
    try materializeInstructionBytesForExpression(module, node);
    var ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = fileResolver(context),
        .source_path = currentSourcePath(context),
        .local_context = context,
        .resolve_local = resolveLocalValue,
        .next_unique_symbol = nextUniqueSymbol,
        .call_user_function = evalUserValueFunction,
        .evaluate_struct_literal = evalStructLiteralValue,
    };
    return expr.evaluateInteger(node, &ctx) catch |err| return mapExpressionError(err);
}

fn evalValueAtContext(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    node: *const expr.Node,
) LowerError!value_mod.Value {
    try materializeInstructionBytesForExpression(module, node);
    var ctx: expr.EvalContext = .{
        .module = module,
        .active_target = active.target,
        .active_section = active.section_id,
        .active_offset = active.offset,
        .active_file_offset = active.file_offset,
        .file_resolver = fileResolver(context),
        .source_path = currentSourcePath(context),
        .local_context = context,
        .resolve_local = resolveLocalValue,
        .next_unique_symbol = nextUniqueSymbol,
        .call_user_function = evalUserValueFunction,
        .evaluate_struct_literal = evalStructLiteralValue,
    };
    return expr.evaluateValue(allocator, node, &ctx) catch |err| return mapExpressionError(err);
}

fn mapExpressionError(err: expr.ExpressionError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.UnknownTypeName => error.UnknownTypeName,
        error.UnknownField => error.UnknownField,
        error.DivisionByZero => error.DivisionByZero,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidApiArgument => error.InvalidApiArgument,
        error.InvalidApiInteger => error.InvalidApiInteger,
        error.InvalidIntegerBits => error.InvalidIntegerBits,
        error.InvalidType => error.InvalidType,
        error.InvalidFragment => error.InvalidApiArgument,
        error.InvalidSection => error.InvalidSection,
        error.MissingStructFieldValue => error.MissingStructFieldValue,
        error.OffsetOverflow => error.OffsetOverflow,
        error.FileNotAvailable => error.FileNotAvailable,
        error.TypeMismatch => error.InvalidExpression,
        error.InvalidArgument,
        error.InvalidCharacter,
        error.InvalidNumber,
        error.InvalidOperand,
        error.InvalidToken,
        error.MissingEvaluationContext,
        error.UndefinedSymbol,
        error.UnexpectedEof,
        => error.InvalidExpression,
    };
}

test "expression error mapping preserves file availability" {
    try std.testing.expectEqual(error.FileNotAvailable, mapExpressionError(error.FileNotAvailable));
}

fn fileResolver(context: *LowerContext) ?meta_io.FileResolver {
    if (context.include_resolver == null) return null;
    return .{
        .context = @ptrCast(context),
        .read = readResolvedMetaFile,
        .exists = metaFileExists,
    };
}

fn readResolvedMetaFile(
    raw_context: *anyopaque,
    allocator: Allocator,
    request: meta_io.FileReadRequest,
) meta_io.Error!meta_io.FileReadResult {
    const context: *LowerContext = @ptrCast(@alignCast(raw_context));
    const include_resolver = context.include_resolver orelse return error.FileNotAvailable;
    var include_source = include_resolver.resolve(include_resolver.context, allocator, .{
        .path = request.path,
        .parent_path = request.parent_path,
        .span = request.span,
    }) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.FileNotAvailable,
    };
    errdefer include_source.deinit(allocator);

    return .{
        .path = include_source.path,
        .bytes = include_source.bytes,
    };
}

fn metaFileExists(
    raw_context: *anyopaque,
    allocator: Allocator,
    request: meta_io.FileReadRequest,
) Allocator.Error!bool {
    var result = readResolvedMetaFile(raw_context, allocator, request) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        error.FileNotAvailable => return false,
    };
    result.deinit(allocator);
    return true;
}

fn materializeInstructionBytesForExpression(module: *module_mod.Module, node: *const expr.Node) LowerError!void {
    if (!expr.usesOutputLoad(node)) return;
    try materializeInstructionBytesForOutputAccess(module);
}

fn materializeInstructionBytesForOutputAccess(module: *module_mod.Module) LowerError!void {
    const result = pass.encodeInstructionFragments(module.allocator, module) catch |err| return mapPassError(err);
    if (result.changed_count > result.encoded_count) return error.InvalidApiArgument;
}

fn syncActiveOutputOffsetForLayoutApi(module: *module_mod.Module, active: *ActiveOutput) LowerError!void {
    try materializeInstructionBytesForOutputAccess(module);
    active.offset = try sectionCursor(module, active.section_id);
    active.file_offset = try sectionFileCursor(module, active.section_id);
}

fn mapPassError(err: pass.PassError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidFragment => error.InvalidFragment,
        error.InvalidSection => error.InvalidSection,
        error.InvalidModeBits => error.InvalidModeBits,
        error.OffsetOverflow => error.OffsetOverflow,
        error.TooManyFixups => error.TooManyFixups,
        error.FrontendDiagnostics => error.FrontendDiagnostics,
        error.BackendUnsupported,
        error.InstructionTooLarge,
        error.InvalidFixupTarget,
        error.InvalidInstructionText,
        => error.InvalidApiArgument,
    };
}

fn mapParseError(err: parser.ParseError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.SourceTooLarge => error.SourceTooLarge,
        error.InvalidLateLayout => error.InvalidLateLayout,
        error.UnexpectedEndOfLateLayout => error.UnexpectedEndOfLateLayout,
        else => error.InvalidApiCall,
    };
}

fn lowerIsaText(
    allocator: Allocator,
    module: *module_mod.Module,
    context: *LowerContext,
    active: ActiveOutput,
    text: []const u8,
) LowerError![]u8 {
    var result: std.ArrayList(u8) = .empty;
    errdefer result.deinit(allocator);

    var cursor: usize = 0;
    while (findBuiltinCall(text, cursor)) |call_range| {
        const start = call_range.start;
        const end = call_range.end;
        try result.appendSlice(allocator, text[cursor..start]);
        var expression = expr.parseOwned(allocator, text[start..end]) catch |err| return mapExpressionError(err);
        defer expression.deinit(allocator);
        const value = try evalIntegerAtContext(module, context, active, &expression);
        const value_text = try std.fmt.allocPrint(allocator, "{}", .{value});
        defer allocator.free(value_text);
        try result.appendSlice(allocator, value_text);
        cursor = end;
    }

    try result.appendSlice(allocator, text[cursor..]);
    return result.toOwnedSlice(allocator);
}

const TextRange = struct {
    start: usize,
    end: usize,
};

fn findBuiltinCall(text: []const u8, start_index: usize) ?TextRange {
    var index = start_index;
    while (index < text.len) : (index += 1) {
        if (!identifier.isStart(text[index])) continue;

        const name_start = index;
        index += 1;
        while (index < text.len and identifier.isContinue(text[index])) : (index += 1) {}
        const name_end = index;
        if (!isExpressionBuiltinName(text[name_start..name_end])) continue;

        var cursor = index;
        while (cursor < text.len and std.ascii.isWhitespace(text[cursor])) : (cursor += 1) {}
        if (cursor >= text.len or text[cursor] != '(') continue;

        if (findMatchingCloseParen(text, cursor)) |close| {
            return .{
                .start = name_start,
                .end = close + 1,
            };
        }
        return null;
    }
    return null;
}

fn findMatchingCloseParen(text: []const u8, open_index: usize) ?usize {
    var depth: usize = 0;
    var index = open_index;
    while (index < text.len) : (index += 1) {
        switch (text[index]) {
            '(' => depth += 1,
            ')' => {
                depth -= 1;
                if (depth == 0) return index;
            },
            '"', '\'' => {
                index = skipQuotedText(text, index) orelse return null;
            },
            else => {},
        }
    }
    return null;
}

fn skipQuotedText(text: []const u8, quote_index: usize) ?usize {
    const quote = text[quote_index];
    var index = quote_index + 1;
    while (index < text.len) : (index += 1) {
        if (text[index] != quote) continue;
        if (index + 1 < text.len and text[index + 1] == quote) {
            index += 1;
            continue;
        }
        return index;
    }
    return null;
}

fn isExpressionBuiltinName(name: []const u8) bool {
    return std.mem.eql(u8, name, "sizeof") or
        std.mem.eql(u8, name, "lengthof") or
        std.mem.eql(u8, name, "offset_of") or
        std.mem.eql(u8, name, "here") or
        std.mem.eql(u8, name, "region_base") or
        std.mem.eql(u8, name, "file_offset") or
        std.mem.eql(u8, name, "file_cursor_real") or
        std.mem.eql(u8, name, "file_cursor_potential") or
        std.mem.eql(u8, name, "tail_reserve_size") or
        std.mem.eql(u8, name, "label_addr") or
        std.mem.eql(u8, name, "sym.unique");
}

fn discardLastActiveOutput(output_stack: *std.ArrayList(ActiveOutput)) void {
    output_stack.shrinkRetainingCapacity(output_stack.items.len - 1);
}

fn nextOffsetFromFragment(stored_fragment: fragment.Fragment, current_offset: u64) LowerError!u64 {
    const size: u64 = switch (stored_fragment) {
        .bytes => |bytes| @intCast(bytes.data.len),
        .reserve => |reserve| reserve.size,
        .alignment => |alignment| {
            if (alignment.alignment == 0) return error.InvalidAlignment;
            const remainder = current_offset % alignment.alignment;
            if (remainder == 0) return current_offset;
            return std.math.add(u64, current_offset, alignment.alignment - remainder) catch error.OffsetOverflow;
        },
        .isa_instruction => |instruction| instruction.current_size,
    };

    return std.math.add(u64, current_offset, size) catch error.OffsetOverflow;
}

fn nextFileOffsetFromFragment(stored_fragment: fragment.Fragment, current_offset: u64, current_file_offset: u64) LowerError!u64 {
    return switch (stored_fragment) {
        .bytes => |bytes| checkedAdd(try materializedOffset(current_offset, current_file_offset), @intCast(bytes.data.len)),
        .isa_instruction => |instruction| checkedAdd(try materializedOffset(current_offset, current_file_offset), instruction.current_size),
        .reserve => current_file_offset,
        .alignment => |alignment| {
            const materialized = try materializedOffset(current_offset, current_file_offset);
            return alignForward(materialized, alignment.alignment);
        },
    };
}

fn advanceActiveOutput(active: *ActiveOutput, stored_fragment: fragment.Fragment) LowerError!void {
    active.file_offset = try nextFileOffsetFromFragment(stored_fragment, active.offset, active.file_offset);
    active.offset = try nextOffsetFromFragment(stored_fragment, active.offset);
}

fn sectionCursor(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u64 {
    const stored_section = try module.sections.get(section_id);
    var cursor: u64 = 0;
    for (stored_section.fragments.items) |fragment_id| {
        cursor = try nextOffsetFromFragment(module.fragments.items.items[fragment_id.index], cursor);
    }
    return cursor;
}

fn sectionFileCursor(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u64 {
    const stored_section = try module.sections.get(section_id);
    var cursor: u64 = 0;
    var file_cursor: u64 = 0;
    for (stored_section.fragments.items) |fragment_id| {
        const stored_fragment = module.fragments.items.items[fragment_id.index];
        file_cursor = try nextFileOffsetFromFragment(stored_fragment, cursor, file_cursor);
        cursor = try nextOffsetFromFragment(stored_fragment, cursor);
    }
    return try alignForward(file_cursor, stored_section.file_size_alignment);
}

fn materializedOffset(current_offset: u64, current_file_offset: u64) LowerError!u64 {
    return @max(current_offset, current_file_offset);
}

fn alignForward(value: u64, alignment: u64) LowerError!u64 {
    if (!isPowerOfTwoNonZero(alignment)) return error.InvalidAlignment;
    const remainder = value % alignment;
    if (remainder == 0) return value;
    return checkedAdd(value, alignment - remainder);
}

fn checkedAdd(a: u64, b: u64) LowerError!u64 {
    return std.math.add(u64, a, b) catch error.OffsetOverflow;
}

fn activeFragmentPosition(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u32 {
    const stored_section = try module.sections.get(section_id);
    if (stored_section.fragments.items.len > std.math.maxInt(u32)) return error.FragmentTooLarge;
    return @intCast(stored_section.fragments.items.len);
}

fn isPowerOfTwoNonZero(value: u64) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

test "lowering records labels and ISA fragments in the frontend container" {
    var module = try lowerSource(
        std.testing.allocator,
        \\entry:
        \\    mov rax, 1
        \\origin(0x7c00);
        \\org 0x7c00
        \\packed struct Header {
        \\    magic: u16 = 0xaa55,
        \\    size: u32,
        \\}
        \\let count = 4
        \\count = count + 1
        \\    add rax, count
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 1), module.sections.items.items.len);
    try std.testing.expectEqual(@as(usize, 2), module.fragments.items.items.len);
    try std.testing.expectEqual(@as(usize, 2), module.symbols.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
    try std.testing.expectEqual(@as(usize, 3), module.types.items.items.len);
    try std.testing.expect((module.lookupTypeName("Header") orelse return error.MissingType).index == 2);
    try std.testing.expectEqualStrings(
        "legacy assembler directive is not supported; use modern XIRASM API syntax",
        module.diagnostics.items.items[0].message,
    );

    const entry_id = module.symbols.lookup("entry") orelse return error.MissingSymbol;
    const entry = try module.symbols.get(entry_id);
    switch (entry.binding) {
        .label => |label| {
            try std.testing.expectEqual(module.default_section.index, label.section.index);
            try std.testing.expectEqual(@as(u64, 0), label.offset);
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const count_id = module.symbols.lookup("count") orelse return error.MissingSymbol;
    const count = try module.symbols.get(count_id);
    switch (count.binding) {
        .value => |binding| {
            try std.testing.expectEqual(.let, binding.mutability);
            try std.testing.expectEqual(@as(u64, 5), try binding.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
}

test "lowering updates let value bindings" {
    var module = try lowerSource(
        std.testing.allocator,
        \\let value = 41
        \\value = value + 1
        \\emit.u8(value);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const value_id = module.symbols.lookup("value") orelse return error.MissingSymbol;
    const value_symbol = try module.symbols.get(value_id);
    switch (value_symbol.binding) {
        .value => |binding| {
            try std.testing.expectEqual(value_mod.Mutability.let, binding.mutability);
            try std.testing.expectEqual(@as(u64, 42), try binding.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
}

test "lowering rejects const value assignment" {
    var module = lowerSource(
        std.testing.allocator,
        \\const value = 41
        \\value = 42
        \\
    ,
        .{},
    ) catch |err| {
        try std.testing.expectEqual(error.InvalidValueDeclaration, err);
        return;
    };
    module.deinit();
    return error.TestExpectedError;
}

test "value functions may update local let bindings only" {
    var module = try lowerSource(
        std.testing.allocator,
        \\fn bump(value: integer) -> integer {
        \\    let local = value
        \\    local = local + 1
        \\    return local
        \\}
        \\const result = bump(41)
        \\
    ,
        .{},
    );
    defer module.deinit();

    const result_id = module.symbols.lookup("result") orelse return error.MissingSymbol;
    const result_symbol = try module.symbols.get(result_id);
    switch (result_symbol.binding) {
        .value => |binding| try std.testing.expectEqual(@as(u64, 42), try binding.value.expectInteger()),
        else => return error.UnexpectedSymbolBinding,
    }

    try std.testing.expectError(
        error.InvalidExpression,
        lowerSource(
            std.testing.allocator,
            \\let outer = 41
            \\fn bump() -> integer {
            \\    outer = 42
            \\    return outer
            \\}
            \\const result = bump()
            \\
        ,
            .{},
        ),
    );
}

test "lowering records Meta diagnostic API messages" {
    var module = try lowerSource(
        std.testing.allocator,
        \\print("size", 2 + 3);
        \\warn("careful", here());
        \\assert(true, "must not emit");
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 2), module.diagnostics.items.items.len);

    try std.testing.expectEqual(.note, module.diagnostics.items.items[0].severity);
    try std.testing.expectEqualStrings("size 5", module.diagnostics.items.items[0].message);
    try std.testing.expect(module.diagnostics.items.items[0].span.start < module.diagnostics.items.items[0].span.end);

    try std.testing.expectEqual(.warning, module.diagnostics.items.items[1].severity);
    try std.testing.expectEqualStrings("careful 0", module.diagnostics.items.items[1].message);
    try std.testing.expect(module.diagnostics.items.items[1].span.start < module.diagnostics.items.items[1].span.end);
}

test "lowering err emits one frontend diagnostic error" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.FrontendDiagnostics,
        lowerSourceIntoModule(std.testing.allocator, &module,
            \\err("stop", 7);
            \\
        ),
    );

    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
    try std.testing.expectEqual(.err, module.diagnostics.items.items[0].severity);
    try std.testing.expectEqualStrings("stop 7", module.diagnostics.items.items[0].message);
    try std.testing.expect(module.diagnostics.items.items[0].span.start < module.diagnostics.items.items[0].span.end);
}

test "lowering assert false emits one frontend diagnostic error" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.FrontendDiagnostics,
        lowerSourceIntoModule(std.testing.allocator, &module,
            \\assert(false, "bad state");
            \\
        ),
    );

    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
    try std.testing.expectEqual(.err, module.diagnostics.items.items[0].severity);
    try std.testing.expectEqualStrings("bad state", module.diagnostics.items.items[0].message);
}

test "lowering assert false has a default message" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.FrontendDiagnostics,
        lowerSourceIntoModule(std.testing.allocator, &module,
            \\assert(false);
            \\
        ),
    );

    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
    try std.testing.expectEqual(.err, module.diagnostics.items.items[0].severity);
    try std.testing.expectEqualStrings("assertion failed", module.diagnostics.items.items[0].message);
}

test "lowering records struct declarations in the frontend type store" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32,
        \\}
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 3), module.types.items.items.len);
    const header = try module.types.getStruct(.{ .index = 2 });
    try std.testing.expectEqualStrings("DosHeader", header.name);
    try std.testing.expectEqual(types.StructLayoutPolicy.@"packed", header.policy);
    try std.testing.expectEqual(@as(u64, 6), header.layout.size);
    try std.testing.expectEqual(@as(u64, 0), try module.types.structFieldOffset(.{ .index = 2 }, "magic"));
    try std.testing.expectEqual(@as(u64, 2), try module.types.structFieldOffset(.{ .index = 2 }, "lfanew"));
    try std.testing.expect((module.lookupTypeName("DosHeader") orelse return error.MissingType).index == 2);
}

test "lowering reuses named types across structs" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct HeaderA {
        \\    magic: u16,
        \\    size: u32,
        \\}
        \\packed struct HeaderB {
        \\    other_magic: u16,
        \\    other_size: u32,
        \\}
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 4), module.types.items.items.len);
    try std.testing.expect((module.lookupTypeName("u16") orelse return error.MissingType).index == 0);
    try std.testing.expect((module.lookupTypeName("u32") orelse return error.MissingType).index == 1);
    try std.testing.expect((module.lookupTypeName("HeaderA") orelse return error.MissingType).index == 2);
    try std.testing.expect((module.lookupTypeName("HeaderB") orelse return error.MissingType).index == 3);
}

test "lowering executes flat v1 API calls" {
    var module = try lowerSource(
        std.testing.allocator,
        \\origin(0x7c00);
        \\entry:
        \\emit.u8(0xeb);
        \\emit.u16(0xaa55);
        \\emit.bytes("OK");
        \\reserve(4);
        \\pad(2, 0xcc);
        \\pad_to(16, 0);
        \\align(32, 0x90);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(u64, 0x7c00), text.origin);
    try std.testing.expectEqual(@as(usize, 7), text.fragments.items.len);

    const entry_id = module.symbols.lookup("entry") orelse return error.MissingSymbol;
    const entry = try module.symbols.get(entry_id);
    switch (entry.binding) {
        .label => |label| try std.testing.expectEqual(@as(u64, 0), label.offset),
        else => return error.UnexpectedSymbolBinding,
    }

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0xeb), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 2), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x55), bytes.data[0]);
            try std.testing.expectEqual(@as(u8, 0xaa), bytes.data[1]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[4].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 2), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0xcc), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[6].index]) {
        .alignment => |alignment| {
            try std.testing.expectEqual(@as(u64, 32), alignment.alignment);
            try std.testing.expectEqual(@as(u8, 0x90), alignment.fill);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering rejects output after region file alignment closes physical section" {
    try std.testing.expectError(error.OutputRegionClosed, lowerSource(
        std.testing.allocator,
        \\emit.u8(1);
        \\region.file_align(0x200);
        \\emit.u8(2);
        \\
    ,
        .{},
    ));
}

test "lowering target mode APIs snapshot subsequent ISA fragments" {
    var module = try lowerSource(
        std.testing.allocator,
        \\x86.use32();
        \\    ret
        \\x86.use64();
        \\    ret
        \\riscv.use32();
        \\    addi x1, x0, 1
        \\riscv.use64();
        \\    addi x2, x0, 2
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 4), text.fragments.items.len);

    const first = module.fragments.items.items[text.fragments.items[0].index];
    const second = module.fragments.items.items[text.fragments.items[1].index];
    const third = module.fragments.items.items[text.fragments.items[2].index];
    const fourth = module.fragments.items.items[text.fragments.items[3].index];

    switch (first) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqual(target.Isa.x86_64, instruction.target.isa());
            try std.testing.expectEqual(@as(u16, 32), instruction.target.bits().?);
        },
        else => return error.UnexpectedFragment,
    }
    switch (second) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqual(target.Isa.x86_64, instruction.target.isa());
            try std.testing.expectEqual(@as(u16, 64), instruction.target.bits().?);
        },
        else => return error.UnexpectedFragment,
    }
    switch (third) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqual(target.Isa.riscv64, instruction.target.isa());
            try std.testing.expectEqual(@as(u16, 32), instruction.target.bits().?);
        },
        else => return error.UnexpectedFragment,
    }
    switch (fourth) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqual(target.Isa.riscv64, instruction.target.isa());
            try std.testing.expectEqual(@as(u16, 64), instruction.target.bits().?);
        },
        else => return error.UnexpectedFragment,
    }

    try std.testing.expectEqual(target.Isa.riscv64, module.target.isa());
    try std.testing.expectEqual(@as(u16, 64), module.target.bits().?);
}

test "lowering evaluates modern defined meta conditionals" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const enabled = 1
        \\if defined("enabled") {
        \\emit.u8(0xaa);
        \\}
        \\if defined("missing") {
        \\org 0x7c00
        \\emit.u8(0xbb);
        \\}
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0xaa), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering evaluates target meta conditionals" {
    var module = try lowerSource(
        std.testing.allocator,
        \\if target.bits == 64 {
        \\emit.u8(0x64);
        \\}
        \\if target.isa == .riscv64 {
        \\emit.u8(0xff);
        \\}
        \\
    ,
        .{ .target = try target.Target.initX86(64) },
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x64), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }
}

const TestIncludeFile = struct {
    path: []const u8,
    bytes: []const u8,
};

const TestIncludeResolver = struct {
    files: []const TestIncludeFile,

    fn resolve(
        context: *anyopaque,
        allocator: Allocator,
        request: IncludeRequest,
    ) LowerError!IncludeSource {
        const resolver: *const TestIncludeResolver = @ptrCast(@alignCast(context));
        const resolved_path = try testResolveIncludePath(allocator, request.parent_path, request.path);
        errdefer allocator.free(resolved_path);

        for (resolver.files) |file| {
            if (!std.mem.eql(u8, file.path, resolved_path)) continue;

            return .{
                .path = resolved_path,
                .bytes = try allocator.dupe(u8, file.bytes),
            };
        }

        return error.IncludeNotAvailable;
    }
};

fn testResolveIncludePath(
    allocator: Allocator,
    parent_path: ?[]const u8,
    include_path: []const u8,
) Allocator.Error![]u8 {
    const parent = parent_path orelse return allocator.dupe(u8, include_path);
    const separator_index = std.mem.lastIndexOfAny(u8, parent, "\\/") orelse return allocator.dupe(u8, include_path);
    const parent_dir = parent[0..separator_index];
    if (parent_dir.len == 0) return allocator.dupe(u8, include_path);
    return std.fmt.allocPrint(allocator, "{s}/{s}", .{ parent_dir, include_path });
}

test "lowering evaluates target width fields in general expressions" {
    var module = try lowerSource(
        std.testing.allocator,
        \\x86.use64();
        \\const x86_bits = target.bits
        \\assert(x86_bits == 64);
        \\assert(target.bits == 64);
        \\riscv.use32();
        \\const riscv_bits = target.xlen
        \\assert(riscv_bits == 32);
        \\assert(target.xlen == 32);
        \\emit.u8(riscv_bits);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, &.{0x20}, bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering resolves source-level include relative to parent source" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/prefix.xir",
            .bytes =
            \\const prefix: u64 = 2;
            \\emit.u8(prefix);
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try lowerSourceIntoModuleWithPathOptions(
        std.testing.allocator,
        &module,
        "src/main.xir",
        \\include("shared/prefix.xir");
        \\emit.u8(prefix + 1);
        \\
    ,
        .{
            .include_resolver = .{
                .context = @ptrCast(&resolver),
                .resolve = TestIncludeResolver.resolve,
            },
        },
    );

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 2), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 3), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering imports source files only once" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/once.xir",
            .bytes =
            \\emit.u8(0x42);
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try lowerSourceIntoModuleWithPathOptions(
        std.testing.allocator,
        &module,
        "src/main.xir",
        \\import("shared/once.xir");
        \\import("shared/once.xir");
        \\
    ,
        .{
            .include_resolver = .{
                .context = @ptrCast(&resolver),
                .resolve = TestIncludeResolver.resolve,
            },
        },
    );

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 0x42), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }
}

test "lowering includes source files every time" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/inline.xir",
            .bytes =
            \\emit.u8(0x24);
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try lowerSourceIntoModuleWithPathOptions(
        std.testing.allocator,
        &module,
        "src/main.xir",
        \\include("shared/inline.xir");
        \\include("shared/inline.xir");
        \\
    ,
        .{
            .include_resolver = .{
                .context = @ptrCast(&resolver),
                .resolve = TestIncludeResolver.resolve,
            },
        },
    );

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
    try std.testing.expectEqual(@as(usize, 0), module.diagnostics.items.items.len);

    for (text.fragments.items) |fragment_id| {
        switch (module.fragments.items.items[fragment_id.index]) {
            .bytes => |bytes| try std.testing.expectEqual(@as(u8, 0x24), bytes.data[0]),
            else => return error.UnexpectedFragment,
        }
    }
}

test "lowering imports Meta function modules only once" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/functions.xir",
            .bytes =
            \\fn emit_once(value: u64) {
            \\    emit.u8(value);
            \\}
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try lowerSourceIntoModuleWithPathOptions(
        std.testing.allocator,
        &module,
        "src/main.xir",
        \\import("shared/functions.xir");
        \\import("shared/functions.xir");
        \\emit_once(9);
        \\
    ,
        .{
            .include_resolver = .{
                .context = @ptrCast(&resolver),
                .resolve = TestIncludeResolver.resolve,
            },
        },
    );

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 9), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }
}

test "lowering includes duplicate Meta function modules as repeated source" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/functions.xir",
            .bytes =
            \\fn emit_dup(value: u64) {
            \\    emit.u8(value);
            \\}
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.DuplicateMetaFunction,
        lowerSourceIntoModuleWithPathOptions(
            std.testing.allocator,
            &module,
            "src/main.xir",
            \\include("shared/functions.xir");
            \\include("shared/functions.xir");
            \\
        ,
            .{
                .include_resolver = .{
                    .context = @ptrCast(&resolver),
                    .resolve = TestIncludeResolver.resolve,
                },
            },
        ),
    );
}

test "lowering rejects recursive source imports" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/main.xir",
            .bytes =
            \\import("main.xir");
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.IncludeCycle,
        lowerSourceIntoModuleWithPathOptions(
            std.testing.allocator,
            &module,
            "src/main.xir",
            \\import("main.xir");
            \\
        ,
            .{
                .include_resolver = .{
                    .context = @ptrCast(&resolver),
                    .resolve = TestIncludeResolver.resolve,
                },
            },
        ),
    );
}

test "lowering rejects scoped source imports" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/mod.xir",
            .bytes =
            \\emit.u8(1);
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try std.testing.expectError(
        error.InvalidMetaBlock,
        lowerSourceIntoModuleWithPathOptions(
            std.testing.allocator,
            &module,
            "src/main.xir",
            \\{
            \\    import("shared/mod.xir");
            \\}
            \\
        ,
            .{
                .include_resolver = .{
                    .context = @ptrCast(&resolver),
                    .resolve = TestIncludeResolver.resolve,
                },
            },
        ),
    );
}

test "lowering calls Meta functions with scoped integer parameters" {
    var module = try lowerSource(
        std.testing.allocator,
        \\fn emit_pair(value: u64) {
        \\    emit.u8(value);
        \\    emit.u8(value + 1);
        \\}
        \\emit_pair(2);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 2), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 3), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering scopes block-local values without leaking symbols" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const value = 1
        \\{
        \\    let value = 2
        \\    emit.u8(value);
        \\}
        \\emit.u8(value);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const value_id = module.symbols.lookup("value") orelse return error.MissingSymbol;
    const value_symbol = try module.symbols.get(value_id);
    switch (value_symbol.binding) {
        .value => |binding| try std.testing.expectEqual(@as(u64, 1), try binding.value.expectInteger()),
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 2), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 1), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }
}

test "lowering scopes Meta if body values without leaking symbols" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const value = 1
        \\if true {
        \\    let value = 2
        \\    emit.u8(value);
        \\}
        \\emit.u8(value);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const value_id = module.symbols.lookup("value") orelse return error.MissingSymbol;
    const value_symbol = try module.symbols.get(value_id);
    switch (value_symbol.binding) {
        .value => |binding| try std.testing.expectEqual(@as(u64, 1), try binding.value.expectInteger()),
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 2), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 1), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }
}

test "lowering keeps Meta function parameters local to the call" {
    try std.testing.expectError(
        error.InvalidExpression,
        lowerSource(
            std.testing.allocator,
            \\fn emit_one(value: u64) {
            \\    emit.u8(value);
            \\}
            \\emit_one(7);
            \\emit.u8(value);
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects duplicate Meta function parameter names" {
    try std.testing.expectError(
        error.InvalidMetaFunction,
        lowerSource(
            std.testing.allocator,
            \\fn emit_pair(value: u64, value: u64) {
            \\    emit.u8(value);
            \\}
            \\emit_pair(1, 2);
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects duplicate local names in one Meta scope" {
    try std.testing.expectError(
        error.DuplicateSymbol,
        lowerSource(
            std.testing.allocator,
            \\{
            \\    let value = 1
            \\    let value = 2
            \\}
            \\
        ,
            .{},
        ),
    );
}

test "lowering keeps nested block locals scoped by nearest declaration" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const value = 1
        \\{
        \\    let value = 2
        \\    {
        \\        let value = 3
        \\        emit.u8(value);
        \\    }
        \\    emit.u8(value);
        \\}
        \\emit.u8(value);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 3), text.fragments.items.len);

    const expected = [_]u8{ 3, 2, 1 };
    for (text.fragments.items, expected) |fragment_id, value| {
        switch (module.fragments.items.items[fragment_id.index]) {
            .bytes => |bytes| try std.testing.expectEqual(value, bytes.data[0]),
            else => return error.UnexpectedFragment,
        }
    }
}

test "lowering keeps Meta for iteration locals scoped per iteration" {
    try std.testing.expectError(
        error.InvalidExpression,
        lowerSource(
            std.testing.allocator,
            \\for i in range(0, 2) {
            \\    if i == 0 {
            \\        let first_only = 7
            \\    }
            \\    if i == 1 {
            \\        emit.u8(first_only);
            \\    }
            \\}
            \\
        ,
            .{},
        ),
    );
}

test "lowering keeps Meta function body locals inside call scope" {
    try std.testing.expectError(
        error.InvalidExpression,
        lowerSource(
            std.testing.allocator,
            \\fn emit_one(value: u64) {
            \\    let temp = value
            \\    emit.u8(temp);
            \\}
            \\emit_one(7);
            \\emit.u8(temp);
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects Meta function declarations in scoped blocks" {
    try std.testing.expectError(
        error.InvalidMetaFunction,
        lowerSource(
            std.testing.allocator,
            \\{
            \\    fn inner() {
            \\        emit.u8(1);
            \\    }
            \\}
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects recursive Meta function calls at depth limit" {
    try std.testing.expectError(
        error.MetaCallDepthExceeded,
        lowerSource(
            std.testing.allocator,
            \\fn recurse(value: u64) {
            \\    recurse(value);
            \\}
            \\recurse(1);
            \\
        ,
            .{},
        ),
    );
}

test "lowering calls Meta functions defined by source includes" {
    const files = [_]TestIncludeFile{
        .{
            .path = "src/shared/functions.xir",
            .bytes =
            \\fn emit_prefix(value: u64) {
            \\    emit.u8(value);
            \\}
            \\
            ,
        },
    };
    var resolver: TestIncludeResolver = .{ .files = &files };

    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try lowerSourceIntoModuleWithPathOptions(
        std.testing.allocator,
        &module,
        "src/main.xir",
        \\include("shared/functions.xir");
        \\emit_prefix(5);
        \\
    ,
        .{
            .include_resolver = .{
                .context = @ptrCast(&resolver),
                .resolve = TestIncludeResolver.resolve,
            },
        },
    );

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 5), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering isolates virtual output sections from main output" {
    var module = try lowerSource(
        std.testing.allocator,
        \\emit.u8(0xaa);
        \\virtual.begin(0x1000);
        \\VBox:
        \\emit.u8(0x11);
        \\reserve(2);
        \\emit.u8(0x22);
        \\virtual.end();
        \\after:
        \\emit.u8(0xbb);
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 2), module.sections.items.items.len);
    try std.testing.expectEqual(@as(usize, 1), module.virtual_sections.items.len);

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    const virtual_id = module.virtual_sections.items[0];
    const virtual = try module.sections.get(virtual_id);
    try std.testing.expectEqual(@as(u64, 0x1000), virtual.origin);
    try std.testing.expectEqual(@as(usize, 3), virtual.fragments.items.len);

    const vbox_id = module.symbols.lookup("VBox") orelse return error.MissingSymbol;
    const vbox = try module.symbols.get(vbox_id);
    switch (vbox.binding) {
        .label => |label| {
            try std.testing.expectEqual(virtual_id.index, label.section.index);
            try std.testing.expectEqual(@as(u64, 0), label.offset);
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const after_id = module.symbols.lookup("after") orelse return error.MissingSymbol;
    const after = try module.symbols.get(after_id);
    switch (after.binding) {
        .label => |label| {
            try std.testing.expectEqual(module.default_section.index, label.section.index);
            try std.testing.expectEqual(@as(u64, 1), label.offset);
        },
        else => return error.UnexpectedSymbolBinding,
    }
}

test "lowering defaults virtual output origin to active address" {
    var module = try lowerSource(
        std.testing.allocator,
        \\origin(0x7c00);
        \\emit.u8(0xaa);
        \\virtual.begin();
        \\emit.u8(0x11);
        \\virtual.end();
        \\
    ,
        .{},
    );
    defer module.deinit();

    const virtual_id = module.virtual_sections.items[0];
    const virtual = try module.sections.get(virtual_id);
    try std.testing.expectEqual(@as(u64, 0x7c01), virtual.origin);
}

test "lowering rejects unmatched virtual output boundaries" {
    try std.testing.expectError(
        error.UnmatchedVirtualEnd,
        lowerSource(
            std.testing.allocator,
            \\virtual.end();
            \\
        ,
            .{},
        ),
    );

    try std.testing.expectError(
        error.UnclosedVirtualOutput,
        lowerSource(
            std.testing.allocator,
            \\virtual.begin(0x1000);
            \\emit.u8(0x11);
            \\
        ,
            .{},
        ),
    );
}

test "lowering resolves sizeof type queries" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct SaveArea {
        \\    rax: u64,
        \\    rcx: u64,
        \\}
        \\pad(sizeof(SaveArea), 0);
        \\sub rsp, sizeof(SaveArea)
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(usize, 16), bytes.data.len),
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqualStrings("sub rsp, 16", instruction.text);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering emits struct literals and lengthof values" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16,
        \\    lfanew: u32,
        \\}
        \\emit.u8(lengthof("AB"));
        \\emit.struct(DosHeader { magic: 0x5a4d, lfanew: 0x80 });
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 2), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 6), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x4d), bytes.data[0]);
            try std.testing.expectEqual(@as(u8, 0x5a), bytes.data[1]);
            try std.testing.expectEqual(@as(u8, 0x80), bytes.data[2]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[3]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[4]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[5]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering emits stored struct values" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32,
        \\}
        \\const hdr: DosHeader = DosHeader { lfanew: 0x80 }
        \\emit.struct(hdr);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const hdr_id = module.symbols.lookup("hdr") orelse return error.MissingSymbol;
    const hdr_symbol = try module.symbols.get(hdr_id);
    switch (hdr_symbol.binding) {
        .value => |binding| {
            try std.testing.expectEqual(value_mod.Mutability.@"const", binding.mutability);
            const stored_struct = try binding.value.expectStruct();
            try std.testing.expectEqual(@as(usize, 2), stored_struct.fields.len);
            const magic = stored_struct.fieldByName("magic") orelse return error.MissingStructFieldValue;
            const lfanew = stored_struct.fieldByName("lfanew") orelse return error.MissingStructFieldValue;
            try std.testing.expectEqual(@as(u64, 0x5a4d), try magic.value.expectInteger());
            try std.testing.expectEqual(@as(u64, 0x80), try lfanew.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 6), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x4d), bytes.data[0]);
            try std.testing.expectEqual(@as(u8, 0x5a), bytes.data[1]);
            try std.testing.expectEqual(@as(u8, 0x80), bytes.data[2]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[3]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[4]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[5]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering accesses stored struct fields" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32,
        \\}
        \\const hdr: DosHeader = DosHeader { lfanew: 0x80 }
        \\const magic: u16 = hdr.magic
        \\emit.u16(hdr.magic);
        \\emit.u32(hdr.lfanew);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const magic_id = module.symbols.lookup("magic") orelse return error.MissingSymbol;
    const magic_symbol = try module.symbols.get(magic_id);
    switch (magic_symbol.binding) {
        .value => |binding| {
            const integer = try binding.value.expectIntegerValue();
            try std.testing.expectEqual(@as(u64, 0x5a4d), integer.value);
            const u16_id = module.lookupTypeName("u16") orelse return error.UnknownTypeName;
            try std.testing.expectEqual(u16_id.index, integer.type_id.?.index);
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, &.{ 0x4d, 0x5a }, bytes.data),
        else => return error.UnexpectedFragment,
    }
    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, &.{ 0x80, 0x00, 0x00, 0x00 }, bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering passes user struct values to Meta functions" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32,
        \\}
        \\fn emit_hdr(h: DosHeader) {
        \\    emit.struct(h);
        \\}
        \\const hdr: DosHeader = DosHeader { lfanew: 0x80 }
        \\emit_hdr(hdr);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, &.{ 0x4d, 0x5a, 0x80, 0x00, 0x00, 0x00 }, bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering packs struct values as bytes" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct Header {
        \\    magic: u16 = 0x4241,
        \\    tail: u16,
        \\}
        \\const hdr: Header = Header { tail: 0x4443 }
        \\const packed_hdr: bytes = pack(hdr)
        \\assert(pack(hdr) == b"ABCD");
        \\emit.u8(lengthof(pack(hdr)));
        \\emit.bytes(packed_hdr);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const packed_id = module.symbols.lookup("packed_hdr") orelse return error.MissingSymbol;
    const packed_symbol = try module.symbols.get(packed_id);
    switch (packed_symbol.binding) {
        .value => |binding| try std.testing.expectEqualSlices(u8, "ABCD", try binding.value.expectBytes()),
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, &.{4}, bytes.data),
        else => return error.UnexpectedFragment,
    }
    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, "ABCD", bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering evaluates inline aggregate builtin results with caller allocator" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();
    const u16_type = try module.getOrAddIntType("u16", 16, .unsigned);
    const u32_type = try module.getOrAddIntType("u32", 32, .unsigned);
    const header = try module.addStructType("Header", &.{
        .{ .name = "magic", .ty = u16_type },
        .{ .name = "lfanew", .ty = u32_type },
    }, .@"packed");
    try module.registerTypeName("Header", header);

    var context: LowerContext = .{};
    defer context.deinit(std.testing.allocator);
    const active: ActiveOutput = .{
        .section_id = module.default_section,
        .offset = 0,
        .file_offset = 0,
        .target = module.target,
    };

    var expression = try expr.parseOwned(std.testing.allocator, "pack(Header { magic: 0x5a4d, lfanew: 0x80 })");
    defer expression.deinit(std.testing.allocator);

    var buffer: [4096]u8 = undefined;
    var fixed = std.heap.FixedBufferAllocator.init(&buffer);
    const value_allocator = fixed.allocator();
    var value = try evalValueAtContext(value_allocator, &module, &context, active, &expression);
    defer value.deinit(value_allocator);

    switch (value) {
        .bytes => |packed_bytes| {
            try std.testing.expectEqualSlices(u8, &.{ 0x4d, 0x5a, 0x80, 0x00, 0x00, 0x00 }, packed_bytes);
            try std.testing.expect(fixed.ownsSlice(packed_bytes));
        },
        else => return error.InvalidApiArgument,
    }
}

test "lowering rejects unknown struct field access" {
    try std.testing.expectError(
        error.UnknownField,
        lowerSource(
            std.testing.allocator,
            \\packed struct DosHeader {
            \\    magic: u16 = 0x5a4d,
            \\}
            \\const hdr: DosHeader = DosHeader { }
            \\emit.u16(hdr.missing);
            \\
        ,
            .{},
        ),
    );
}

test "lowering emits struct literal default field values" {
    var module = try lowerSource(
        std.testing.allocator,
        \\packed struct DosHeader {
        \\    magic: u16 = 0x5a4d,
        \\    lfanew: u32 = 0x80,
        \\    checksum: u8,
        \\}
        \\emit.struct(DosHeader { checksum: 7 });
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 7), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x4d), bytes.data[0]);
            try std.testing.expectEqual(@as(u8, 0x5a), bytes.data[1]);
            try std.testing.expectEqual(@as(u8, 0x80), bytes.data[2]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[3]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[4]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[5]);
            try std.testing.expectEqual(@as(u8, 7), bytes.data[6]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering resolves const and let values in API and struct expressions" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const header_size: u64 = 4 * 2;
        \\let fill = 0xcc;
        \\packed struct Header {
        \\    magic: u16 = 0xaa55,
        \\    lfanew: u32,
        \\}
        \\emit.u8(fill);
        \\reserve(header_size);
        \\emit.struct(Header { lfanew: header_size + 0x20 });
        \\
    ,
        .{},
    );
    defer module.deinit();

    const header_size_id = module.symbols.lookup("header_size") orelse return error.MissingSymbol;
    const header_size = try module.symbols.get(header_size_id);
    switch (header_size.binding) {
        .value => |binding| {
            try std.testing.expectEqual(.@"const", binding.mutability);
            try std.testing.expectEqual(@as(u64, 8), try binding.value.expectInteger());
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 3), text.fragments.items.len);

    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 1), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0xcc), bytes.data[0]);
        },
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[1].index]) {
        .reserve => |reserve| try std.testing.expectEqual(@as(u64, 8), reserve.size),
        else => return error.UnexpectedFragment,
    }

    switch (module.fragments.items.items[text.fragments.items[2].index]) {
        .bytes => |bytes| {
            try std.testing.expectEqual(@as(usize, 6), bytes.data.len);
            try std.testing.expectEqual(@as(u8, 0x55), bytes.data[0]);
            try std.testing.expectEqual(@as(u8, 0xaa), bytes.data[1]);
            try std.testing.expectEqual(@as(u8, 0x28), bytes.data[2]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[3]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[4]);
            try std.testing.expectEqual(@as(u8, 0x00), bytes.data[5]);
        },
        else => return error.UnexpectedFragment,
    }
}

test "lowering stores Phase 1 Meta value types" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const ok: bool = true
        \\const name: string = "demo"
        \\const blob: bytes = b"AB"
        \\const word_ty: type = u32
        \\print(name, blob, word_ty);
        \\emit.bytes(blob);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const ok_id = module.symbols.lookup("ok") orelse return error.MissingSymbol;
    const ok_symbol = try module.symbols.get(ok_id);
    switch (ok_symbol.binding) {
        .value => |binding| {
            try std.testing.expectEqual(value_mod.Mutability.@"const", binding.mutability);
            try std.testing.expectEqual(true, try binding.value.expectBoolean());
        },
        else => return error.UnexpectedSymbolBinding,
    }

    const name_id = module.symbols.lookup("name") orelse return error.MissingSymbol;
    const name_symbol = try module.symbols.get(name_id);
    switch (name_symbol.binding) {
        .value => |binding| try std.testing.expectEqualStrings("demo", try binding.value.expectString()),
        else => return error.UnexpectedSymbolBinding,
    }

    const blob_id = module.symbols.lookup("blob") orelse return error.MissingSymbol;
    const blob_symbol = try module.symbols.get(blob_id);
    switch (blob_symbol.binding) {
        .value => |binding| try std.testing.expectEqualSlices(u8, "AB", try binding.value.expectBytes()),
        else => return error.UnexpectedSymbolBinding,
    }

    const word_ty_id = module.symbols.lookup("word_ty") orelse return error.MissingSymbol;
    const word_ty_symbol = try module.symbols.get(word_ty_id);
    switch (word_ty_symbol.binding) {
        .value => |binding| {
            const ty = try binding.value.expectType();
            const layout = try module.typeLayout(ty);
            try std.testing.expectEqual(@as(u64, 4), layout.size);
        },
        else => return error.UnexpectedSymbolBinding,
    }

    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
    try std.testing.expectEqualStrings("demo b\"AB\" type#0", module.diagnostics.items.items[0].message);

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, "AB", bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering uses bool expressions for Meta if and assert" {
    var module = try lowerSource(
        std.testing.allocator,
        \\const enabled: bool = true
        \\if enabled && 1 < 2 {
        \\    assert(enabled, "must pass");
        \\    emit.u8(0xaa);
        \\}
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqual(@as(u8, 0xaa), bytes.data[0]),
        else => return error.UnexpectedFragment,
    }
}

test "lowering type-checks Meta function parameters" {
    var module = try lowerSource(
        std.testing.allocator,
        \\fn emit_blob(flag: bool, data: bytes, ty: type) {
        \\    if flag && ty == u16 {
        \\        emit.bytes(data);
        \\    }
        \\}
        \\emit_blob(true, b"XY", u16);
        \\
    ,
        .{},
    );
    defer module.deinit();

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .bytes => |bytes| try std.testing.expectEqualSlices(u8, "XY", bytes.data),
        else => return error.UnexpectedFragment,
    }
}

test "lowering rejects Meta value type mismatches" {
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\const bad: MissingType = 1
            \\
        ,
            .{},
        ),
    );

    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\const bad: bool = 1
            \\
        ,
            .{},
        ),
    );

    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\const bad: bytes = "text"
            \\
        ,
            .{},
        ),
    );

    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\const bad: type = 1
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects Meta function argument type mismatches" {
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\fn need_bool(flag: bool) {
            \\    if flag {
            \\        emit.u8(1);
            \\    }
            \\}
            \\need_bool(1);
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects wrong struct argument type for Meta functions" {
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\packed struct DosHeader {
            \\    magic: u16 = 0x5a4d,
            \\}
            \\packed struct OtherHeader {
            \\    magic: u16 = 0xaa55,
            \\}
            \\fn emit_hdr(h: DosHeader) {
            \\    emit.struct(h);
            \\}
            \\emit_hdr(OtherHeader { });
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects struct value declaration type mismatches" {
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\packed struct DosHeader {
            \\    magic: u16 = 0x5a4d,
            \\}
            \\packed struct OtherHeader {
            \\    magic: u16 = 0xaa55,
            \\}
            \\const hdr: DosHeader = OtherHeader { }
            \\
        ,
            .{},
        ),
    );
}

test "lowering records ISA fragments without pass-owned fixups" {
    var module = try lowerSource(
        std.testing.allocator,
        \\entry:
        \\    jmp target
        \\target:
        \\    ret
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 0), module.fixups.items.items.len);

    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
}

test "lowering keeps x86 branch hints inside ISA fragments" {
    var module = try lowerSource(
        std.testing.allocator,
        \\entry:
        \\    jmp short target
        \\target:
        \\    ret
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 0), module.fixups.items.items.len);
    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 2), text.fragments.items.len);
}

test "lowering keeps riscv registers inside ISA fragments" {
    var module = try lowerSource(
        std.testing.allocator,
        \\riscv.use64();
        \\target:
        \\    addi x1, x0, target
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 0), module.fixups.items.items.len);
    const text = try module.sections.get(module.default_section);
    try std.testing.expectEqual(@as(usize, 1), text.fragments.items.len);
}

test "lowering keeps ISA expression text for backend adapter pass" {
    var module = try lowerSource(
        std.testing.allocator,
        \\target:
        \\    mov rax, target + 4
        \\
    ,
        .{},
    );
    defer module.deinit();

    try std.testing.expectEqual(@as(usize, 0), module.fixups.items.items.len);
    const text = try module.sections.get(module.default_section);
    switch (module.fragments.items.items[text.fragments.items[0].index]) {
        .isa_instruction => |instruction| try std.testing.expectEqualStrings("mov rax, target + 4", instruction.text),
        else => return error.UnexpectedFragment,
    }
}

test "lowering expression fixups can resolve label arithmetic" {
    var module = try lowerSource(
        std.testing.allocator,
        \\origin(0x1000);
        \\target:
        \\    mov rax, target + 4
        \\
    ,
        .{},
    );
    defer module.deinit();

    const encode_result = try pass.encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), encode_result.encoded_count);
    var result = try pass.resolveFixups(std.testing.allocator, &module);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.resolved_count);
    try std.testing.expectEqual(@as(usize, 0), result.pending_count);
    switch (result.items[0]) {
        .resolved => |resolved| try std.testing.expectEqual(@as(u64, 0x1004), resolved.value),
        else => return error.UnexpectedResolveState,
    }
}

test "lowering rejects unknown struct literal fields" {
    try std.testing.expectError(
        error.UnknownField,
        lowerSource(
            std.testing.allocator,
            \\packed struct DosHeader {
            \\    magic: u16,
            \\}
            \\emit.struct(DosHeader { magic: 0x5a4d, missing: 1 });
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects duplicate struct literal fields" {
    try std.testing.expectError(
        error.DuplicateFieldName,
        lowerSource(
            std.testing.allocator,
            \\packed struct DosHeader {
            \\    magic: u16,
            \\}
            \\emit.struct(DosHeader { magic: 1, magic: 2 });
            \\
        ,
            .{},
        ),
    );
}

test "lowering rejects union literals with multiple active fields" {
    try std.testing.expectError(
        error.InvalidValueDeclaration,
        lowerSource(
            std.testing.allocator,
            \\union ValueBits {
            \\    raw: u32,
            \\    tag: u8,
            \\}
            \\const bad: ValueBits = ValueBits { raw: 1, tag: 2 }
            \\
        ,
            .{},
        ),
    );
}
