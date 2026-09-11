const std = @import("std");

const frontend = @import("frontend/root.zig");

const Allocator = std.mem.Allocator;

const AssemblyError = error{
    FixupAddressOverflow,
    FixupPatchOutOfBounds,
    InvalidFixupWidth,
    RelativeFixupOutOfRange,
    SignedFixupOutOfRange,
    UnsignedFixupOutOfRange,
    WrapFixupOutOfRange,
};

pub const Stage = enum {
    encode,
    fixup_resolve,
    layout,
    materialize,
    patch,
    defer_finalizers,
};

pub const StageObserver = struct {
    context: *anyopaque,
    begin: *const fn (*anyopaque, Stage) void,
    end: *const fn (*anyopaque, Stage) void,
};

pub const FlatResult = struct {
    layout: frontend.ModuleLayout,
    bytes: []u8,
    encoded_count: usize,
    pending_fixups: usize,

    pub fn deinit(self: *FlatResult, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.layout.deinit(allocator);
        self.* = undefined;
    }
};

pub fn assembleFlat(
    allocator: Allocator,
    module: *frontend.Module,
    observer: ?StageObserver,
) !FlatResult {
    const encode_result = encode: {
        stageBegin(observer, .encode);
        defer stageEnd(observer, .encode);
        break :encode try frontend.encodeInstructionFragments(allocator, module);
    };

    try frontend.runLateLayoutPhase(allocator, module);

    var fixup_result = fixup: {
        stageBegin(observer, .fixup_resolve);
        defer stageEnd(observer, .fixup_resolve);
        break :fixup try frontend.resolveFixups(allocator, module);
    };
    defer fixup_result.deinit(allocator);

    var module_layout = layout: {
        stageBegin(observer, .layout);
        defer stageEnd(observer, .layout);
        break :layout try frontend.layoutModule(allocator, module);
    };
    errdefer module_layout.deinit(allocator);

    var writer_result = materialize: {
        stageBegin(observer, .materialize);
        defer stageEnd(observer, .materialize);
        break :materialize try frontend.writeOutput(allocator, .flat, module, &module_layout);
    };
    errdefer writer_result.deinit(allocator);

    try warnOnRegionFileOverlap(module, writer_result.regions);
    try warnOnSparseOutput(module, writer_result.regions, writer_result.bytes.len);

    {
        stageBegin(observer, .patch);
        defer stageEnd(observer, .patch);
        try patchResolvedFixups(writer_result.bytes, module, &module_layout, writer_result.regions, fixup_result);
    }
    {
        stageBegin(observer, .defer_finalizers);
        defer stageEnd(observer, .defer_finalizers);
        try runDeferredFinalizers(module, writer_result.regions, writer_result.bytes);
    }

    const output_bytes = writer_result.bytes;
    allocator.free(writer_result.regions);
    writer_result.bytes = &.{};
    writer_result.regions = &.{};

    return .{
        .layout = module_layout,
        .bytes = output_bytes,
        .encoded_count = encode_result.encoded_count,
        .pending_fixups = fixup_result.pending_count,
    };
}

fn stageBegin(observer: ?StageObserver, stage: Stage) void {
    if (observer) |active| active.begin(active.context, stage);
}

fn stageEnd(observer: ?StageObserver, stage: Stage) void {
    if (observer) |active| active.end(active.context, stage);
}

fn runDeferredFinalizers(
    module: *frontend.Module,
    image_regions: []const frontend.output.ImageRegion,
    bytes: []u8,
) anyerror!void {
    if (module.deferred.items.items.len == 0) return;

    const default_region = imageRegionForSection(image_regions, module.default_section) orelse return error.InvalidSection;

    const image: frontend.OutputImage = .{
        .section = module.default_section,
        .origin = default_region.origin,
        .regions = image_regions,
        .bytes = bytes,
    };
    var lower_context: frontend.lower.LowerContext = .{};
    defer lower_context.deinit(module.allocator);

    var state: FinalizerState = .{
        .allocator = module.allocator,
        .module = module,
        .image = image,
        .lower_context = &lower_context,
    };

    for (module.deferred.items.items) |block| {
        const previous_expansion = module.diagnostics.active_expansion;
        module.diagnostics.active_expansion = block.span.expansion;
        defer module.diagnostics.active_expansion = previous_expansion;
        try frontend.lower.pushMetaScope(state.lower_context, state.allocator);
        defer frontend.lower.popMetaScope(state.lower_context, state.allocator);
        if (block.captures) |captures| {
            for (captures.entries) |entry| {
                var value = try entry.value.clone(state.allocator);
                errdefer value.deinit(state.allocator);
                try frontend.lower.defineFinalLocalValue(state.lower_context, state.allocator, entry.key, value, .@"const");
            }
        }
        const diagnostic_start = module.diagnostics.items.items.len;
        runDeferredScopedStatements(&state, block.body) catch |err| {
            if (err == error.OutOfMemory) return err;
            if (module.diagnostics.items.items.len > diagnostic_start) return err;
            try addFinalizerDiagnostic(&state, block.span, err);
            return error.FrontendDiagnostics;
        };
    }
}

const FinalizerState = struct {
    allocator: Allocator,
    module: *frontend.Module,
    image: frontend.OutputImage,
    lower_context: *frontend.lower.LowerContext,
    in_meta_loop: bool = false,
};

fn runDeferredStatements(state: *FinalizerState, statements: []const frontend.DeferredStatement) anyerror!void {
    for (statements) |statement| {
        const diagnostic_start = state.module.diagnostics.items.items.len;
        runDeferredStatement(state, statement) catch |err| {
            // `break` and `continue` are control flow for the enclosing
            // finalizer loop, not failures, so they keep travelling.
            if (err == error.OutOfMemory or err == error.MetaLoopBreak or err == error.MetaLoopContinue) return err;
            if (state.module.diagnostics.items.items.len > diagnostic_start) return err;
            try addFinalizerDiagnostic(state, statement.span(), err);
            return error.FrontendDiagnostics;
        };
    }
}

/// A finalizer runs after the output image is sealed, so a failure here has no
/// lowering-time diagnostic to fall back on. Without this the reader sees only
/// `assembly failed: <error name>`, with no file, no line, and no reason -- and
/// the format library writes most of its backfills as plain `defer` blocks.
fn addFinalizerDiagnostic(state: *FinalizerState, span: frontend.SourceSpan, err: anyerror) !void {
    const message = if (finalizerErrorDetail(err)) |detail|
        try std.fmt.allocPrint(state.allocator, "{s} ({s})", .{ detail, @errorName(err) })
    else
        try std.fmt.allocPrint(state.allocator, "the finalizer failed: {s}", .{@errorName(err)});
    defer state.allocator.free(message);
    try state.module.diagnostics.add(state.allocator, .err, span, message);
}

