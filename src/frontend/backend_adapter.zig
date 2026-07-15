const std = @import("std");
const backend = @import("xirasm_backend");

const fixup = @import("fixup.zig");
const fragment = @import("fragment.zig");
const isa_text = @import("isa_text.zig");
const source = @import("source.zig");
const target = @import("target.zig");

const Allocator = std.mem.Allocator;

pub const AdapterError = Allocator.Error || error{
    AmbiguousMemorySize,
    BackendFixupCountMismatch,
    BackendFixupOffsetOverflow,
    BackendOutputMaterializationFailed,
    CmpR64ImmediateOutOfRange,
    HighRegisterNotAllowed,
    ImpossibleAddressSize,
    InvalidBackendFixupWidth,
    InvalidMemoryScale,
    InstructionTooLarge,
    InvalidInstructionText,
    InvalidRspIndexRegister,
    InvalidModeBits,
    UnsupportedBackendFixupKind,
    UnsupportedInstructionTarget,
    UnsupportedRiscvInstruction,
    UnsupportedX86Instruction,
    UnsupportedOperandSyntax,
    UnsupportedPrefixes,
};

pub const SpirvAdapterError = Allocator.Error || error{
    InstructionTooLarge,
    InvalidSpirvVersion,
    UnsupportedSpirvInstruction,
};

pub const FixupFact = struct {
    target: []u8,
    kind: fixup.FixupKind,
    offset: u32,
    width_bits: u16,
    span: source.SourceSpan,

    pub fn deinit(self: *FixupFact, allocator: Allocator) void {
        allocator.free(self.target);
        self.* = undefined;
    }
};

pub const RiscvResolution = struct {
    target: []const u8,
    value: u64,
};

pub const RiscvEncodedInstruction = struct {
    bytes: [4]u8,
    len: u8,

    pub fn asSlice(self: *const RiscvEncodedInstruction) []const u8 {
        return self.bytes[0..self.len];
    }
};

pub const InstructionFacts = struct {
    bytes: []u8,
    min_size: u32,
    max_size: u32,
    current_size: u32,
    fixups: []FixupFact = &.{},
    relaxable: bool = false,

    pub fn deinit(self: *InstructionFacts, allocator: Allocator) void {
        allocator.free(self.bytes);
        for (self.fixups) |*stored_fixup| {
            stored_fixup.deinit(allocator);
        }
        allocator.free(self.fixups);
        self.* = undefined;
    }
};

const X86ResolverContext = struct {
    isa: target.Isa,
    mode_bits: u16,
    allocator: Allocator,
    span: source.SourceSpan,
    fixups: *std.ArrayList(FixupFact),
};

const RiscvUnresolvedContext = struct {
    allocator: Allocator,
    span: source.SourceSpan,
    kind: fixup.FixupKind,
    fixups: *std.ArrayList(FixupFact),
};

const RiscvResolvedContext = struct {
    instruction_address: u64,
    pc_relative: bool,
    resolutions: []const RiscvResolution,
};

pub fn encodeInstruction(
    allocator: Allocator,
    instruction: fragment.IsaInstructionFragment,
    options: target.Target,
) AdapterError!InstructionFacts {
    return switch (instruction.target.isa()) {
        .x86_64 => encodeX86Instruction(allocator, instruction, options),
        .riscv64 => encodeRiscvInstruction(allocator, instruction, options),
        .spirv => error.UnsupportedInstructionTarget,
    };
}

pub fn encodeSpirvSource(
    allocator: Allocator,
    source_text: []const u8,
    options: target.Target,
) SpirvAdapterError!InstructionFacts {
    const version = try spirvVersion(options);
    const bytes = backend.spirv.text.parseSourceToOwnedBytes(
        allocator,
        source_text,
        .{ .version = version },
    ) catch |err| return mapSpirvTextError(err);
    errdefer allocator.free(bytes);

    const current_size = sizeToU32(bytes.len) catch return error.InstructionTooLarge;
    return .{
        .bytes = bytes,
        .min_size = current_size,
        .max_size = current_size,
        .current_size = current_size,
    };
}

