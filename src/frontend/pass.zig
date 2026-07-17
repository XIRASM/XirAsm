const std = @import("std");

const backend_adapter = @import("backend_adapter.zig");
const diagnostic = @import("diagnostic.zig");
const fixup = @import("fixup.zig");
const fragment = @import("fragment.zig");
const layout = @import("layout.zig");
const module_mod = @import("module.zig");

const Allocator = std.mem.Allocator;

pub const PassError = Allocator.Error || error{
    FrontendDiagnostics,
    FragmentTooLarge,
    InstructionTooLarge,
    InvalidInstructionText,
    InvalidFragment,
    InvalidFixupTarget,
    InvalidModeBits,
    InvalidSection,
    OffsetOverflow,
    TooManyFixups,
};

pub const FixupResolveState = union(enum) {
    resolved: fixup.ResolvedFixup,
    pending: fixup.FixupId,
};

pub const FixupPassResult = struct {
    items: []FixupResolveState,
    resolved_count: usize,
    pending_count: usize,

    pub fn deinit(self: *FixupPassResult, allocator: Allocator) void {
        allocator.free(self.items);
        self.* = undefined;
    }
};

pub const EncodeInstructionsResult = struct {
    encoded_count: usize,
    changed_count: usize,
};

pub fn encodeInstructionFragments(
    allocator: Allocator,
    module: *module_mod.Module,
) PassError!EncodeInstructionsResult {
    if (try validateSpirvModuleFragments(allocator, module)) |first_instruction| {
        return encodeSpirvModuleFragments(allocator, module, first_instruction);
    }

    var encoded_count: usize = 0;
    var changed_count: usize = 0;

    for (module.fragments.items.items, 0..) |stored_fragment, index| {
        switch (stored_fragment) {
            .isa_instruction => |instruction| {
                const id: fragment.FragmentId = .{ .index = @intCast(index) };
                var facts = backend_adapter.encodeInstruction(allocator, instruction, module.target) catch |err| switch (err) {
                    error.AmbiguousMemorySize => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86 memory operand size is ambiguous; add byte, word, dword, or qword",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.CmpR64ImmediateOutOfRange => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86-64 cmp r64 accepts only imm8 or sign-extended imm32 immediates; load wider constants into a register first",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.HighRegisterNotAllowed => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86 high 8-bit registers cannot be encoded with a REX prefix or extended register",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.ImpossibleAddressSize => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86 addressing registers do not match the active address size",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.InvalidMemoryScale => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86 memory scale must be 1, 2, 4, or 8",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.InvalidRspIndexRegister => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "x86 SIB addressing cannot use rsp/esp/sp as an index register",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.SymbolicSubByteImmediate => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "symbolic sub-byte immediate is unsupported; use a compile-time constant",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedOperandSyntax => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "unsupported x86 operand syntax",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedPrefixes => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "unsupported x86 prefix combination for this instruction",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedInstructionTarget => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "instruction text emission is not supported for this target ISA",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedX86Instruction => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "unsupported x86 instruction form",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedRiscvInstruction => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "unsupported RISC-V instruction form",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.BackendFixupCountMismatch => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "backend fixup count did not match frontend symbolic operands",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.UnsupportedBackendFixupKind => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "backend produced a fixup kind this frontend cannot resolve",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.BackendFixupOffsetOverflow => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "backend fixup offset or addend overflowed the frontend range",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.InvalidBackendFixupWidth => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "backend produced an invalid fixup width",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.BackendOutputMaterializationFailed => {
                        try module.diagnostics.add(
                            allocator,
                            diagnostic.Severity.err,
                            instruction.span,
                            "backend could not materialize instruction output",
                        );
                        return error.FrontendDiagnostics;
                    },
                    error.OutOfMemory => return error.OutOfMemory,
                    error.InstructionTooLarge => return error.InstructionTooLarge,
                    error.InvalidInstructionText => return error.InvalidInstructionText,
                    error.InvalidModeBits => return error.InvalidModeBits,
                };
                defer facts.deinit(allocator);

                if (instructionFactsChanged(instruction, facts)) changed_count += 1;
                try module.fragments.updateIsaInstructionFacts(
                    allocator,
                    id,
                    facts.bytes,
                    facts.min_size,
                    facts.max_size,
                    facts.current_size,
                    facts.relaxable,
                );
                try recordInstructionFixups(module, id, facts.fixups);
                encoded_count += 1;
            },
            else => {},
        }
    }

    try syncAnchoredLabelOffsets(allocator, module);
    return .{
        .encoded_count = encoded_count,
        .changed_count = changed_count,
    };
}