fn finalizerErrorDetail(err: anyerror) ?[]const u8 {
    return switch (err) {
        error.InvalidApiArgument => "the finalizer touched bytes the finished output image does not hold; a reserved tail is not in the file",
        error.InvalidApiInteger => "the value does not fit the width of this finalizer store",
        error.InvalidApiArity => "this finalizer call passes the wrong number of arguments",
        error.OffsetOverflow => "the address is too large for the output image",
        error.InvalidSection => "the address does not belong to a region of the output image",
        error.FinalizerCannotChangeLayout => "a finalizer can patch bytes, but it cannot emit bytes, define labels, or change regions",
        error.UndefinedSymbol => "the name is not defined where the finalizer uses it",
        error.DivisionByZero => "the expression divides by zero",
        error.InvalidOperand => "this operand cannot be evaluated in a finalizer",
        else => null,
    };
}

fn byteCountWord(count: usize) []const u8 {
    return if (count == 1) "byte" else "bytes";
}

fn runDeferredStatement(state: *FinalizerState, statement: frontend.DeferredStatement) anyerror!void {
    switch (statement) {
        .api_call => |call| try runDeferredApiCall(state, call),
        .value_decl => |declaration| try runDeferredValueDeclaration(state, declaration),
        .assignment => |assignment| try runDeferredAssignment(state, assignment),
        .meta_if => |meta_if| {
            if (try evalDeferredCondition(state, meta_if.condition)) {
                try runDeferredScopedStatements(state, meta_if.body);
            } else {
                try runDeferredScopedStatements(state, meta_if.else_body);
            }
        },
        .meta_while => |meta_while| try runDeferredWhile(state, meta_while),
        .meta_break => |span| {
            if (state.in_meta_loop) return error.MetaLoopBreak;
            try addDeferredLoopControlDiagnostic(state, span, "break");
            return error.FrontendDiagnostics;
        },
        .meta_continue => |span| {
            if (state.in_meta_loop) return error.MetaLoopContinue;
            try addDeferredLoopControlDiagnostic(state, span, "continue");
            return error.FrontendDiagnostics;
        },
    }
}

fn runDeferredScopedStatements(state: *FinalizerState, statements: []const frontend.DeferredStatement) anyerror!void {
    try frontend.lower.pushMetaScope(state.lower_context, state.allocator);
    defer frontend.lower.popMetaScope(state.lower_context, state.allocator);
    try runDeferredStatements(state, statements);
}

fn runDeferredValueDeclaration(state: *FinalizerState, declaration: frontend.output.ValueDeclaration) !void {
    var node = try frontend.expr.parseOwned(state.allocator, declaration.value_text);
    defer node.deinit(state.allocator);

    var value = try deferredEvalValue(state, &node);
    errdefer value.deinit(state.allocator);

    const annotation = try frontend.typecheck.annotationFromName(state.module, declaration.type_name);
    if (declaration.type_name != null and annotation == null) return error.InvalidValueDeclaration;
    try frontend.typecheck.coerceValueToAnnotation(state.module, &value, annotation);

    try frontend.lower.defineFinalLocalValue(
        state.lower_context,
        state.allocator,
        declaration.name,
        value,
        declaration.mutability,
    );
}

fn runDeferredAssignment(state: *FinalizerState, assignment: frontend.output.Assignment) !void {
    var node = try frontend.expr.parseOwned(state.allocator, assignment.value_text);
    defer node.deinit(state.allocator);

    var value = try deferredEvalValue(state, &node);
    errdefer value.deinit(state.allocator);

    if (try frontend.lower.setFinalLocalValue(state.lower_context, state.allocator, assignment.name, value)) {
        return;
    }
    return error.InvalidValueDeclaration;
}

fn runDeferredWhile(state: *FinalizerState, meta_while: frontend.output.MetaWhile) anyerror!void {
    const previous_in_meta_loop = state.in_meta_loop;
    state.in_meta_loop = true;
    defer state.in_meta_loop = previous_in_meta_loop;

    var iterations: usize = 0;
    while (try evalDeferredCondition(state, meta_while.condition)) {
        if (iterations >= frontend.lower.max_finalizer_loop_iterations) return error.MetaLoopLimitExceeded;
        runDeferredScopedStatements(state, meta_while.body) catch |err| switch (err) {
            error.MetaLoopBreak => return,
            error.MetaLoopContinue => {},
            else => return err,
        };
        iterations += 1;
    }
}

fn addDeferredLoopControlDiagnostic(
    state: *FinalizerState,
    span: frontend.SourceSpan,
    keyword: []const u8,
) !void {
    const message = try std.fmt.allocPrint(state.allocator, "{s} used outside of a Meta loop", .{keyword});
    defer state.allocator.free(message);
    try state.module.diagnostics.add(state.allocator, .err, span, message);
}

fn runDeferredApiCall(state: *FinalizerState, call: frontend.output.ApiCall) !void {
    var parsed = try frontend.parser.parseApiCallText(state.allocator, call.text, call.span);
    defer parsed.deinit(state.allocator);

    if (std.mem.eql(u8, parsed.callee, "store.bytes")) {
        try runDeferredStoreBytes(state, parsed);
        return;
    }

    if (storeByteCount(parsed.callee)) |byte_count| {
        try runDeferredStoreInteger(state, parsed, byte_count);
        return;
    }

    if (std.mem.eql(u8, parsed.callee, "assert")) {
        try runDeferredAssert(state, parsed);
        return;
    }

    if (std.mem.eql(u8, parsed.callee, "print")) {
        try addDeferredDiagnostic(state, parsed, .note);
        return;
    }

    if (std.mem.eql(u8, parsed.callee, "warn")) {
        try addDeferredDiagnostic(state, parsed, .warning);
        return;
    }

    if (std.mem.eql(u8, parsed.callee, "err")) {
        try addDeferredDiagnostic(state, parsed, .err);
        return error.FrontendDiagnostics;
    }

    return error.FinalizerCannotChangeLayout;
}

fn runDeferredStoreBytes(state: *FinalizerState, call: frontend.ast.ApiCallStatement) !void {
    if (call.args.len != 2) return error.InvalidApiArity;
    const target = try deferredOutputTarget(state, call, 0);
    var value = try deferredValueArg(state, call, 1);
    defer value.deinit(state.allocator);
    const bytes = switch (value) {
        .bytes => |data| data,
        .string => |text| text,
        .operand, .void, .integer, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
    };
    const result = if (target.explicit_section)
        state.image.storeBytesInSection(target.section, target.address, bytes)
    else
        state.image.storeBytes(target.address, bytes);
    result catch |err| return reportFinalizerStoreFailure(state, call, target.address, bytes.len, err);
}