fn spirvVersion(options: target.Target) SpirvAdapterError!backend.spirv.module.Version {
    const raw_version = switch (options) {
        .spirv => |config| config.version,
        .x86, .riscv => return error.InvalidSpirvVersion,
    };
    return switch (raw_version) {
        0x00010000 => .v1_0,
        0x00010100 => .v1_1,
        0x00010200 => .v1_2,
        0x00010300 => .v1_3,
        0x00010400 => .v1_4,
        0x00010500 => .v1_5,
        0x00010600 => .v1_6,
        else => error.InvalidSpirvVersion,
    };
}

fn mapSpirvTextError(err: backend.spirv.text.ParseError) SpirvAdapterError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.EmptyOrComment,
        error.UnknownOpcode,
        error.UnknownOperand,
        error.ExpectedId,
        error.ExpectedEquals,
        error.ExpectedOperand,
        error.TooManyOperands,
        error.InvalidInteger,
        error.InvalidString,
        error.InstructionTooLong,
        error.InvalidHeaderBound,
        error.IdBoundOverflow,
        => error.UnsupportedSpirvInstruction,
    };
}

fn encodeX86Instruction(
    allocator: Allocator,
    instruction: fragment.IsaInstructionFragment,
    options: target.Target,
) AdapterError!InstructionFacts {
    const mode_bits = try x86ModeBits(instruction, options);
    var parsed = isa_text.parseInstructionText(allocator, instruction.text) catch |err| return mapIsaTextError(err);
    defer parsed.deinit(allocator);

    var fixups: std.ArrayList(FixupFact) = .empty;
    errdefer {
        clearFixupFacts(&fixups, allocator);
        fixups.deinit(allocator);
    }

    var context = backend.x86.EncodeContext.init(mode_bits);
    const encoded_mnemonic = applyX86MnemonicPrefixes(&context, parsed.mnemonic, parsed.operands);

    var resolver_context: X86ResolverContext = .{
        .isa = instruction.target.isa(),
        .mode_bits = mode_bits,
        .allocator = allocator,
        .span = instruction.span,
        .fixups = &fixups,
    };
    const resolver: backend.x86.ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = unknownX86ExpressionResolver,
    };

    var encoded = backend.x86.encodeBuiltinUnitsWithResolver(
        allocator,
        encoded_mnemonic.mnemonic,
        encoded_mnemonic.operandSlice(),
        context,
        false,
        resolver,
    ) catch |err| return mapX86EncodeError(err);
    if (fixups.items.len != 0 and isX86BranchMnemonic(encoded_mnemonic.mnemonic)) {
        encoded.deinit(allocator);
        clearFixupFacts(&fixups, allocator);
        const current_known = false;
        context = context
            .withBranchRelaxationHint(.near)
            .withBranchRelaxationCurrentKnown(&current_known);
        encoded = backend.x86.encodeBuiltinUnitsWithResolver(
            allocator,
            encoded_mnemonic.mnemonic,
            encoded_mnemonic.operandSlice(),
            context,
            false,
            resolver,
        ) catch |err| return mapX86EncodeError(err);
    }
    defer encoded.deinit(allocator);

    const bytes = backend.x86.materializeOutput(allocator, encoded.units()) catch |err| return mapX86MaterializeError(err);
    errdefer allocator.free(bytes);
    try applyX86BackendFixups(allocator, fixups.items, encoded.units());
    applyX86BranchFallbackFixup(fixups.items, parsed.mnemonic, bytes.len);

    const current_size = sizeToU32(bytes.len) catch return error.InstructionTooLarge;
    const symbolic_operands = try fixups.toOwnedSlice(allocator);
    errdefer deinitFixupFacts(symbolic_operands, allocator);
    return .{
        .bytes = bytes,
        .min_size = if (encoded.branch_relaxation_decision == .rel8) current_size else current_size,
        .max_size = current_size,
        .current_size = current_size,
        .fixups = symbolic_operands,
        .relaxable = symbolic_operands.len != 0 or encoded.branch_relaxation_decision != null,
    };
}