fn validateSpirvModuleFragments(
    allocator: Allocator,
    module: *module_mod.Module,
) PassError!?fragment.IsaInstructionFragment {
    var first_instruction: ?fragment.IsaInstructionFragment = null;
    for (module.fragments.items.items) |stored_fragment| {
        const instruction = switch (stored_fragment) {
            .isa_instruction => |active| active,
            else => continue,
        };
        if (instruction.target.isa() != .spirv) continue;
        if (first_instruction) |first| {
            const first_version = switch (first.target) {
                .spirv => |config| config.version,
                .x86, .riscv => return error.InvalidModeBits,
            };
            const active_version = switch (instruction.target) {
                .spirv => |config| config.version,
                .x86, .riscv => return error.InvalidModeBits,
            };
            if (instruction.section.index != first.section.index or active_version != first_version) {
                try addSpirvDiagnostic(
                    allocator,
                    module,
                    instruction.span,
                    "all SPIR-V instructions in one output must use the same section and module version",
                );
                return error.FrontendDiagnostics;
            }
        } else {
            first_instruction = instruction;
        }
    }

    if (first_instruction == null) return null;
    for (module.fragments.items.items) |stored_fragment| {
        const incompatible_span = switch (stored_fragment) {
            .isa_instruction => |instruction| if (instruction.target.isa() == .spirv) null else instruction.span,
            .bytes => |bytes| if (bytes.data.len == 0) null else bytes.span,
            .reserve => |reserve| if (reserve.size == 0) null else reserve.span,
            .alignment => |alignment| alignment.span,
        };
        if (incompatible_span) |span| {
            try addSpirvDiagnostic(
                allocator,
                module,
                span,
                "SPIR-V module instructions cannot be mixed with other ISA, data, reserve, or alignment fragments",
            );
            return error.FrontendDiagnostics;
        }
    }
    return first_instruction;
}

fn encodeSpirvModuleFragments(
    allocator: Allocator,
    module: *module_mod.Module,
    first_instruction: fragment.IsaInstructionFragment,
) PassError!EncodeInstructionsResult {
    var source_text: std.ArrayList(u8) = .empty;
    defer source_text.deinit(allocator);

    var encoded_count: usize = 0;
    for (module.fragments.items.items) |stored_fragment| {
        const instruction = switch (stored_fragment) {
            .isa_instruction => |active| active,
            else => continue,
        };
        if (instruction.target.isa() != .spirv) continue;
        if (source_text.items.len != 0) try source_text.append(allocator, '\n');
        try source_text.appendSlice(allocator, instruction.text);
        encoded_count += 1;
    }

    var facts = backend_adapter.encodeSpirvSource(
        allocator,
        source_text.items,
        first_instruction.target,
    ) catch |err| switch (err) {
        error.UnsupportedSpirvInstruction => {
            try addSpirvDiagnostic(
                allocator,
                module,
                first_instruction.span,
                "unsupported SPIR-V instruction or operand syntax",
            );
            return error.FrontendDiagnostics;
        },
        error.InvalidSpirvVersion => {
            try addSpirvDiagnostic(
                allocator,
                module,
                first_instruction.span,
                "unsupported SPIR-V module version",
            );
            return error.FrontendDiagnostics;
        },
        error.InstructionTooLarge => return error.InstructionTooLarge,
        error.OutOfMemory => return error.OutOfMemory,
    };
    defer facts.deinit(allocator);

    var changed_count: usize = 0;
    var wrote_module = false;
    for (module.fragments.items.items, 0..) |stored_fragment, index| {
        const instruction = switch (stored_fragment) {
            .isa_instruction => |active| active,
            else => continue,
        };
        if (instruction.target.isa() != .spirv) continue;
        const id: fragment.FragmentId = .{ .index = @intCast(index) };
        if (!wrote_module) {
            if (instructionFactsChanged(instruction, facts)) changed_count += 1;
            try module.fragments.updateIsaInstructionFacts(
                allocator,
                id,
                facts.bytes,
                facts.min_size,
                facts.max_size,
                facts.current_size,
                false,
            );
            wrote_module = true;
            continue;
        }

        if (instruction.min_size != 0 or
            instruction.max_size != 0 or
            instruction.current_size != 0 or
            instruction.relaxable or
            instruction.encoded_bytes.len != 0)
        {
            changed_count += 1;
        }
        try module.fragments.updateIsaInstructionFacts(
            allocator,
            id,
            &.{},
            0,
            0,
            0,
            false,
        );
    }

    try syncAnchoredLabelOffsets(allocator, module);
    return .{
        .encoded_count = encoded_count,
        .changed_count = changed_count,
    };
}