fn runDeferredStoreInteger(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    byte_count: u8,
) !void {
    if (call.args.len != 2) return error.InvalidApiArity;
    const target = try deferredOutputTarget(state, call, 0);
    const value = try deferredIntegerArg(state, call, 1);
    const result = if (target.explicit_section)
        state.image.storeIntegerInSection(target.section, target.address, value, byte_count)
    else
        state.image.storeInteger(target.address, value, byte_count);
    result catch |err| return reportFinalizerStoreFailure(state, call, target.address, byte_count, err);
}

/// The image reports one argument error for every address it cannot reach, which
/// does not say which write failed or why. `target.address` is already resolved
/// here, so the diagnostic can name the address, the width, and the file length.
fn reportFinalizerStoreFailure(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    address: u64,
    byte_count: usize,
    err: anyerror,
) anyerror {
    if (err == error.OutOfMemory) return err;
    const message = switch (err) {
        error.InvalidApiArgument, error.OffsetOverflow => std.fmt.allocPrint(
            state.allocator,
            "this store writes {d} {s} at 0x{x}, but the finished output image holds {d} {s}; a reserved tail is not in the file ({s})",
            .{ byte_count, byteCountWord(byte_count), address, state.image.bytes.len, byteCountWord(state.image.bytes.len), @errorName(err) },
        ),
        error.InvalidApiInteger => std.fmt.allocPrint(
            state.allocator,
            "the value does not fit the {d} {s} written at 0x{x} ({s})",
            .{ byte_count, byteCountWord(byte_count), address, @errorName(err) },
        ),
        else => std.fmt.allocPrint(
            state.allocator,
            "this store cannot be applied to the finished output image: {s}",
            .{@errorName(err)},
        ),
    } catch return error.OutOfMemory;
    defer state.allocator.free(message);
    state.module.diagnostics.add(state.allocator, .err, call.span, message) catch return error.OutOfMemory;
    return error.FrontendDiagnostics;
}

fn runDeferredAssert(state: *FinalizerState, call: frontend.ast.ApiCallStatement) !void {
    if (call.args.len != 1 and call.args.len != 2) return error.InvalidApiArity;
    if (try deferredBooleanArg(state, call, 0)) return;

    const message = if (call.args.len == 2)
        try formatDeferredDiagnosticArg(state, &call.args[1])
    else
        try state.allocator.dupe(u8, "assertion failed");
    defer state.allocator.free(message);

    try state.module.diagnostics.add(state.allocator, .err, call.span, message);
    return error.FrontendDiagnostics;
}

fn addDeferredDiagnostic(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    severity: frontend.diagnostic.Severity,
) !void {
    if (call.args.len == 0) return error.InvalidApiArity;
    var message: std.ArrayList(u8) = .empty;
    errdefer message.deinit(state.allocator);
    for (call.args, 0..) |*arg, index| {
        if (index != 0) try message.append(state.allocator, ' ');
        const text = try formatDeferredDiagnosticArg(state, arg);
        defer state.allocator.free(text);
        try message.appendSlice(state.allocator, text);
    }
    const owned = try message.toOwnedSlice(state.allocator);
    defer state.allocator.free(owned);
    try state.module.diagnostics.add(state.allocator, severity, call.span, owned);
}

fn evalDeferredCondition(state: *FinalizerState, condition: []const u8) !bool {
    const trimmed = std.mem.trim(u8, condition, " \t\r\n");
    if (trimmed.len == 0) return error.InvalidMetaIf;
    if (std.mem.eql(u8, trimmed, "true")) return true;
    if (std.mem.eql(u8, trimmed, "false")) return false;

    var node = try frontend.expr.parseOwned(state.allocator, trimmed);
    defer node.deinit(state.allocator);
    return deferredEvalBoolean(state, &node);
}