const X86EncodedMnemonic = struct {
    mnemonic: []const u8,
    operands: []const []const u8,
    lock_operands: [4][]const u8 = undefined,
    lock_operand_count: usize = 0,
    use_lock_operands: bool = false,

    fn operandSlice(self: *const X86EncodedMnemonic) []const []const u8 {
        if (self.use_lock_operands) return self.lock_operands[0..self.lock_operand_count];
        return self.operands;
    }
};

fn applyX86MnemonicPrefixes(
    context: *backend.x86.EncodeContext,
    mnemonic: []const u8,
    operands: []const []const u8,
) X86EncodedMnemonic {
    if (operands.len == 0) return .{ .mnemonic = mnemonic, .operands = operands };

    if (std.ascii.eqlIgnoreCase(mnemonic, "lock")) {
        const split = std.mem.indexOfAny(u8, operands[0], " \t");
        const locked_mnemonic = if (split) |index| operands[0][0..index] else operands[0];
        const first_operand = if (split) |index|
            std.mem.trim(u8, operands[0][index + 1 ..], " \t\r\n")
        else
            "";

        var result: X86EncodedMnemonic = .{
            .mnemonic = locked_mnemonic,
            .operands = &.{},
            .use_lock_operands = true,
        };
        const first_operand_count: usize = if (first_operand.len == 0) 0 else 1;
        if (first_operand_count + operands.len - 1 > result.lock_operands.len) {
            return .{ .mnemonic = mnemonic, .operands = operands };
        }
        context.* = context.withLock(true);
        if (first_operand.len != 0) {
            result.lock_operands[0] = first_operand;
        }
        for (operands[1..], 0..) |operand, index| {
            result.lock_operands[first_operand_count + index] = operand;
        }
        result.lock_operand_count = first_operand_count + operands.len - 1;
        return result;
    }

    if (x86RepPrefixFromMnemonic(mnemonic)) |rep_prefix| {
        context.* = context.withRepPrefix(rep_prefix);
        return .{
            .mnemonic = operands[0],
            .operands = operands[1..],
        };
    }

    return .{ .mnemonic = mnemonic, .operands = operands };
}

fn x86RepPrefixFromMnemonic(mnemonic: []const u8) ?backend.x86.RepPrefixKind {
    if (std.ascii.eqlIgnoreCase(mnemonic, "rep")) return .rep;
    if (std.ascii.eqlIgnoreCase(mnemonic, "repe")) return .repe;
    if (std.ascii.eqlIgnoreCase(mnemonic, "repz")) return .repe;
    if (std.ascii.eqlIgnoreCase(mnemonic, "repne")) return .repne;
    if (std.ascii.eqlIgnoreCase(mnemonic, "repnz")) return .repne;
    return null;
}

fn x86ModeBits(instruction: fragment.IsaInstructionFragment, options: target.Target) AdapterError!u8 {
    const mode_bits = instruction.target.bits() orelse options.bits() orelse return error.InvalidModeBits;
    if (mode_bits != 16 and mode_bits != 32 and mode_bits != 64) return error.InvalidModeBits;
    return @intCast(mode_bits);
}

fn encodeRiscvInstruction(
    allocator: Allocator,
    instruction: fragment.IsaInstructionFragment,
    options: target.Target,
) AdapterError!InstructionFacts {
    const xlen = try riscvXLen(instruction, options);
    var fixups: std.ArrayList(FixupFact) = .empty;
    errdefer {
        clearFixupFacts(&fixups, allocator);
        fixups.deinit(allocator);
    }
    var resolver_context: RiscvUnresolvedContext = .{
        .allocator = allocator,
        .span = instruction.span,
        .kind = if (riscvMnemonicIsPcRelative(instruction.text)) .pc_relative else .absolute,
        .fixups = &fixups,
    };
    const resolver: backend.riscv.source.ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = recordUnresolvedRiscvExpression,
    };

    const encoded = backend.riscv.encodeInstructionText(instruction.text, xlen, resolver) catch |err| return mapRiscvSourceError(err);
    const width_bits = std.math.mul(u16, encoded.len, 8) catch return error.InvalidBackendFixupWidth;
    for (fixups.items) |*stored_fixup| stored_fixup.width_bits = width_bits;
    const encoded_bytes = encoded.asSlice();
    const bytes = try allocator.dupe(u8, encoded_bytes);
    errdefer allocator.free(bytes);
    const symbolic_operands = try fixups.toOwnedSlice(allocator);
    errdefer deinitFixupFacts(symbolic_operands, allocator);

    const current_size = sizeToU32(bytes.len) catch return error.InstructionTooLarge;
    return .{
        .bytes = bytes,
        .min_size = current_size,
        .max_size = current_size,
        .current_size = current_size,
        .fixups = symbolic_operands,
        .relaxable = symbolic_operands.len != 0,
    };
}

