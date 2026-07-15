const std = @import("std");

const frontend = @import("frontend/root.zig");

const Allocator = std.mem.Allocator;

const AssemblyError = error{
    RelativeFixupOutOfRange,
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
        try frontend.lower.pushMetaScope(state.lower_context, state.allocator);
        defer frontend.lower.popMetaScope(state.lower_context, state.allocator);
        try runDeferredStatements(&state, block.body);
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
        try runDeferredStatement(state, statement);
    }
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
        .void, .integer, .float32, .float64, .boolean, .type, .@"struct", .list, .map => return error.InvalidApiArgument,
    };
    if (target.explicit_section)
        try state.image.storeBytesInSection(target.section, target.address, bytes)
    else
        try state.image.storeBytes(target.address, bytes);
}

fn runDeferredStoreInteger(
    state: *FinalizerState,
    call: frontend.ast.ApiCallStatement,
    byte_count: u8,
) !void {
    if (call.args.len != 2) return error.InvalidApiArity;
    const target = try deferredOutputTarget(state, call, 0);
    const value = try deferredIntegerArg(state, call, 1);
    if (target.explicit_section)
        try state.image.storeIntegerInSection(target.section, target.address, value, byte_count)
    else
        try state.image.storeInteger(target.address, value, byte_count);
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
        .@"struct", .list, .map => error.InvalidApiArgument,
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
    module: *const frontend.Module,
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
                const image_region = imageRegionForSection(image_regions, section_id) orelse return error.InvalidSection;
                const fragment_layout = fragmentLayout(section_layout, stored_fixup.fragment) orelse return error.InvalidFragment;
                try patchOneFixup(bytes, section_layout.*, image_region, fragment_layout, stored_fixup, resolved.value);
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
    module: *const frontend.Module,
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
    const image_region = imageRegionForSection(image_regions, section_id) orelse return error.InvalidSection;
    const fragment_layout = fragmentLayout(section_layout, fragment_id) orelse return error.InvalidFragment;
    const instruction_address = std.math.add(u64, section_layout.origin, fragment_layout.offset) catch return error.OffsetOverflow;
    var encoded = try frontend.encodeResolvedRiscvInstruction(
        instruction,
        module.target,
        instruction_address,
        resolution_storage[0..resolution_count],
    );
    const encoded_bytes = encoded.asSlice();
    if (encoded_bytes.len != fragment_layout.file_size or encoded_bytes.len != instruction.current_size) {
        return error.InvalidFixupTarget;
    }
    const patch_end_relative = std.math.add(u64, fragment_layout.offset, encoded_bytes.len) catch return error.OffsetOverflow;
    if (patch_end_relative > image_region.file_size) return error.InvalidFixupTarget;

    const patch_offset = std.math.add(u64, image_region.file_offset, fragment_layout.offset) catch return error.OffsetOverflow;
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

fn fragmentLayout(section_layout: *const frontend.SectionLayout, fragment_id: frontend.FragmentId) ?frontend.FragmentLayout {
    for (section_layout.fragments) |entry| {
        if (entry.fragment.index == fragment_id.index) return entry;
    }
    return null;
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

fn patchOneFixup(
    bytes: []u8,
    section_layout: frontend.SectionLayout,
    image_region: frontend.output.ImageRegion,
    fragment_layout: frontend.FragmentLayout,
    stored_fixup: frontend.Fixup,
    target_value: u64,
) (AssemblyError || anyerror)!void {
    const width_bytes = fixupWidthBytes(stored_fixup.width_bits) catch return error.InvalidFixupTarget;
    const section_relative_patch_offset = std.math.add(u64, fragment_layout.offset, stored_fixup.offset) catch return error.OffsetOverflow;
    const patch_end_relative = std.math.add(u64, section_relative_patch_offset, width_bytes) catch return error.OffsetOverflow;
    if (patch_end_relative > image_region.file_size) return error.InvalidFixupTarget;
    const patch_offset = std.math.add(u64, image_region.file_offset, section_relative_patch_offset) catch return error.OffsetOverflow;
    const patch_start = try sizeToUsize(patch_offset);
    const patch_end = std.math.add(usize, patch_start, width_bytes) catch return error.OffsetOverflow;
    if (patch_end > bytes.len) return error.InvalidFixupTarget;

    const value = switch (stored_fixup.kind) {
        .absolute => try absolutePatchValue(target_value, stored_fixup.width_bits),
        .pc_relative => value: {
            const next_ip_offset = std.math.add(u64, section_relative_patch_offset, width_bytes) catch return error.OffsetOverflow;
            const next_ip = std.math.add(u64, section_layout.origin, next_ip_offset) catch return error.OffsetOverflow;
            break :value try relativePatchValue(target_value, next_ip, stored_fixup.width_bits);
        },
    };
    writeSignedLittleEndian(bytes[patch_start..patch_end], value);
}

fn fixupWidthBytes(width_bits: u16) !usize {
    if (width_bits == 0 or width_bits % 8 != 0) return error.InvalidFixupTarget;
    const width_bytes = width_bits / 8;
    if (width_bytes != 1 and width_bytes != 2 and width_bytes != 4 and width_bytes != 8) return error.InvalidFixupTarget;
    return @intCast(width_bytes);
}

fn absolutePatchValue(value: u64, width_bits: u16) !i64 {
    if (width_bits < 64) {
        const max_value = (@as(u64, 1) << @intCast(width_bits)) - 1;
        if (value > max_value) return error.InvalidFixupTarget;
    }
    if (value > std.math.maxInt(i64)) return error.InvalidFixupTarget;
    return @intCast(value);
}

fn relativePatchValue(target_value: u64, next_ip: u64, width_bits: u16) !i64 {
    const target_i128: i128 = @intCast(target_value);
    const next_ip_i128: i128 = @intCast(next_ip);
    const value = target_i128 - next_ip_i128;
    switch (width_bits) {
        8 => if (value < std.math.minInt(i8) or value > std.math.maxInt(i8)) return error.RelativeFixupOutOfRange,
        16 => if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) return error.RelativeFixupOutOfRange,
        32 => if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.RelativeFixupOutOfRange,
        64 => if (value < std.math.minInt(i64) or value > std.math.maxInt(i64)) return error.RelativeFixupOutOfRange,
        else => return error.InvalidFixupTarget,
    }
    return @intCast(value);
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