fn deferredIntegerArg(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    index: usize,
) !u64 {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| deferredEvalInteger(state, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn deferredOutputTarget(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    index: usize,
) !frontend.expr.OutputExpressionTarget {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| blk: {
            var ctx = deferredEvalContext(state);
            break :blk try frontend.expr.resolveOutputExpressionTarget(state.allocator, &ctx, node);
        },
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn deferredBooleanArg(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    index: usize,
) !bool {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| deferredEvalBoolean(state, node),
        .string, .struct_literal => error.InvalidApiArgument,
    };
}

fn deferredValueArg(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    index: usize,
) !frontend.Value {
    if (index >= call.args.len) return error.InvalidApiArity;
    return switch (call.args[index]) {
        .expression => |*node| deferredEvalValue(state, node),
        .string => |text| .{ .string = try state.allocator.dupe(u8, text) },
        .struct_literal => error.InvalidApiArgument,
    };
}

fn deferredEvalInteger(state: *FinalizerState, node: *const frontend.expr.Node) !u64 {
    var ctx = deferredEvalContext(state);
    return frontend.expr.evaluateInteger(node, &ctx);
}

fn deferredEvalBoolean(state: *FinalizerState, node: *const frontend.expr.Node) !bool {
    var ctx = deferredEvalContext(state);
    return frontend.expr.evaluateBoolean(node, &ctx);
}

fn deferredEvalValue(state: *FinalizerState, node: *const frontend.expr.Node) !frontend.Value {
    var ctx = deferredEvalContext(state);
    return frontend.expr.evaluateValue(state.allocator, node, &ctx);
}

fn deferredEvalContext(state: *FinalizerState) frontend.expr.EvalContext {
    return .{
        .module = state.module,
        .active_section = state.image.section,
        .active_offset = 0,
        .output_image = state.image,
        .local_context = state.lower_context,
        .resolve_local = frontend.lower.resolveLocalValue,
        .call_user_function = frontend.lower.evalModuleValueFunction,
        .evaluate_struct_literal = frontend.lower.evalModuleStructLiteralValue,
        .eval_operand = frontend.lower.evalModuleOperand,
    };
}

fn formatDeferredDiagnosticArg(
    state: *FinalizerState,
    arg: *const frontend.ast.ApiArgument,
) ![]u8 {
    return switch (arg.*) {
        .string => |text| state.allocator.dupe(u8, text),
        .struct_literal => error.InvalidApiArgument,
        .expression => |*node| blk: {
            var value = try deferredEvalValue(state, node);
            defer value.deinit(state.allocator);
            break :blk formatDeferredValue(state.allocator, value);
        },
    };
}

fn formatDeferredValue(allocator: Allocator, value: frontend.Value) ![]u8 {
    return switch (value) {
        .void => allocator.dupe(u8, "void"),
        .boolean => |boolean| allocator.dupe(u8, if (boolean) "true" else "false"),
        .integer => |integer| std.fmt.allocPrint(allocator, "{d}", .{integer.value}),
        .float32 => |stored| frontend.formatFloat32Literal(allocator, stored),
        .float64 => |stored| frontend.formatFloatLiteral(allocator, stored),
        .string => |text| allocator.dupe(u8, text),
        .bytes => |bytes| formatBytesValue(allocator, bytes),
        .type => |id| std.fmt.allocPrint(allocator, "type({d})", .{id.index}),
        .operand, .@"struct", .list, .map => error.InvalidApiArgument,
    };
}

fn formatBytesValue(allocator: Allocator, bytes: []const u8) ![]u8 {
    const out = try allocator.alloc(u8, bytes.len * 2);
    for (bytes, 0..) |byte, index| {
        const hex = "0123456789abcdef";
        out[index * 2] = hex[byte >> 4];
        out[index * 2 + 1] = hex[byte & 0x0f];
    }
    return out;
}

fn storeByteCount(name: []const u8) ?u8 {
    if (std.mem.eql(u8, name, "store.u8")) return 1;
    if (std.mem.eql(u8, name, "store.u16")) return 2;
    if (std.mem.eql(u8, name, "store.u32")) return 4;
    if (std.mem.eql(u8, name, "store.u64")) return 8;
    return null;
}

fn patchResolvedFixups(
    bytes: []u8,
    module: *frontend.Module,
    module_layout: *const frontend.ModuleLayout,
    image_regions: []const frontend.output.ImageRegion,
    fixup_result: frontend.FixupPassResult,
) (AssemblyError || anyerror)!void {
    for (fixup_result.items, 0..) |state, state_index| {
        switch (state) {
            .pending => {},
            .resolved => |resolved| {
                const stored_fixup = try fixupAt(module, resolved.fixup);
                if (isRiscvInstructionFixup(module, stored_fixup)) {
                    if (!hasEarlierFixupForFragment(module, state_index, stored_fixup.fragment)) {
                        try patchResolvedRiscvInstruction(
                            bytes,
                            module,
                            module_layout,
                            image_regions,
                            fixup_result,
                            stored_fixup.fragment,
                        );
                    }
                    continue;
                }
                const section_id = try sectionForFragment(module, stored_fixup.fragment);
                const section_layout = module_layout.sectionLayout(section_id) orelse return error.InvalidSection;
                const image_region = imageRegionForSection(image_regions, section_id) orelse {
                    try reportInstructionOutsideImage(module, stored_fixup.span, fixupTargetText(stored_fixup));
                    return error.FrontendDiagnostics;
                };
                const fragment_offset = module_layout.fragmentOffset(stored_fixup.fragment) orelse return error.InvalidFragment;
                patchOneFixup(bytes, section_layout.*, image_region, fragment_offset, stored_fixup, resolved.value) catch |err| {
                    try addFixupPatchDiagnostic(module, stored_fixup, resolved.value, err);
                    return error.FrontendDiagnostics;
                };
            },
        }
    }
}

fn isRiscvInstructionFixup(module: *const frontend.Module, stored_fixup: frontend.Fixup) bool {
    if (stored_fixup.fragment.index >= module.fragments.items.items.len) return false;
    return switch (module.fragments.items.items[stored_fixup.fragment.index]) {
        .isa_instruction => |instruction| instruction.target.isa() == .riscv64,
        else => false,
    };
}

fn hasEarlierFixupForFragment(
    module: *const frontend.Module,
    state_index: usize,
    fragment_id: frontend.FragmentId,
) bool {
    var index: usize = 0;
    while (index < state_index and index < module.fixups.items.items.len) : (index += 1) {
        if (module.fixups.items.items[index].fragment.index == fragment_id.index) return true;
    }
    return false;
}

fn patchResolvedRiscvInstruction(
    bytes: []u8,
    module: *frontend.Module,
    module_layout: *const frontend.ModuleLayout,
    image_regions: []const frontend.output.ImageRegion,
    fixup_result: frontend.FixupPassResult,
    fragment_id: frontend.FragmentId,
) (AssemblyError || anyerror)!void {
    if (fragment_id.index >= module.fragments.items.items.len) return error.InvalidFragment;
    const instruction = switch (module.fragments.items.items[fragment_id.index]) {
        .isa_instruction => |active| active,
        else => return error.InvalidFragment,
    };
    if (instruction.target.isa() != .riscv64) return error.InvalidFixupTarget;
    if (module.fixups.items.items.len != fixup_result.items.len) return error.InvalidFixupTarget;

    // The backend source parser accepts at most 16 operands, so one instruction
    // cannot produce more than 16 resolver-backed fixups.
    var resolution_storage: [16]frontend.RiscvResolution = undefined;
    var resolution_count: usize = 0;
    for (module.fixups.items.items, fixup_result.items, 0..) |candidate, state, state_index| {
        if (candidate.fragment.index != fragment_id.index) continue;
        const resolved = switch (state) {
            .pending => return,
            .resolved => |active| active,
        };
        if (resolved.fixup.index != state_index) return error.InvalidFixupTarget;
        if (resolution_count >= resolution_storage.len) return error.InvalidFixupTarget;
        resolution_storage[resolution_count] = .{
            .target = fixupTargetText(candidate),
            .value = resolved.value,
        };
        resolution_count += 1;
    }
    if (resolution_count == 0) return error.InvalidFixupTarget;

    const section_id = instruction.section;
    const section_layout = module_layout.sectionLayout(section_id) orelse return error.InvalidSection;
    const image_region = imageRegionForSection(image_regions, section_id) orelse {
        try reportInstructionOutsideImage(module, instruction.span, resolution_storage[0].target);
        return error.FrontendDiagnostics;
    };
    const fragment_offset = module_layout.fragmentOffset(fragment_id) orelse return error.InvalidFragment;
    const instruction_address = std.math.add(u64, section_layout.origin, fragment_offset) catch return error.OffsetOverflow;
    var encoded = try frontend.encodeResolvedRiscvInstruction(
        instruction,
        module.target,
        instruction_address,
        resolution_storage[0..resolution_count],
    );
    const encoded_bytes = encoded.asSlice();
    // An instruction fragment's file size is always its current size: the layout
    // gives it `logical_size` and trims only a trailing `reserve`, so comparing
    // against `fragment_offset`'s neighbour is unnecessary -- and looking the
    // fragment's layout entry up here cost a scan of the whole section for every
    // branch that needed re-encoding.
    if (encoded_bytes.len != instruction.current_size) {
        return error.InvalidFixupTarget;
    }
    const patch_end_relative = std.math.add(u64, fragment_offset, encoded_bytes.len) catch return error.OffsetOverflow;
    if (patch_end_relative > image_region.file_size) return error.InvalidFixupTarget;

    const patch_offset = std.math.add(u64, image_region.file_offset, fragment_offset) catch return error.OffsetOverflow;
    const patch_start = try sizeToUsize(patch_offset);
    const patch_end = std.math.add(usize, patch_start, encoded_bytes.len) catch return error.OffsetOverflow;
    if (patch_end > bytes.len) return error.InvalidFixupTarget;
    @memcpy(bytes[patch_start..patch_end], encoded_bytes);
}

fn fixupTargetText(stored_fixup: frontend.Fixup) []const u8 {
    return switch (stored_fixup.target) {
        .symbol => |symbol| symbol,
        .expression_text => |text| text,
    };
}

fn imageRegionForSection(
    image_regions: []const frontend.output.ImageRegion,
    section_id: frontend.section.SectionId,
) ?frontend.output.ImageRegion {
    for (image_regions) |region| {
        if (region.section.index == section_id.index) return region;
    }
    return null;
}

fn fixupAt(module: *const frontend.Module, id: frontend.FixupId) !frontend.Fixup {
    if (id.index >= module.fixups.items.items.len) return error.InvalidFixupTarget;
    return module.fixups.items.items[id.index];
}

fn sectionForFragment(module: *const frontend.Module, fragment_id: frontend.FragmentId) !frontend.section.SectionId {
    if (fragment_id.index >= module.fragments.items.items.len) return error.InvalidFragment;
    return switch (module.fragments.items.items[fragment_id.index]) {
        .bytes => |payload| payload.section,
        .reserve => |payload| payload.section,
        .alignment => |payload| payload.section,
        .isa_instruction => |payload| payload.section,
    };
}

/// A region placed far past the data before it turns the output into mostly
/// zeros. One digit too many in a file offset -- writing `0x1_0000_0000` where
/// `0x40_0000` was meant -- costs gigabytes of disk and a long write, and
/// nothing in the source looks wrong. Holes are allowed on purpose, so this
/// warns instead of failing.
fn warnOnSparseOutput(
    module: *frontend.Module,
    image_regions: []const frontend.output.ImageRegion,
    output_bytes: usize,
) !void {
    const hole_threshold: u64 = 1 << 20;
    var written: u64 = 0;
    for (image_regions) |region| {
        written = std.math.add(u64, written, region.file_size) catch return;
    }
    const total: u64 = @intCast(output_bytes);
    if (total <= written) return;
    const holes = total - written;
    if (holes < hole_threshold) return;

    const message = try std.fmt.allocPrint(
        module.allocator,
        "the output is {d} bytes but the source writes only {d} of them; {d} bytes are holes, so check a region's file offset",
        .{ total, written, holes },
    );
    defer module.allocator.free(message);
    try module.diagnostics.add(
        module.allocator,
        frontend.diagnostic.Severity.warning,
        frontend.source.unknown_span,
        message,
    );
}

/// `region.begin` places output by file offset, so two regions can claim the
/// same file bytes and the later one silently overwrites the earlier one. The
/// language leaves ordering, holes, and overlap to the caller, so this warns
/// instead of failing -- but it is the one path that can quietly change bytes
/// that were already written.
fn warnOnRegionFileOverlap(
    module: *frontend.Module,
    image_regions: []const frontend.output.ImageRegion,
) !void {
    for (image_regions, 0..) |region, index| {
        if (region.file_size == 0) continue;
        const region_end = std.math.add(u64, region.file_offset, region.file_size) catch continue;
        for (image_regions[index + 1 ..]) |other| {
            if (other.file_size == 0) continue;
            const other_end = std.math.add(u64, other.file_offset, other.file_size) catch continue;
            if (region.file_offset >= other_end or other.file_offset >= region_end) continue;

            const message = try std.fmt.allocPrint(
                module.allocator,
                "region '{s}' writes file bytes 0x{x}..0x{x} and region '{s}' writes 0x{x}..0x{x}; the shared bytes are written twice, and the later region wins",
                .{
                    sectionName(module, region.section),
                    region.file_offset,
                    region_end,
                    sectionName(module, other.section),
                    other.file_offset,
                    other_end,
                },
            );
            defer module.allocator.free(message);
            try module.diagnostics.add(
                module.allocator,
                frontend.diagnostic.Severity.warning,
                frontend.source.unknown_span,
                message,
            );
        }
    }
}

fn sectionName(module: *frontend.Module, section_id: frontend.section.SectionId) []const u8 {
    const stored = module.sections.get(section_id) catch return "?";
    return stored.name;
}

fn patchOneFixup(
    bytes: []u8,
    section_layout: frontend.SectionLayout,
    image_region: frontend.output.ImageRegion,
    fragment_offset: u64,
    stored_fixup: frontend.Fixup,
    target_value: u64,
) AssemblyError!void {
    const width_bytes = try fixupWidthBytes(stored_fixup.width_bits);
    const section_relative_patch_offset = std.math.add(u64, fragment_offset, stored_fixup.offset) catch return error.FixupAddressOverflow;
    const patch_end_relative = std.math.add(u64, section_relative_patch_offset, width_bytes) catch return error.FixupAddressOverflow;
    if (patch_end_relative > image_region.file_size) return error.FixupPatchOutOfBounds;
    const patch_offset = std.math.add(u64, image_region.file_offset, section_relative_patch_offset) catch return error.FixupAddressOverflow;
    const patch_start = std.math.cast(usize, patch_offset) orelse return error.FixupAddressOverflow;
    const patch_end = std.math.add(usize, patch_start, width_bytes) catch return error.FixupAddressOverflow;
    if (patch_end > bytes.len) return error.FixupPatchOutOfBounds;

    const value = switch (stored_fixup.kind) {
        .absolute => try absolutePatchValue(target_value, stored_fixup.width_bits, stored_fixup.value_range),
        .pc_relative => value: {
            const next_ip_offset = std.math.add(u64, section_relative_patch_offset, width_bytes) catch return error.FixupAddressOverflow;
            const next_ip = std.math.add(u64, section_layout.origin, next_ip_offset) catch return error.FixupAddressOverflow;
            break :value try relativePatchValue(target_value, next_ip, stored_fixup.width_bits);
        },
    };
    writeSignedLittleEndian(bytes[patch_start..patch_end], value);
}

fn fixupWidthBytes(width_bits: u16) AssemblyError!usize {
    if (width_bits == 0 or width_bits % 8 != 0) return error.InvalidFixupWidth;
    const width_bytes = width_bits / 8;
    if (width_bytes != 1 and width_bytes != 2 and width_bytes != 4 and width_bytes != 8) return error.InvalidFixupWidth;
    return @intCast(width_bytes);
}

fn absolutePatchValue(value: u64, width_bits: u16, value_range: frontend.fixup.ValueRange) AssemblyError!i64 {
    const signed_value: i64 = @bitCast(value);
    const unsigned_fits = switch (width_bits) {
        8 => value <= std.math.maxInt(u8),
        16 => value <= std.math.maxInt(u16),
        32 => value <= std.math.maxInt(u32),
        64 => true,
        else => return error.InvalidFixupWidth,
    };
    const signed_fits = switch (width_bits) {
        8 => signed_value >= std.math.minInt(i8) and signed_value <= std.math.maxInt(i8),
        16 => signed_value >= std.math.minInt(i16) and signed_value <= std.math.maxInt(i16),
        32 => signed_value >= std.math.minInt(i32) and signed_value <= std.math.maxInt(i32),
        64 => true,
        else => return error.InvalidFixupWidth,
    };
    const fits = switch (value_range) {
        .wrap => unsigned_fits or signed_fits,
        .signed => signed_fits,
        .unsigned => unsigned_fits,
    };
    if (!fits) return switch (value_range) {
        .wrap => error.WrapFixupOutOfRange,
        .signed => error.SignedFixupOutOfRange,
        .unsigned => error.UnsignedFixupOutOfRange,
    };
    return signed_value;
}

test "absolute fixup values honor backend signedness" {
    try std.testing.expectEqual(@as(i64, 127), try absolutePatchValue(127, 8, .signed));
    try std.testing.expectEqual(@as(i64, -128), try absolutePatchValue(@bitCast(@as(i64, -128)), 8, .signed));
    try std.testing.expectError(error.SignedFixupOutOfRange, absolutePatchValue(128, 8, .signed));
    try std.testing.expectError(error.SignedFixupOutOfRange, absolutePatchValue(0x80000000, 32, .signed));
    try std.testing.expectEqual(@as(i64, -1), try absolutePatchValue(std.math.maxInt(u64), 64, .wrap));
    try std.testing.expectEqual(@as(i64, 255), try absolutePatchValue(255, 8, .unsigned));
    try std.testing.expectError(error.UnsignedFixupOutOfRange, absolutePatchValue(256, 8, .unsigned));
    try std.testing.expectError(error.WrapFixupOutOfRange, absolutePatchValue(256, 8, .wrap));
    try std.testing.expectError(error.InvalidFixupWidth, absolutePatchValue(0, 128, .wrap));
}

test "fixup patching distinguishes invalid widths bounds and address overflow" {
    try std.testing.expectError(error.InvalidFixupWidth, fixupWidthBytes(12));
    try std.testing.expectError(error.RelativeFixupOutOfRange, relativePatchValue(128, 0, 8));

    var target = [_]u8{ 't', 'a', 'r', 'g', 'e', 't' };
    const section_layout: frontend.SectionLayout = .{
        .section = .{ .index = 0 },
        .origin = 0,
        .file_offset = 0,
        .logical_size = 1,
        .file_size = 1,
        .fragments = &.{},
    };
    const image_region: frontend.output.ImageRegion = .{
        .section = .{ .index = 0 },
        .origin = 0,
        .file_offset = 0,
        .logical_size = 1,
        .file_size = 1,
    };
    var bytes = [_]u8{0};
    const base_fixup: frontend.Fixup = .{
        .fragment = .{ .index = 0 },
        .target = .{ .symbol = &target },
        .kind = .absolute,
        .offset = 0,
        .width_bits = 16,
        .span = frontend.source.unknown_span,
    };

    try std.testing.expectError(
        error.FixupPatchOutOfBounds,
        patchOneFixup(
            &bytes,
            section_layout,
            image_region,
            0,
            base_fixup,
            0,
        ),
    );

    var overflow_fixup = base_fixup;
    overflow_fixup.width_bits = 8;
    overflow_fixup.offset = 1;
    try std.testing.expectError(
        error.FixupAddressOverflow,
        patchOneFixup(
            &bytes,
            section_layout,
            image_region,
            std.math.maxInt(u64),
            overflow_fixup,
            0,
        ),
    );
}

fn relativePatchValue(target_value: u64, next_ip: u64, width_bits: u16) AssemblyError!i64 {
    const target_i128: i128 = @intCast(target_value);
    const next_ip_i128: i128 = @intCast(next_ip);
    const value = target_i128 - next_ip_i128;
    switch (width_bits) {
        8 => if (value < std.math.minInt(i8) or value > std.math.maxInt(i8)) return error.RelativeFixupOutOfRange,
        16 => if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) return error.RelativeFixupOutOfRange,
        32 => if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.RelativeFixupOutOfRange,
        64 => if (value < std.math.minInt(i64) or value > std.math.maxInt(i64)) return error.RelativeFixupOutOfRange,
        else => return error.InvalidFixupWidth,
    }
    return @intCast(value);
}

/// An instruction whose region is not part of the output image cannot receive
/// its resolved reference. A virtual region is the usual cause: its bytes enter
/// the file only where the source copies them, and a copy is a snapshot taken
/// before references are patched. Writing the field now would not reach that
/// copy, and skipping the write would leave the encoded placeholder in it, so
/// the instruction is refused where it is written instead.
fn reportInstructionOutsideImage(
    module: *frontend.Module,
    span: frontend.SourceSpan,
    target: []const u8,
) !void {
    const message = try std.fmt.allocPrint(
        module.allocator,
        "instruction referencing '{s}' needs a resolved field, but its region is not part of the output image; put the virtual region in the file with region.place, because bytes copied out with emit.bytes keep the encoded placeholder",
        .{target},
    );
    defer module.allocator.free(message);
    try module.diagnostics.add(
        module.allocator,
        frontend.diagnostic.Severity.err,
        span,
        message,
    );
}

fn addFixupPatchDiagnostic(
    module: *frontend.Module,
    stored_fixup: frontend.Fixup,
    target_value: u64,
    patch_error: AssemblyError,
) !void {
    const message = try fixupPatchDiagnostic(
        module.allocator,
        fixupTargetText(stored_fixup),
        stored_fixup.width_bits,
        target_value,
        patch_error,
    );
    defer module.allocator.free(message);
    try module.diagnostics.add(
        module.allocator,
        frontend.diagnostic.Severity.err,
        stored_fixup.span,
        message,
    );
}

fn fixupPatchDiagnostic(
    allocator: Allocator,
    target: []const u8,
    width_bits: u16,
    target_value: u64,
    patch_error: AssemblyError,
) Allocator.Error![]u8 {
    return switch (patch_error) {
        error.InvalidFixupWidth => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' uses unsupported {d}-bit field width; supported widths are 8, 16, 32, and 64 bits",
            .{ target, width_bits },
        ),
        error.FixupPatchOutOfBounds => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' writes a {d}-bit field outside the output image",
            .{ target, width_bits },
        ),
        error.FixupAddressOverflow => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' overflows address arithmetic for its {d}-bit field",
            .{ target, width_bits },
        ),
        error.RelativeFixupOutOfRange => std.fmt.allocPrint(
            allocator,
            "PC-relative fixup target '{s}' (0x{x}) does not fit the signed {d}-bit displacement",
            .{ target, target_value, width_bits },
        ),
        error.SignedFixupOutOfRange => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' (0x{x}) does not fit the signed {d}-bit field",
            .{ target, target_value, width_bits },
        ),
        error.UnsignedFixupOutOfRange => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' (0x{x}) does not fit the unsigned {d}-bit field",
            .{ target, target_value, width_bits },
        ),
        error.WrapFixupOutOfRange => std.fmt.allocPrint(
            allocator,
            "fixup target '{s}' (0x{x}) does not fit the signed-or-unsigned {d}-bit field under wrap policy",
            .{ target, target_value, width_bits },
        ),
    };
}