pub fn encodeResolvedRiscvInstruction(
    instruction: fragment.IsaInstructionFragment,
    options: target.Target,
    instruction_address: u64,
    resolutions: []const RiscvResolution,
) AdapterError!RiscvEncodedInstruction {
    const xlen = try riscvXLen(instruction, options);
    var resolver_context: RiscvResolvedContext = .{
        .instruction_address = instruction_address,
        .pc_relative = riscvMnemonicIsPcRelative(instruction.text),
        .resolutions = resolutions,
    };
    const resolver: backend.riscv.source.ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = resolveRiscvExpression,
    };
    const encoded = backend.riscv.encodeInstructionText(instruction.text, xlen, resolver) catch |err| return mapRiscvSourceError(err);
    return .{ .bytes = encoded.bytes, .len = encoded.len };
}

fn riscvXLen(instruction: fragment.IsaInstructionFragment, options: target.Target) AdapterError!u8 {
    const xlen = instruction.target.bits() orelse options.bits() orelse return error.InvalidModeBits;
    if (xlen != 32 and xlen != 64) return error.InvalidModeBits;
    return @intCast(xlen);
}

fn applyX86BackendFixups(allocator: Allocator, facts: []FixupFact, units: []const backend.x86.EncodeUnit) AdapterError!void {
    var fixup_index: usize = 0;
    var byte_offset: u32 = 0;
    for (units) |unit| {
        const unit_size = if (unit.fixup) |backend_fixup| backend_fixup.size else unit.bytes.len;
        if (unit.fixup) |backend_fixup| {
            if (fixup_index >= facts.len) return error.BackendFixupCountMismatch;
            facts[fixup_index].kind = switch (backend_fixup.kind) {
                .absolute => .absolute,
                .relative => .pc_relative,
                .segment => return error.UnsupportedBackendFixupKind,
            };
            const effective_addend = try x86BackendFixupAddend(byte_offset, backend_fixup);
            try applyX86BackendFixupAddend(allocator, &facts[fixup_index], effective_addend);
            facts[fixup_index].offset = byte_offset;
            facts[fixup_index].width_bits = try fixupWidthBits(backend_fixup.size);
            fixup_index += 1;
        } else if (fixup_index < facts.len and unit.note != null and std.mem.eql(u8, unit.note.?, "rip-relative displacement")) {
            facts[fixup_index].kind = .pc_relative;
            facts[fixup_index].offset = byte_offset;
            facts[fixup_index].width_bits = try fixupWidthBits(try sizeToU8(unit.bytes.len));
            fixup_index += 1;
        }
        byte_offset = std.math.add(u32, byte_offset, try sizeToU32(unit_size)) catch return error.InstructionTooLarge;
    }
}

fn x86BackendFixupAddend(byte_offset: u32, backend_fixup: backend.x86.Fixup) AdapterError!i64 {
    if (backend_fixup.kind != .relative) return backend_fixup.toffset;

    const fixup_end = std.math.add(i64, @intCast(byte_offset), @as(i64, @intCast(backend_fixup.size))) catch return error.BackendFixupOffsetOverflow;
    const relbase_delta = std.math.sub(i64, fixup_end, backend_fixup.relbase) catch return error.BackendFixupOffsetOverflow;
    return std.math.add(i64, backend_fixup.toffset, relbase_delta) catch return error.BackendFixupOffsetOverflow;
}