fn addSpirvDiagnostic(
    allocator: Allocator,
    module: *module_mod.Module,
    span: @import("source.zig").SourceSpan,
    message: []const u8,
) Allocator.Error!void {
    try module.diagnostics.add(
        allocator,
        diagnostic.Severity.err,
        span,
        message,
    );
}

pub fn resolveFixups(
    allocator: Allocator,
    module: *module_mod.Module,
) PassError!FixupPassResult {
    var module_layout = try layout.layoutModule(allocator, module);
    defer module_layout.deinit(allocator);

    var items = try allocator.alloc(FixupResolveState, module.fixups.items.items.len);
    errdefer allocator.free(items);

    var resolved_count: usize = 0;
    var pending_count: usize = 0;
    for (module.fixups.items.items, 0..) |stored_fixup, index| {
        const id: fixup.FixupId = .{ .index = @intCast(index) };
        const active = try activeContextForFixup(module, &module_layout, stored_fixup);
        if (module.fixups.resolveOneWithContext(allocator, active, id)) |resolved| {
            items[index] = .{ .resolved = resolved };
            resolved_count += 1;
        } else |err| switch (err) {
            error.UndefinedSymbol,
            error.InvalidOperand,
            error.InvalidApiArgument,
            error.InvalidApiInteger,
            error.InvalidIntegerBits,
            error.InvalidType,
            error.UnknownTypeName,
            error.UnknownField,
            error.FileNotAvailable,
            error.MissingEvaluationContext,
            error.MissingStructFieldValue,
            error.FragmentTooLarge,
            error.TypeMismatch,
            => {
                items[index] = .{ .pending = id };
                pending_count += 1;
            },
            error.OutOfMemory => return error.OutOfMemory,
            error.InvalidFixupTarget => return error.InvalidFixupTarget,
            error.InvalidFragment => return error.InvalidFragment,
            error.InvalidSection => return error.InvalidSection,
            error.OffsetOverflow => return error.OffsetOverflow,
            error.DivisionByZero,
            error.InvalidArgument,
            error.InvalidCharacter,
            error.InvalidNumber,
            error.InvalidToken,
            error.UnexpectedEof,
            => {
                items[index] = .{ .pending = id };
                pending_count += 1;
            },
        }
    }

    return .{
        .items = items,
        .resolved_count = resolved_count,
        .pending_count = pending_count,
    };
}

fn syncAnchoredLabelOffsets(allocator: Allocator, module: *module_mod.Module) PassError!void {
    var module_layout = try layout.layoutModule(allocator, module);
    defer module_layout.deinit(allocator);

    for (module.symbols.items.items) |*stored_symbol| {
        switch (stored_symbol.binding) {
            .label => |label| {
                const fragment_position = label.fragment_position orelse continue;
                stored_symbol.binding = .{ .label = .{
                    .section = label.section,
                    .offset = try labelOffsetForFragmentPosition(module, &module_layout, label.section, fragment_position),
                    .fragment_position = label.fragment_position,
                } };
            },
            .unknown, .absolute, .value => {},
        }
    }
}

fn labelOffsetForFragmentPosition(
    module: *const module_mod.Module,
    module_layout: *const layout.ModuleLayout,
    section_id: fragment.SectionId,
    fragment_position: u32,
) PassError!u64 {
    const stored_section = try module.sections.get(section_id);
    const position: usize = @intCast(fragment_position);
    if (position > stored_section.fragments.items.len) return error.InvalidFragment;

    const section_layout = module_layout.sectionLayout(section_id) orelse return error.InvalidSection;
    if (position == stored_section.fragments.items.len) return section_layout.logical_size;

    const fragment_id = stored_section.fragments.items[position];
    const entry = fragmentLayout(section_layout, fragment_id) orelse return error.InvalidFragment;
    return entry.offset;
}