test "fixup patch diagnostics preserve target width and range policy" {
    const Case = struct {
        patch_error: AssemblyError,
        width_bits: u16,
        value: u64,
        expected: []const u8,
    };
    const cases = [_]Case{
        .{
            .patch_error = error.InvalidFixupWidth,
            .width_bits = 12,
            .value = 0,
            .expected = "fixup target 'target + 4' uses unsupported 12-bit field width; supported widths are 8, 16, 32, and 64 bits",
        },
        .{
            .patch_error = error.FixupPatchOutOfBounds,
            .width_bits = 32,
            .value = 0,
            .expected = "fixup target 'target + 4' writes a 32-bit field outside the output image",
        },
        .{
            .patch_error = error.FixupAddressOverflow,
            .width_bits = 64,
            .value = 0,
            .expected = "fixup target 'target + 4' overflows address arithmetic for its 64-bit field",
        },
        .{
            .patch_error = error.RelativeFixupOutOfRange,
            .width_bits = 8,
            .value = 0x1234,
            .expected = "PC-relative fixup target 'target + 4' (0x1234) does not fit the signed 8-bit displacement",
        },
        .{
            .patch_error = error.SignedFixupOutOfRange,
            .width_bits = 8,
            .value = 0x80,
            .expected = "fixup target 'target + 4' (0x80) does not fit the signed 8-bit field",
        },
        .{
            .patch_error = error.UnsignedFixupOutOfRange,
            .width_bits = 8,
            .value = 0x100,
            .expected = "fixup target 'target + 4' (0x100) does not fit the unsigned 8-bit field",
        },
        .{
            .patch_error = error.WrapFixupOutOfRange,
            .width_bits = 32,
            .value = 0x1_0000_0000,
            .expected = "fixup target 'target + 4' (0x100000000) does not fit the signed-or-unsigned 32-bit field under wrap policy",
        },
    };

    for (cases) |case| {
        const message = try fixupPatchDiagnostic(
            std.testing.allocator,
            "target + 4",
            case.width_bits,
            case.value,
            case.patch_error,
        );
        defer std.testing.allocator.free(message);
        try std.testing.expectEqualStrings(case.expected, message);
    }
}