fn applyX86BackendFixupAddend(allocator: Allocator, fact: *FixupFact, addend: i64) AdapterError!void {
    if (addend == 0) return;

    const old_target = fact.target;
    const magnitude = signedMagnitude(addend);
    const new_target = try std.fmt.allocPrint(allocator, "{s} {c} {}", .{
        old_target,
        if (addend < 0) @as(u8, '-') else @as(u8, '+'),
        magnitude,
    });
    allocator.free(old_target);
    fact.target = new_target;
}

fn signedMagnitude(value: i64) u64 {
    if (value >= 0) return @intCast(value);
    const raw: u64 = @bitCast(value);
    return (~raw) + 1;
}

fn applyX86BranchFallbackFixup(facts: []FixupFact, mnemonic: []const u8, encoded_size: usize) void {
    if (facts.len != 1) return;
    if (facts[0].kind != .absolute or facts[0].offset != 0 or facts[0].width_bits != 64) return;
    if (!isX86BranchMnemonic(mnemonic)) return;
    if (encoded_size == 2) {
        facts[0].kind = .pc_relative;
        facts[0].offset = 1;
        facts[0].width_bits = 8;
    } else if (encoded_size == 5) {
        facts[0].kind = .pc_relative;
        facts[0].offset = 1;
        facts[0].width_bits = 32;
    }
}

fn isX86BranchMnemonic(mnemonic: []const u8) bool {
    if (std.ascii.eqlIgnoreCase(mnemonic, "jmp")) return true;
    if (std.ascii.eqlIgnoreCase(mnemonic, "call")) return true;
    if (mnemonic.len < 2) return false;
    if (mnemonic[0] != 'j' and mnemonic[0] != 'J') return false;
    return true;
}

fn fixupWidthBits(byte_size: u8) AdapterError!u16 {
    if (byte_size == 0 or byte_size > 8) return error.InvalidBackendFixupWidth;
    return std.math.mul(u16, byte_size, 8) catch return error.InvalidBackendFixupWidth;
}

fn deinitFixupFacts(facts: []FixupFact, allocator: Allocator) void {
    for (facts) |*stored_fixup| stored_fixup.deinit(allocator);
    allocator.free(facts);
}

fn clearFixupFacts(facts: *std.ArrayList(FixupFact), allocator: Allocator) void {
    for (facts.items) |*stored_fixup| stored_fixup.deinit(allocator);
    facts.clearRetainingCapacity();
}

fn riscvMnemonicIsPcRelative(text: []const u8) bool {
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    const end = std.mem.indexOfAny(u8, trimmed, " \t\r\n") orelse trimmed.len;
    const mnemonic = trimmed[0..end];
    var normalized_storage: [96]u8 = undefined;
    if (mnemonic.len > normalized_storage.len) return false;
    for (mnemonic, 0..) |byte, index| {
        normalized_storage[index] = switch (byte) {
            '.', '-' => '_',
            else => std.ascii.toLower(byte),
        };
    }
    const spec = (backend.riscv.api.instructionByMnemonicAnyXLen(normalized_storage[0..mnemonic.len]) catch return false) orelse return false;
    return switch (spec.semantic) {
        .rs1_rs2_offset, .rd_offset, .offset, .c_offset, .c_rs1_p_offset => true,
        else => false,
    };
}

fn mapIsaTextError(err: isa_text.ParseError) AdapterError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidInstructionText => error.InvalidInstructionText,
    };
}

fn mapX86EncodeError(err: backend.x86.EncodeError) AdapterError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.AmbiguousMemorySize => error.AmbiguousMemorySize,
        error.CmpR64ImmediateOutOfRange => error.CmpR64ImmediateOutOfRange,
        error.HighRegisterNotAllowed => error.HighRegisterNotAllowed,
        error.ImpossibleAddressSize => error.ImpossibleAddressSize,
        error.InvalidMemoryScale => error.InvalidMemoryScale,
        error.InvalidRspIndexRegister => error.InvalidRspIndexRegister,
        error.UnsupportedOperandSyntax => error.UnsupportedOperandSyntax,
        error.UnsupportedPrefixes => error.UnsupportedPrefixes,
        else => error.UnsupportedX86Instruction,
    };
}