fn recordInstructionFixups(
    module: *module_mod.Module,
    fragment_id: fragment.FragmentId,
    facts: []const backend_adapter.FixupFact,
) PassError!void {
    for (facts) |fact| {
        if (hasInstructionFixup(module, fragment_id, fact)) continue;
        const fixup_id = if (isSimpleSymbolFact(fact.target))
            try module.addFixup(fragment_id, fact.target, fact.kind, fact.offset, fact.width_bits, fact.span)
        else
            try module.addExpressionFixup(fragment_id, fact.target, fact.kind, fact.offset, fact.width_bits, fact.span);
        if (fixup_id.index >= module.fixups.items.items.len) return error.InvalidFixupTarget;
        try module.fixups.setValueRange(fixup_id, fact.value_range);
    }
}

fn hasInstructionFixup(
    module: *const module_mod.Module,
    fragment_id: fragment.FragmentId,
    fact: backend_adapter.FixupFact,
) bool {
    for (module.fixups.items.items) |stored| {
        if (stored.fragment.index != fragment_id.index) continue;
        if (stored.kind != fact.kind) continue;
        if (stored.offset != fact.offset) continue;
        if (stored.width_bits != fact.width_bits) continue;
        if (stored.value_range != fact.value_range) continue;
        switch (stored.target) {
            .symbol => |symbol| {
                if (isSimpleSymbolFact(fact.target) and std.mem.eql(u8, symbol, fact.target)) return true;
            },
            .expression_text => |text| {
                if (!isSimpleSymbolFact(fact.target) and std.mem.eql(u8, text, fact.target)) return true;
            },
        }
    }
    return false;
}

fn isSimpleSymbolFact(target: []const u8) bool {
    if (target.len == 0) return false;
    if (!std.ascii.isAlphabetic(target[0]) and target[0] != '_' and target[0] != '.') return false;
    for (target[1..]) |byte| {
        if (!std.ascii.isAlphanumeric(byte) and byte != '_' and byte != '.' and byte != '$') return false;
    }
    return true;
}

fn activeContextForFixup(
    module: *module_mod.Module,
    module_layout: *const layout.ModuleLayout,
    stored_fixup: fixup.Fixup,
) PassError!fixup.ResolveContext {
    const stored_fragment = try fragmentForFixup(module, stored_fixup.fragment);
    const section_id = fragmentSection(stored_fragment);
    const section_layout = module_layout.sectionLayout(section_id) orelse return error.InvalidSection;
    const fragment_layout = fragmentLayout(section_layout, stored_fixup.fragment) orelse return error.InvalidFragment;
    const active_offset = std.math.add(u64, fragment_layout.offset, stored_fixup.offset) catch return error.OffsetOverflow;
    return .{
        .module = module,
        .active_section = section_id,
        .active_offset = active_offset,
    };
}

fn fragmentForFixup(module: *const module_mod.Module, fragment_id: fragment.FragmentId) PassError!fragment.Fragment {
    if (fragment_id.index >= module.fragments.items.items.len) return error.InvalidFragment;
    return module.fragments.items.items[fragment_id.index];
}

fn fragmentSection(stored_fragment: fragment.Fragment) fragment.SectionId {
    return switch (stored_fragment) {
        .bytes => |payload| payload.section,
        .reserve => |payload| payload.section,
        .alignment => |payload| payload.section,
        .isa_instruction => |payload| payload.section,
    };
}

fn fragmentLayout(
    section_layout: *const layout.SectionLayout,
    fragment_id: fragment.FragmentId,
) ?layout.FragmentLayout {
    for (section_layout.fragments) |entry| {
        if (entry.fragment.index == fragment_id.index) return entry;
    }
    return null;
}

fn instructionFactsChanged(
    instruction: fragment.IsaInstructionFragment,
    facts: backend_adapter.InstructionFacts,
) bool {
    return instruction.min_size != facts.min_size or
        instruction.max_size != facts.max_size or
        instruction.current_size != facts.current_size or
        instruction.relaxable != facts.relaxable or
        !std.mem.eql(u8, instruction.encoded_bytes, facts.bytes);
}