fn writeSignedLittleEndian(out: []u8, value: i64) void {
    const raw: u64 = @bitCast(value);
    for (out, 0..) |*byte, index| {
        const shift: u6 = @intCast(index * 8);
        byte.* = @intCast((raw >> shift) & 0xff);
    }
}

fn sizeToUsize(value: u64) !usize {
    if (value > std.math.maxInt(usize)) return error.FileTooLarge;
    return @intCast(value);
}

test "flat assembly reports product stages in order" {
    const TestObserver = struct {
        begun: [6]?Stage = @splat(null),
        ended: [6]?Stage = @splat(null),
        begun_len: usize = 0,
        ended_len: usize = 0,

        fn begin(context: *anyopaque, stage: Stage) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.begun_len >= self.begun.len) return;
            self.begun[self.begun_len] = stage;
            self.begun_len += 1;
        }

        fn end(context: *anyopaque, stage: Stage) void {
            const self: *@This() = @ptrCast(@alignCast(context));
            if (self.ended_len >= self.ended.len) return;
            self.ended[self.ended_len] = stage;
            self.ended_len += 1;
        }
    };

    var module = try frontend.Module.init(std.testing.allocator, frontend.Target.default);
    defer module.deinit();
    var observed: TestObserver = .{};
    var result = try assembleFlat(std.testing.allocator, &module, .{
        .context = @ptrCast(&observed),
        .begin = TestObserver.begin,
        .end = TestObserver.end,
    });
    defer result.deinit(std.testing.allocator);

    const expected = [_]Stage{ .encode, .fixup_resolve, .layout, .materialize, .patch, .defer_finalizers };
    try std.testing.expectEqual(expected.len, observed.begun_len);
    try std.testing.expectEqual(expected.len, observed.ended_len);
    for (expected, 0..) |stage, index| {
        try std.testing.expectEqual(stage, observed.begun[index] orelse return error.MissingObservedStage);
        try std.testing.expectEqual(stage, observed.ended[index] orelse return error.MissingObservedStage);
    }
}