fn mapX86MaterializeError(err: backend.x86.MaterializeError) AdapterError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.InvalidFixupSize => error.InvalidBackendFixupWidth,
        error.RelativeFixupOverflow => error.BackendFixupOffsetOverflow,
        error.UnresolvedFixup,
        error.UnsupportedSegmentFixup,
        error.UnsupportedReserve,
        => error.BackendOutputMaterializationFailed,
    };
}

fn mapRiscvSourceError(err: backend.riscv.source.SourceError) AdapterError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        else => error.UnsupportedRiscvInstruction,
    };
}

fn unknownX86ExpressionResolver(context: *anyopaque, text: []const u8) backend.x86.ExpressionResolveError!?backend.x86.ResolvedExpr {
    const resolver_context: *X86ResolverContext = @ptrCast(@alignCast(context));
    if (resolver_context.isa != .x86_64) {
        return null;
    }
    if (resolver_context.mode_bits != 16 and resolver_context.mode_bits != 32 and resolver_context.mode_bits != 64) {
        return null;
    }
    const target_text = std.mem.trim(u8, text, " \t\r\n");
    if (target_text.len == 0) return null;
    const owned_target = try resolver_context.allocator.dupe(u8, target_text);
    errdefer resolver_context.allocator.free(owned_target);
    try resolver_context.fixups.append(resolver_context.allocator, .{
        .target = owned_target,
        .kind = .absolute,
        .offset = 0,
        .width_bits = 64,
        .span = resolver_context.span,
    });
    return .{
        .value = 0,
        .known = false,
        .current_known = false,
        .simple = false,
        .symbolic = true,
    };
}

fn recordUnresolvedRiscvExpression(context: *anyopaque, text: []const u8) backend.riscv.source.SourceError!?i64 {
    const resolver_context: *RiscvUnresolvedContext = @ptrCast(@alignCast(context));
    const target_text = std.mem.trim(u8, text, " \t\r\n");
    if (target_text.len == 0) return null;
    const owned_target = try resolver_context.allocator.dupe(u8, target_text);
    errdefer resolver_context.allocator.free(owned_target);
    try resolver_context.fixups.append(resolver_context.allocator, .{
        .target = owned_target,
        .kind = resolver_context.kind,
        .offset = 0,
        .width_bits = 0,
        .span = resolver_context.span,
    });
    return 0;
}

fn resolveRiscvExpression(context: *anyopaque, text: []const u8) backend.riscv.source.SourceError!?i64 {
    const resolver_context: *const RiscvResolvedContext = @ptrCast(@alignCast(context));
    const target_text = std.mem.trim(u8, text, " \t\r\n");
    for (resolver_context.resolutions) |resolution| {
        if (!std.mem.eql(u8, resolution.target, target_text)) continue;
        const raw_value: i128 = @intCast(resolution.value);
        const adjusted = if (resolver_context.pc_relative)
            raw_value - @as(i128, @intCast(resolver_context.instruction_address))
        else
            raw_value;
        if (adjusted < std.math.minInt(i64) or adjusted > std.math.maxInt(i64)) {
            return error.ImmediateOutOfRange;
        }
        return @intCast(adjusted);
    }
    return null;
}

fn sizeToU32(size: usize) error{InstructionTooLarge}!u32 {
    if (size > std.math.maxInt(u32)) return error.InstructionTooLarge;
    return @intCast(size);
}

fn sizeToU8(size: usize) error{InstructionTooLarge}!u8 {
    if (size > std.math.maxInt(u8)) return error.InstructionTooLarge;
    return @intCast(size);
}