test "pass resolves fixups and leaves forward misses pending" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    _ = try module.defineLabel("target", module.default_section, 8, @import("source.zig").unknown_span);
    const resolved_fragment = try module.emitBytes(module.default_section, &.{0xaa}, @import("source.zig").unknown_span);
    const pending_fragment = try module.emitBytes(module.default_section, &.{0xbb}, @import("source.zig").unknown_span);
    _ = try module.addExpressionFixup(
        resolved_fragment,
        "target + 4",
        .absolute,
        0,
        64,
        @import("source.zig").unknown_span,
    );
    _ = try module.addFixup(
        pending_fragment,
        "missing",
        .absolute,
        0,
        64,
        @import("source.zig").unknown_span,
    );

    var result = try resolveFixups(std.testing.allocator, &module);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.resolved_count);
    try std.testing.expectEqual(@as(usize, 1), result.pending_count);
    switch (result.items[0]) {
        .resolved => |resolved| try std.testing.expectEqual(@as(u64, 12), resolved.value),
        else => return error.UnexpectedResolveState,
    }
    switch (result.items[1]) {
        .pending => |pending| try std.testing.expectEqual(@as(u32, 1), pending.index),
        else => return error.UnexpectedResolveState,
    }
}

test "pass encodes x86 instruction fragments through backend adapter" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    const id = try module.appendIsaInstruction(
        module.default_section,
        @import("target.zig").Target.default,
        "ret",
        @import("source.zig").unknown_span,
    );

    const result = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), result.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), result.changed_count);

    switch (module.fragments.items.items[id.index]) {
        .isa_instruction => |instruction| {
            try std.testing.expectEqualSlices(u8, &.{0xC3}, instruction.encoded_bytes);
            try std.testing.expectEqual(@as(u32, 1), instruction.current_size);
            try std.testing.expect(!instruction.relaxable);
        },
        else => return error.UnexpectedFragment,
    }
}

test "pass encodes a complete spirv module without pass drift" {
    const spirv_target = @import("target.zig").Target.spv();
    var module = try module_mod.Module.init(std.testing.allocator, spirv_target);
    defer module.deinit();

    const capability = try module.appendIsaInstruction(
        module.default_section,
        spirv_target,
        "OpCapability Shader",
        @import("source.zig").unknown_span,
    );
    const memory_model = try module.appendIsaInstruction(
        module.default_section,
        spirv_target,
        "OpMemoryModel Logical GLSL450",
        @import("source.zig").unknown_span,
    );
    const void_type = try module.appendIsaInstruction(
        module.default_section,
        spirv_target,
        "%1 = OpTypeVoid",
        @import("source.zig").unknown_span,
    );

    const first = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 3), first.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), first.changed_count);

    const capability_fragment = module.fragments.items.items[capability.index].isa_instruction;
    try std.testing.expectEqual(@as(usize, 12 * @sizeOf(u32)), capability_fragment.encoded_bytes.len);
    try std.testing.expectEqual(@as(u32, 0x07230203), std.mem.readInt(u32, capability_fragment.encoded_bytes[0..4], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, capability_fragment.encoded_bytes[12..16], .little));
    try std.testing.expectEqual(@as(usize, 0), module.fragments.items.items[memory_model.index].isa_instruction.encoded_bytes.len);
    try std.testing.expectEqual(@as(usize, 0), module.fragments.items.items[void_type.index].isa_instruction.encoded_bytes.len);

    const second = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 3), second.encoded_count);
    try std.testing.expectEqual(@as(usize, 0), second.changed_count);
}

test "pass rejects mixed spirv and raw data fragments" {
    const spirv_target = @import("target.zig").Target.spv();
    var module = try module_mod.Module.init(std.testing.allocator, spirv_target);
    defer module.deinit();

    _ = try module.appendIsaInstruction(
        module.default_section,
        spirv_target,
        "OpCapability Shader",
        @import("source.zig").unknown_span,
    );
    _ = try module.emitBytes(module.default_section, &.{0xaa}, @import("source.zig").unknown_span);

    try std.testing.expectError(
        error.FrontendDiagnostics,
        encodeInstructionFragments(std.testing.allocator, &module),
    );
    try std.testing.expectEqual(@as(usize, 1), module.diagnostics.items.items.len);
}