fn exerciseDeferredOperandEvaluation(allocator: Allocator) !void {
    var module = try frontend.lowerSource(allocator,
        \\let saved: list = list.new()
        \\macro save(value) {
        \\    list.push_mut(saved, value)
        \\}
        \\fn indirect() -> u64 {
        \\    return operand.eval(list.get(saved, 0));
        \\}
        \\fn indirect_stamp() -> string {
        \\    return operand.eval(list.get(saved, 1));
        \\}
        \\let addend: u64 = 4
        \\save label_addr(future) + addend
        \\save sym.unique("evaluation")
        \\addend = 99
        \\emit.u32(0)
        \\emit.u32(0)
        \\future:
        \\emit.u8(9)
        \\defer {
        \\    let addend: u64 = 100
        \\    store.u32(0, operand.eval(list.get(saved, 0)))
        \\    assert(addend == 100)
        \\    addend = addend + 1
        \\    assert(addend == 101)
        \\    assert(operand.eval(list.get(saved, 1)) == "evaluation__0")
        \\}
        \\defer {
        \\    store.u32(4, indirect())
        \\    assert(indirect_stamp() == "evaluation__1")
        \\}
    , .{});
    defer module.deinit();
    var result = try assembleFlat(allocator, &module, null);
    defer result.deinit(allocator);
    try std.testing.expectEqualSlices(u8, &.{ 12, 0, 0, 0, 12, 0, 0, 0, 9 }, result.bytes);
}

test "deferred operands preserve captures and scopes through every allocation failure" {
    var no_resize = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredOperandEvaluation, .{});
}