fn testEncodeInstruction(
    text: []const u8,
    instruction_target: target.Target,
    options: target.Target,
) !InstructionFacts {
    const owned_text = try std.testing.allocator.dupe(u8, text);
    defer std.testing.allocator.free(owned_text);

    return encodeInstruction(
        std.testing.allocator,
        .{
            .section = .{ .index = 0 },
            .target = instruction_target,
            .text = owned_text,
            .min_size = 0,
            .max_size = 0,
            .current_size = 0,
            .span = source.unknown_span,
        },
        options,
    );
}

test "backend adapter encodes fixed x86 instruction bytes" {
    const cases = [_]struct {
        text: []const u8,
        bytes: []const u8,
    }{
        .{ .text = "mov rax, 1", .bytes = &.{ 0xB8, 0x01, 0x00, 0x00, 0x00 } },
        .{ .text = "add rax, 2", .bytes = &.{ 0x48, 0x83, 0xC0, 0x02 } },
        .{ .text = "rep movsb", .bytes = &.{ 0xF3, 0xA4 } },
        .{ .text = "ret", .bytes = &.{0xC3} },
    };

    for (cases) |case| {
        var facts = try testEncodeInstruction(case.text, target.Target.default, target.Target.default);
        defer facts.deinit(std.testing.allocator);

        try std.testing.expectEqualSlices(u8, case.bytes, facts.bytes);
        try std.testing.expectEqual(@as(u32, @intCast(case.bytes.len)), facts.current_size);
        try std.testing.expect(!facts.relaxable);
        try std.testing.expectEqual(@as(usize, 0), facts.fixups.len);
    }
}

test "backend adapter lets backend parser own x86 vector operands" {
    const x86_target = try target.Target.initX86(64);
    const cases = [_]struct {
        text: []const u8,
        bytes: []const u8,
    }{
        .{ .text = "vaddps xmm0, xmm1, xmm2", .bytes = &.{ 0xc5, 0xf0, 0x58, 0xc2 } },
        .{ .text = "pshufb xmm1, xmm2", .bytes = &.{ 0x66, 0x0f, 0x38, 0x00, 0xca } },
        .{ .text = "pextrb eax, xmm1, 2", .bytes = &.{ 0x66, 0x0f, 0x3a, 0x14, 0xc8, 0x02 } },
        .{ .text = "vpshufb xmm1, xmm2, xmm3", .bytes = &.{ 0xc4, 0xe2, 0x69, 0x00, 0xcb } },
        .{ .text = "vinsertps xmm1, xmm2, xmm3, 4", .bytes = &.{ 0xc4, 0xe3, 0x69, 0x21, 0xcb, 0x04 } },
    };

    for (cases) |case| {
        var facts = try testEncodeInstruction(case.text, x86_target, x86_target);
        defer facts.deinit(std.testing.allocator);

        try std.testing.expectEqual(@as(usize, 0), facts.fixups.len);
        try std.testing.expectEqual(false, facts.relaxable);
        try std.testing.expectEqualSlices(u8, case.bytes, facts.bytes);
    }
}

test "backend adapter marks symbolic x86 jump relaxable" {
    var facts = try testEncodeInstruction("jmp target", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expect(facts.current_size > 0);
    try std.testing.expect(facts.relaxable);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u32, 1), facts.fixups[0].offset);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);
}

test "backend adapter maps symbolic x86 conditional jump to near relative fixup" {
    var facts = try testEncodeInstruction("jne target", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0x0F, 0x85, 0xFA, 0xFF, 0xFF, 0xFF }, facts.bytes);
    try std.testing.expect(facts.relaxable);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u32, 2), facts.fixups[0].offset);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);
}

test "backend adapter strips x86 branch size hints from fixup target" {
    var facts = try testEncodeInstruction("jmp short target", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expect(facts.relaxable);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target", facts.fixups[0].target);
}

test "backend adapter records symbolic expression fixup facts" {
    var facts = try testEncodeInstruction("mov rax, target + 4", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expect(facts.current_size > 0);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target + 4", facts.fixups[0].target);
}

test "backend adapter maps x86 rip-relative memory fixups to displacement bytes" {
    var facts = try testEncodeInstruction("mov eax, [rel target]", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0x8B, 0x05, 0xFA, 0xFF, 0xFF, 0xFF }, facts.bytes);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u32, 2), facts.fixups[0].offset);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);
}