test "pass encoded size drives later layout offsets" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    _ = try module.appendIsaInstruction(
        module.default_section,
        @import("target.zig").Target.default,
        "ret",
        @import("source.zig").unknown_span,
    );
    const bytes_id = try module.emitBytes(module.default_section, &.{0xaa}, @import("source.zig").unknown_span);

    _ = try encodeInstructionFragments(std.testing.allocator, &module);

    var result = try layout.layoutModule(std.testing.allocator, &module);
    defer result.deinit(std.testing.allocator);

    const text = result.sectionLayout(module.default_section) orelse return error.MissingSectionLayout;
    try std.testing.expectEqual(@as(usize, 2), text.fragments.len);
    try std.testing.expectEqual(@as(u64, 0), text.fragments[0].offset);
    try std.testing.expectEqual(@as(u64, 1), text.fragments[1].offset);
    try std.testing.expectEqual(bytes_id.index, text.fragments[1].fragment.index);
}

test "pass marks lowered symbolic x86 jump relaxable" {
    var module = try @import("lower.zig").lowerSource(
        std.testing.allocator,
        \\start:
        \\    jmp start
        \\
    ,
        .{ .target = @import("target.zig").Target.default },
    );
    defer module.deinit();

    const result = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), result.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), module.fixups.items.items.len);

    switch (module.fragments.items.items[0]) {
        .isa_instruction => |instruction| {
            try std.testing.expect(instruction.current_size > 0);
            try std.testing.expect(instruction.relaxable);
        },
        else => return error.UnexpectedFragment,
    }

    var fixup_result = try resolveFixups(std.testing.allocator, &module);
    defer fixup_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), fixup_result.resolved_count);
    try std.testing.expectEqual(@as(usize, 0), fixup_result.pending_count);
    switch (fixup_result.items[0]) {
        .resolved => |resolved| try std.testing.expectEqual(@as(u64, 0), resolved.value),
        else => return error.UnexpectedResolveState,
    }
}

test "pass keeps instruction fixup recording idempotent" {
    var module = try @import("lower.zig").lowerSource(
        std.testing.allocator,
        \\start:
        \\    jmp start
        \\
    ,
        .{ .target = @import("target.zig").Target.default },
    );
    defer module.deinit();

    const first = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), first.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), module.fixups.items.items.len);

    const second = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), second.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), module.fixups.items.items.len);
}

test "pass keeps symbolic immediates in frontend fixup resolution" {
    var module = try @import("lower.zig").lowerSource(
        std.testing.allocator,
        \\origin(0x1000);
        \\target:
        \\    mov rax, target + 4
        \\
    ,
        .{ .target = @import("target.zig").Target.default },
    );
    defer module.deinit();

    const encode_result = try encodeInstructionFragments(std.testing.allocator, &module);
    try std.testing.expectEqual(@as(usize, 1), encode_result.encoded_count);
    try std.testing.expectEqual(@as(usize, 1), module.fixups.items.items.len);

    switch (module.fragments.items.items[0]) {
        .isa_instruction => |instruction| {
            try std.testing.expect(instruction.current_size > 0);
            try std.testing.expectEqual(@as(usize, 1), module.fixups.items.items.len);
        },
        else => return error.UnexpectedFragment,
    }

    var fixup_result = try resolveFixups(std.testing.allocator, &module);
    defer fixup_result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), fixup_result.resolved_count);
    try std.testing.expectEqual(@as(usize, 0), fixup_result.pending_count);
    switch (fixup_result.items[0]) {
        .resolved => |resolved| try std.testing.expectEqual(@as(u64, 0x1004), resolved.value),
        else => return error.UnexpectedResolveState,
    }
}

test "pass resolves fixup expressions with layout active context" {
    var module = try module_mod.Module.init(std.testing.allocator, @import("target.zig").Target.default);
    defer module.deinit();

    try module.sections.setOrigin(module.default_section, 0x1000);
    _ = try module.emitBytes(module.default_section, &.{ 0xaa, 0xbb, 0xcc }, @import("source.zig").unknown_span);
    const fragment_id = try module.emitBytes(module.default_section, &.{0xdd}, @import("source.zig").unknown_span);
    _ = try module.addExpressionFixup(
        fragment_id,
        "here() + file_offset() - region_base()",
        .absolute,
        1,
        64,
        @import("source.zig").unknown_span,
    );

    var result = try resolveFixups(std.testing.allocator, &module);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), result.resolved_count);
    try std.testing.expectEqual(@as(usize, 0), result.pending_count);
    switch (result.items[0]) {
        .resolved => |resolved| try std.testing.expectEqual(@as(u64, 8), resolved.value),
        else => return error.UnexpectedResolveState,
    }
}