fn exerciseDeferredOperandError(allocator: Allocator, expression: []const u8, expected: anyerror) !void {
    const text = try std.fmt.allocPrint(allocator,
        \\let saved: list = list.new()
        \\macro save(value) {{
        \\    list.push_mut(saved, value)
        \\}}
        \\fn forbidden() -> u64 {{
        \\    emit.u8(1)
        \\    return 0;
        \\}}
        \\save {s}
        \\emit.u32(0)
        \\defer {{
        \\    const missing: u64 = 7
        \\    store.u32(0, operand.eval(list.get(saved, 0)))
        \\}}
    , .{expression});
    defer allocator.free(text);
    var module = try frontend.lowerSource(allocator, text, .{});
    defer module.deinit();
    const fragment_count = module.fragments.items.items.len;
    if (assembleFlat(allocator, &module, null)) |output| {
        var result = output;
        defer result.deinit(allocator);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        // A failure inside a finalizer is now reported where it happened, so the
        // error arrives as diagnostics; the category name stays in the message.
        error.FrontendDiagnostics => try std.testing.expect(diagnosticsMention(&module, @errorName(expected))),
        else => try std.testing.expectEqual(expected, err),
    }
    try std.testing.expectEqual(fragment_count, module.fragments.items.items.len);
}

test "sparse output warns instead of filling gigabytes quietly" {
    var module = try frontend.Module.init(std.testing.allocator, frontend.target.Target.default);
    defer module.deinit();

    // A single byte placed four gigabytes into the file: the one-digit file
    // offset slip this warning exists for.
    const far = [_]frontend.output.ImageRegion{.{
        .section = module.default_section,
        .origin = 0x1000,
        .file_offset = 0x1_0000_0000,
        .logical_size = 1,
        .file_size = 1,
    }};
    try warnOnSparseOutput(&module, &far, 0x1_0000_0001);
    try std.testing.expect(diagnosticsMention(&module, "bytes are holes"));

    // A region that accounts for the whole file is not sparse, and a hole below
    // the threshold is ordinary padding.
    const tight = [_]frontend.output.ImageRegion{.{
        .section = module.default_section,
        .origin = 0x1000,
        .file_offset = 0,
        .logical_size = 16,
        .file_size = 16,
    }};
    const before = module.diagnostics.items.items.len;
    try warnOnSparseOutput(&module, &tight, 16);
    try warnOnSparseOutput(&module, &tight, 16 + (1 << 19));
    try std.testing.expectEqual(before, module.diagnostics.items.items.len);
}

fn diagnosticsMention(module: *const frontend.Module, needle: []const u8) bool {
    for (module.diagnostics.items.items) |entry| {
        if (std.mem.indexOf(u8, entry.message, needle) != null) return true;
    }
    return false;
}

test "deferred operand failures preserve errors and release captured state" {
    var no_resize = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredOperandError, .{ "missing", error.UndefinedSymbol });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredOperandError, .{ "1 / 0", error.DivisionByZero });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredOperandError, .{ "forbidden()", error.InvalidOperand });
}

fn exerciseDeferredCompositeCapture(allocator: Allocator) !void {
    var module = try frontend.lowerSource(allocator,
        \\packed struct Pair {
        \\    value: u32
        \\}
        \\fn patch(arg: operand, values: list) {
        \\    const pair: Pair = Pair { value: 5 }
        \\    const kind: type = u32
        \\    let config: map = map.new()
        \\    map.set_mut(config, "value", values)
        \\    defer {
        \\        const values: list = values
        \\        const config: map = config
        \\        const arg: operand = arg
        \\        assert(pair.value == 5)
        \\        assert(kind == u32)
        \\        store.u32(here(), operand.eval(arg) + list.get(values, 0))
        \\        assert(list.get(map.get(config, "value"), 0) == 3)
        \\        if true {
        \\            const values: list = list.of(99)
        \\            assert(list.get(values, 0) == 99)
        \\        }
        \\        assert(list.get(values, 0) == 3)
        \\    }
        \\    map.set_mut(config, "value", list.of(100))
        \\    emit.u32(0)
        \\}
        \\macro capture(arg) {
        \\    patch(arg, list.of(3))
        \\}
        \\const addend: u64 = 1
        \\capture label_addr(end) + addend
        \\capture 7
        \\end:
        \\emit.u8(9)
    , .{});
    defer module.deinit();
    for (0..2) |_| {
        var result = try assembleFlat(allocator, &module, null);
        defer result.deinit(allocator);
        try std.testing.expectEqualSlices(u8, &.{ 12, 0, 0, 0, 10, 0, 0, 0, 9 }, result.bytes);
    }
}

test "deferred composite snapshots retain ownership and survive repeated finalization" {
    var no_resize = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredCompositeCapture, .{});
}

fn exerciseDeferredCapturedError(allocator: Allocator) !void {
    var module = try frontend.lowerSource(allocator,
        \\macro capture(arg) {
        \\    const values: list = list.of(arg)
        \\    defer {
        \\        store.u32(here(), operand.eval(list.get(values, 0)))
        \\    }
        \\    emit.u32(0)
        \\}
        \\capture missing
    , .{});
    defer module.deinit();
    if (assembleFlat(allocator, &module, null)) |output| {
        var result = output;
        defer result.deinit(allocator);
        return error.TestExpectedError;
    } else |err| switch (err) {
        error.OutOfMemory => return err,
        else => try std.testing.expectEqual(error.FrontendDiagnostics, err),
    }
    try std.testing.expect(diagnosticsMention(&module, "UndefinedSymbol"));
}

test "deferred composite failures clean up snapshots and preserve macro diagnostics" {
    var no_resize = std.testing.FailingAllocator.init(std.testing.allocator, .{ .resize_fail_index = 0 });
    try std.testing.checkAllAllocationFailures(no_resize.allocator(), exerciseDeferredCapturedError, .{});
}

test "overlapping output regions warn about the file bytes they share" {
    var module = try frontend.lowerSource(std.testing.allocator,
        \\region.begin("first", 0x1000, 0)
        \\emit.bytes(b"AAAAAAAA")
        \\region.begin("second", 0x2000, 4)
        \\emit.bytes(b"BBBBBBBB")
        \\
    , .{});
    defer module.deinit();

    var result = try assembleFlat(std.testing.allocator, &module, null);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 12), result.bytes.len);
    try std.testing.expect(diagnosticsMention(&module, "shared bytes are written twice"));
}

test "adjacent output regions do not warn" {
    var module = try frontend.lowerSource(std.testing.allocator,
        \\region.begin("first", 0x1000, 0)
        \\emit.bytes(b"AAAA")
        \\region.begin("second", 0x2000, 4)
        \\emit.bytes(b"BBBB")
        \\
    , .{});
    defer module.deinit();

    var result = try assembleFlat(std.testing.allocator, &module, null);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 8), result.bytes.len);
    try std.testing.expect(!diagnosticsMention(&module, "shared bytes are written twice"));
}