test "backend adapter preserves x86 rip-relative memory fixup addends" {
    var facts = try testEncodeInstruction("mov eax, [rel target + 4]", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0x8B, 0x05, 0xFE, 0xFF, 0xFF, 0xFF }, facts.bytes);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target + 4", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u32, 2), facts.fixups[0].offset);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);
}

test "backend adapter accounts for x86 rip-relative relbase after immediate tails" {
    var facts = try testEncodeInstruction("cmp qword [rel target + 4], 0x48474645", target.Target.default, target.Target.default);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0x48, 0x81, 0x3D, 0xF9, 0xFF, 0xFF, 0xFF, 0x45, 0x46, 0x47, 0x48 }, facts.bytes);
    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("target", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u32, 3), facts.fixups[0].offset);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);
}

test "backend adapter encodes fixed riscv instruction bytes" {
    const riscv_target = try target.Target.initRiscv(64);
    var facts = try testEncodeInstruction("addi x1, x0, 1", riscv_target, riscv_target);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0x93, 0x00, 0x10, 0x00 }, facts.bytes);
    try std.testing.expectEqual(@as(u32, 4), facts.current_size);
    try std.testing.expect(!facts.relaxable);
    try std.testing.expectEqual(@as(usize, 0), facts.fixups.len);
}

test "backend adapter leaves parsed riscv vector operands out of fixups" {
    const riscv_target = try target.Target.initRiscv(64);
    var facts = try testEncodeInstruction("vsetvli t0, a2, e8, m8, ta, ma", riscv_target, riscv_target);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqualSlices(u8, &.{ 0xd7, 0x72, 0x36, 0x0c }, facts.bytes);
    try std.testing.expectEqual(@as(usize, 0), facts.fixups.len);
}

test "backend adapter records and resolves riscv branch labels through re-encoding" {
    const riscv_target = try target.Target.initRiscv(64);
    var facts = try testEncodeInstruction("beq a0, a1, forward", riscv_target, riscv_target);
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), facts.fixups.len);
    try std.testing.expectEqualStrings("forward", facts.fixups[0].target);
    try std.testing.expectEqual(fixup.FixupKind.pc_relative, facts.fixups[0].kind);
    try std.testing.expectEqual(@as(u16, 32), facts.fixups[0].width_bits);

    const text = try std.testing.allocator.dupe(u8, "beq a0, a1, forward");
    defer std.testing.allocator.free(text);
    var encoded = try encodeResolvedRiscvInstruction(
        .{
            .section = .{ .index = 0 },
            .target = riscv_target,
            .text = text,
            .min_size = 4,
            .max_size = 4,
            .current_size = 4,
            .span = source.unknown_span,
        },
        riscv_target,
        0x34,
        &.{.{ .target = "forward", .value = 0x3c }},
    );
    try std.testing.expectEqualSlices(u8, &.{ 0x63, 0x04, 0xb5, 0x00 }, encoded.asSlice());
}

test "backend adapter encodes complete spirv source modules" {
    const source_text =
        \\OpCapability Shader
        \\OpMemoryModel Logical GLSL450
        \\%1 = OpTypeVoid
    ;
    var facts = try encodeSpirvSource(std.testing.allocator, source_text, target.Target.spv());
    defer facts.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 12 * @sizeOf(u32)), facts.bytes.len);
    try std.testing.expectEqual(@as(u32, 0x07230203), std.mem.readInt(u32, facts.bytes[0..4], .little));
    try std.testing.expectEqual(@as(u32, 0x00010600), std.mem.readInt(u32, facts.bytes[4..8], .little));
    try std.testing.expectEqual(@as(u32, 2), std.mem.readInt(u32, facts.bytes[12..16], .little));
    try std.testing.expectEqual(@as(u32, 0x00020011), std.mem.readInt(u32, facts.bytes[20..24], .little));
}
