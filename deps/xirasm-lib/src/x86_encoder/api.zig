const std = @import("std");
const encode = @import("encode.zig");
const ea = @import("ea.zig");
const match = @import("match.zig");
const size = @import("size.zig");
const types = @import("types.zig");
const tables = @import("tables.zig");

const Allocator = std.mem.Allocator;

pub const EncodeUnit = encode.EncodeUnit;
pub const Fixup = encode.Fixup;
pub const FixupKind = encode.FixupKind;

pub const FixupValueRange = enum {
    wrap,
    signed,
    unsigned,
};

pub fn fixupValueRange(fixup: Fixup) FixupValueRange {
    return switch (fixup.flags & types.out_signmask) {
        types.out_signed => .signed,
        types.out_unsigned => .unsigned,
        else => .wrap,
    };
}

pub const RepPrefixKind = enum {
    none,
    rep,
    repe,
    repne,
    xacquire,
    xrelease,
    bnd,
    nobnd,
};

pub const OperandSizePrefix = enum {
    none,
    osp,
    o16,
    o32,
    o64,
};

pub const AddressSizePrefix = enum {
    none,
    a16,
    a32,
    a64,
};

pub const EncodingPrefix = enum {
    none,
    rex,
    rex2,
    evex,
    vex,
    vex2,
    vex3,
};

pub const EncodeContext = struct {
    mode_bits: u8,
    lock: bool = false,
    rep: RepPrefixKind = .none,
    operand_size: OperandSizePrefix = .none,
    address_size: AddressSizePrefix = .none,
    encoding: EncodingPrefix = .none,
    nf: bool = false,
    zu: bool = false,
    segment: i32 = match.no_seg,
    default_rel: bool = false,
    apx_dfv: u8 = 0,
    output_position: i64 = 0,
    branch_relaxation_hint: ?BranchRelaxationDecision = null,
    branch_relaxation_current_known: ?*const bool = null,

    pub fn init(mode_bits: u8) EncodeContext {
        return .{ .mode_bits = mode_bits };
    }

    pub fn withLock(self: EncodeContext, lock: bool) EncodeContext {
        var next = self;
        next.lock = lock;
        return next;
    }

    pub fn withRepPrefix(self: EncodeContext, rep: RepPrefixKind) EncodeContext {
        var next = self;
        next.rep = rep;
        return next;
    }

    pub fn withOperandSizePrefix(self: EncodeContext, operand_size: OperandSizePrefix) EncodeContext {
        var next = self;
        next.operand_size = operand_size;
        return next;
    }

    pub fn withAddressSizePrefix(self: EncodeContext, address_size: AddressSizePrefix) EncodeContext {
        var next = self;
        next.address_size = address_size;
        return next;
    }

    pub fn withEncodingPrefix(self: EncodeContext, encoding: EncodingPrefix) EncodeContext {
        var next = self;
        next.encoding = encoding;
        return next;
    }

    pub fn withNfPrefix(self: EncodeContext, nf: bool) EncodeContext {
        var next = self;
        next.nf = nf;
        return next;
    }

    pub fn withZuPrefix(self: EncodeContext, zu: bool) EncodeContext {
        var next = self;
        next.zu = zu;
        return next;
    }

    pub fn withSegmentPrefix(self: EncodeContext, segment: i32) EncodeContext {
        var next = self;
        next.segment = segment;
        return next;
    }

    pub fn withDefaultRel(self: EncodeContext, default_rel: bool) EncodeContext {
        var next = self;
        next.default_rel = default_rel;
        return next;
    }

    pub fn withApxDfv(self: EncodeContext, apx_dfv: u8) EncodeContext {
        var next = self;
        next.apx_dfv = apx_dfv;
        return next;
    }

    pub fn withOutputPosition(self: EncodeContext, output_position: i64) EncodeContext {
        var next = self;
        next.output_position = output_position;
        return next;
    }

    pub fn withBranchRelaxationHint(self: EncodeContext, hint: ?BranchRelaxationDecision) EncodeContext {
        var next = self;
        next.branch_relaxation_hint = hint;
        return next;
    }

    pub fn withBranchRelaxationCurrentKnown(self: EncodeContext, current_known: *const bool) EncodeContext {
        var next = self;
        next.branch_relaxation_current_known = current_known;
        return next;
    }
};

pub const BuiltinEncodeRoute = enum {
    source_runtime,
};

pub const BranchRelaxationDecision = enum {
    rel8,
    near,
};

pub const BuiltinMainlineGap = struct {
    stage: []const u8,
    blocker: []const u8,
};

pub const EncodeError = Allocator.Error || size.CalcSizeError || encode.GencodeError || error{
    AmbiguousMemorySize,
    CmpR64ImmediateOutOfRange,
    ExpressionResolutionFailed,
    InvalidIntegerLiteral,
    InvalidMemoryScale,
    InvalidRspIndexRegister,
    InstructionSizeOverflow,
    IntegerOverflow,
    LegacyOnlyTemplate,
    NegativeInstructionSize,
    NoMatchingTemplate,
    UnsupportedMnemonic,
    UnsupportedOperands,
    UnsupportedOperandSyntax,
    UnsupportedPrefixes,
};

pub const MaterializeError = Allocator.Error || error{
    InvalidFixupSize,
    RelativeFixupOverflow,
    UnresolvedFixup,
    UnsupportedSegmentFixup,
    UnsupportedReserve,
};

pub const BuiltinEncodeResult = struct {
    encoded: encode.OwnedEncodeResult,
    route: BuiltinEncodeRoute = .source_runtime,
    branch_relaxation_decision: ?BranchRelaxationDecision = null,

    pub fn deinit(self: *BuiltinEncodeResult, allocator: Allocator) void {
        self.encoded.deinit(allocator);
    }

    pub fn units(self: *const BuiltinEncodeResult) []const EncodeUnit {
        return self.encoded.units.items;
    }
};

pub const ResolvedExpr = struct {
    value: i64,
    known: bool,
    current_known: bool,
    simple: bool,
    symbolic: bool,
};

pub const ExpressionResolveError = Allocator.Error || error{
    ExpressionResolutionFailed,
};

pub const ExpressionResolver = struct {
    context: *anyopaque,
    resolveFn: *const fn (*anyopaque, []const u8) ExpressionResolveError!?ResolvedExpr,

    fn resolve(self: ExpressionResolver, text: []const u8) ExpressionResolveError!?ResolvedExpr {
        return self.resolveFn(self.context, text);
    }
};

pub fn builtinMainlineGap() BuiltinMainlineGap {
    return .{
        .stage = "insn_early_setup -> find_match -> calcsize -> gencode",
        .blocker = "builtin 直连 x86_encoder 已改走 x86 encoder runtime pipeline；剩余失败必须来自 source-backed stage gap 或 generation-chain 字段缺口，禁止回到 root 层手写 opcode",
    };
}

pub fn encodeBuiltinUnits(
    allocator: Allocator,
    mnemonic: []const u8,
    operand_refs: []const []const u8,
    context: EncodeContext,
) EncodeError!BuiltinEncodeResult {
    return encodeBuiltinUnitsWithResolver(allocator, mnemonic, operand_refs, context, false, null);
}

pub fn encodeBuiltinUnitsWithResolver(
    allocator: Allocator,
    mnemonic: []const u8,
    operand_refs: []const []const u8,
    context: EncodeContext,
    legacy_only: bool,
    resolver: ?ExpressionResolver,
) EncodeError!BuiltinEncodeResult {
    const name = std.mem.trim(u8, mnemonic, " \t\r\n");
    const opcode = match.opcodeByMnemonic(name) orelse {
        if (operand_refs.len == 0) {
            if (standalonePrefixValueByName(name)) |prefix| {
                return .{
                    .encoded = try encode.emitStandalonePrefix(allocator, prefix, context.mode_bits, context.output_position),
                    .route = .source_runtime,
                };
            }
        }
        return error.UnsupportedMnemonic;
    };
    if (operand_refs.len > match.max_operands) return error.UnsupportedOperands;

    var ins = match.Instruction.init(opcode, context.mode_bits);
    ins.loc.offset = context.output_position;
    ins.default_rel = context.default_rel;
    ins.first_pass = false;
    try applyEncodeContext(&ins, context);

    var out_index: usize = 0;
    for (operand_refs) |operand_ref| {
        if (try farImmediatePairFromText(name, operand_ref, resolver)) |pair| {
            if (out_index + pair.operands.len > match.max_operands) return error.UnsupportedOperands;
            for (pair.operands) |operand| {
                ins.oprs[out_index] = operand;
                out_index += 1;
            }
            continue;
        }

        if (registerPairFromText(operand_ref)) |pair| {
            if (out_index + pair.operands.len > match.max_operands) return error.UnsupportedOperands;
            for (pair.operands) |operand| {
                ins.oprs[out_index] = operand;
                out_index += 1;
            }
            continue;
        }

        const parsed = try operandFromText(&ins, operand_ref, resolver);
        switch (parsed) {
            .operand => |operand| {
                if (out_index >= match.max_operands) return error.UnsupportedOperands;
                if ((operand.decoflags & (types.brdcast_mask | types.staticrnd_mask | types.sae_mask)) != 0) {
                    ins.evex_brerop = @intCast(out_index);
                }
                ins.oprs[out_index] = operand;
                out_index += 1;
            },
            .er_sae => |decorator| {
                if (out_index == 0) return error.UnsupportedOperandSyntax;
                const target_index = out_index - 1;
                ins.oprs[target_index].decoflags |= decorator.decoflags;
                ins.evex_rm = decorator.evex_rm;
                ins.evex_brerop = @intCast(target_index);
            },
        }
    }
    if (out_index > std.math.maxInt(u8)) return error.UnsupportedOperands;
    ins.operands = @intCast(out_index);
    inferApxRaoUnsizedMemorySizeFromGprOperand(name, &ins);
    preferMemoryIndirectBranchForms(name, &ins);
    const branch_relaxation_candidate = automaticBranchRelaxationCandidate(&ins);
    if (branch_relaxation_candidate and
        context.branch_relaxation_current_known != null and
        !context.branch_relaxation_current_known.?.* and
        context.branch_relaxation_hint == .near)
    {
        ins.oprs[0].type_bits |= match.near;
        ins.opt |= types.optim_no_jcc_relax | types.optim_no_jmp_relax;
    }
    try rejectUnsupportedCmpR64Imm64(name, &ins);

    try size.insnEarlySetup(&ins);
    const match_result = match.findMatch(BuiltinMatchContext{}, &ins);
    if (!match_result.isSuccess()) return error.NoMatchingTemplate;
    try rejectAmbiguousUnsizedMemory(name, &ins);

    const template = ins.itemp orelse return error.MissingTemplate;
    if (legacy_only and isNonLegacyTemplate(template)) return error.LegacyOnlyTemplate;
    const branch_relaxation_decision: ?BranchRelaxationDecision = if (branch_relaxation_candidate and
        (ins.oprs[0].opflags & types.opflag_unknown) == 0)
        if (template.iflagTest(types.if_jmp_relax)) .rel8 else .near
    else
        null;

    var diagnostics: size.CalcSizeDiagnostics = .{};
    const insn_size = try size.calcSizeWithContext(sizeContext(context, &diagnostics), &ins);
    if (diagnostics.count(.instruction_not_lockable) != 0) return error.UnsupportedPrefixes;
    if (diagnostics.count(.superfluous_lock_xchg) != 0) return error.UnsupportedPrefixes;
    if (diagnostics.count(.hle_requires_lock) != 0) return error.UnsupportedPrefixes;
    if (diagnostics.count(.hle_invalid) != 0) return error.UnsupportedPrefixes;
    if (insn_size < 0) return error.NegativeInstructionSize;
    const inslen: usize = std.math.cast(usize, insn_size) orelse return error.InstructionSizeOverflow;

    return .{
        .encoded = try encode.gencode(allocator, &ins, inslen),
        .route = .source_runtime,
        .branch_relaxation_decision = branch_relaxation_decision,
    };
}

fn isNonLegacyTemplate(template: match.TemplateRef) bool {
    return template.iflagTest(types.if_vex) or
        template.iflagTest(types.if_evex) or
        template.iflagTest(types.if_apx) or
        template.iflagTest(types.if_rex2);
}

fn rejectUnsupportedCmpR64Imm64(mnemonic: []const u8, ins: *const match.Instruction) EncodeError!void {
    if (!std.ascii.eqlIgnoreCase(mnemonic, "cmp")) return;
    if (ins.bits != 64 or ins.operands != 2) return;

    const immediate_index: usize = if ((ins.oprs[0].type_bits & match.immediate) != 0)
        0
    else if ((ins.oprs[1].type_bits & match.immediate) != 0)
        1
    else
        return;
    const target_index: usize = if (immediate_index == 0) 1 else 0;

    if (!operandIs64BitTarget(ins.oprs[target_index])) return;

    const immediate = ins.oprs[immediate_index];
    if ((immediate.opflags & types.opflag_unknown) != 0) return;
    if (immediate.offset < std.math.minInt(i32) or immediate.offset > std.math.maxInt(i32)) {
        return error.CmpR64ImmediateOutOfRange;
    }
}

fn operandIs64BitTarget(operand: match.Operand) bool {
    if (operand.kind == .register) {
        const register = tables.registerByExprReg(operand.basereg) orelse return false;
        const flags: u64 = @intCast(register.flags);
        return isClass(match.reg64, flags) or (flags & match.bits64) != 0;
    }
    if ((operand.type_bits & match.bits64) != 0) return true;
    if (isClass(match.reg64, operand.type_bits)) return true;
    return false;
}

fn rejectAmbiguousUnsizedMemory(mnemonic: []const u8, ins: *const match.Instruction) EncodeError!void {
    if (!instructionRequiresExplicitMemorySize(mnemonic)) return;
    for (ins.oprs[0..ins.operands]) |operand| {
        if (operand.kind != .memory) continue;
        if ((operand.type_bits & types.msize_mask) == 0) return error.AmbiguousMemorySize;
    }
}

fn instructionRequiresExplicitMemorySize(mnemonic: []const u8) bool {
    return std.ascii.eqlIgnoreCase(mnemonic, "inc") or
        std.ascii.eqlIgnoreCase(mnemonic, "dec") or
        std.ascii.eqlIgnoreCase(mnemonic, "not") or
        std.ascii.eqlIgnoreCase(mnemonic, "neg") or
        std.ascii.eqlIgnoreCase(mnemonic, "mul") or
        std.ascii.eqlIgnoreCase(mnemonic, "imul") or
        std.ascii.eqlIgnoreCase(mnemonic, "div") or
        std.ascii.eqlIgnoreCase(mnemonic, "idiv");
}

fn applyEncodeContext(ins: *match.Instruction, context: EncodeContext) EncodeError!void {
    if (context.lock) {
        ins.prefixes[match.PrefixSlot.lock.index()] = match.PrefixToken.lock;
    }
    ins.prefixes[match.PrefixSlot.rep.index()] = switch (context.rep) {
        .none => match.PrefixToken.none,
        .rep => .{ .value = match.p_rep },
        .repe => .{ .value = match.p_repe },
        .repne => .{ .value = match.p_repne },
        .xacquire => match.PrefixToken.xacquire,
        .xrelease => match.PrefixToken.xrelease,
        .bnd => match.PrefixToken.bnd,
        .nobnd => match.PrefixToken.nobnd,
    };
    ins.prefixes[match.PrefixSlot.operand_size.index()] = switch (context.operand_size) {
        .none => match.PrefixToken.none,
        .osp => .{ .value = match.p_osp },
        .o16 => .{ .value = match.p_o16 },
        .o32 => .{ .value = match.p_o32 },
        .o64 => .{ .value = match.p_o64 },
    };
    ins.prefixes[match.PrefixSlot.address_size.index()] = switch (context.address_size) {
        .none => match.PrefixToken.none,
        .a16 => .{ .value = match.p_a16 },
        .a32 => .{ .value = match.p_a32 },
        .a64 => .{ .value = match.p_a64 },
    };
    ins.prefixes[match.PrefixSlot.rex.index()] = switch (context.encoding) {
        .none => match.PrefixToken.none,
        .rex => match.PrefixToken.rex,
        .rex2 => match.PrefixToken.rex2,
        .evex => match.PrefixToken.evex,
        .vex => match.PrefixToken.vex,
        .vex2 => match.PrefixToken.vex2,
        .vex3 => match.PrefixToken.vex3,
    };
    if (context.nf) {
        ins.prefixes[match.PrefixSlot.nf.index()] = match.PrefixToken.nf;
    }
    if (context.zu) {
        ins.prefixes[match.PrefixSlot.zu.index()] = match.PrefixToken.zu;
    }
    if (context.segment != match.no_seg) {
        ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = context.segment };
    }
    if (context.apx_dfv != 0) {
        ins.vex_wlp = context.apx_dfv & 0x0f;
    }
}

fn sizeContext(context: EncodeContext, diagnostics: *size.CalcSizeDiagnostics) size.CalcSizeContext {
    return .{
        .cpu_features = .{
            .x86_64 = context.mode_bits == 64,
            .apx = true,
        },
        .global_bnd = context.rep == .bnd,
        .diagnostics = diagnostics,
    };
}

const BuiltinMatchContext = struct {
    pub fn cpuIflagField(context: @This(), field_index: usize) u32 {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return types.defaultCpuIflagField(field_index);
    }

    pub fn calcSizeSpeculative(context: @This(), ins: *const match.Instruction, temp: match.TemplateRef) match.SpeculativeSize {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return size.calcSizeSpeculative(ins, temp);
    }
};

const ParsedOperandEntry = union(enum) {
    operand: match.Operand,
    er_sae: ErSaeDecorator,
};

const ErSaeDecorator = struct {
    evex_rm: i32,
    decoflags: u16,
};

const FarImmediatePair = struct {
    operands: [2]match.Operand,
};

const RegisterPair = struct {
    operands: [2]match.Operand,
};

fn farImmediatePairFromText(
    mnemonic: []const u8,
    src: []const u8,
    resolver: ?ExpressionResolver,
) EncodeError!?FarImmediatePair {
    if (!std.ascii.eqlIgnoreCase(mnemonic, "jmp") and !std.ascii.eqlIgnoreCase(mnemonic, "call")) {
        return null;
    }

    const text = std.mem.trim(u8, src, " \t\r\n");
    if (text.len == 0) return null;
    const decorated = try splitOperandDecorators(text);
    if (decorated.decorations.len != 0) return null;
    const qualified = try stripOperandQualifiers(decorated.core);
    const split = splitTopLevelDelimiter(qualified.core, ':') orelse return null;

    var segment = (try immediateOperandFromCore(split.left, qualified.qualifiers, 0, resolver)) orelse return null;
    const offset = (try immediateOperandFromCore(split.right, .{}, 0, resolver)) orelse return null;
    segment.type_bits |= match.colon;
    return .{ .operands = .{ segment, offset } };
}

fn registerPairFromText(src: []const u8) ?RegisterPair {
    const text = std.mem.trim(u8, src, " \t\r\n");
    if (text.len == 0) return null;
    const split = splitTopLevelDelimiter(text, ':') orelse return null;
    const left_name = std.mem.trim(u8, split.left, " \t\r\n");
    const right_name = std.mem.trim(u8, split.right, " \t\r\n");
    const left_register = tables.registerByName(left_name) orelse return null;
    const right_register = tables.registerByName(right_name) orelse return null;
    if ((left_register.flags & match.reg_class_sreg) != 0 or
        (right_register.flags & match.reg_class_sreg) != 0)
    {
        return null;
    }

    var left = registerOperand(left_register);
    left.type_bits |= match.colon;
    return .{ .operands = .{ left, registerOperand(right_register) } };
}

fn standalonePrefixValueByName(text: []const u8) ?i32 {
    const prefix = std.mem.trim(u8, text, " \t\r\n");
    if (std.ascii.eqlIgnoreCase(prefix, "wait")) return match.p_wait;
    if (std.ascii.eqlIgnoreCase(prefix, "lock")) return match.p_lock;
    if (std.ascii.eqlIgnoreCase(prefix, "rep")) return match.p_rep;
    if (std.ascii.eqlIgnoreCase(prefix, "repe")) return match.p_repe;
    if (std.ascii.eqlIgnoreCase(prefix, "repz")) return match.p_repz;
    if (std.ascii.eqlIgnoreCase(prefix, "repne")) return match.p_repne;
    if (std.ascii.eqlIgnoreCase(prefix, "repnz")) return match.p_repnz;
    if (std.ascii.eqlIgnoreCase(prefix, "xacquire")) return match.p_xacquire;
    if (std.ascii.eqlIgnoreCase(prefix, "xrelease")) return match.p_xrelease;
    if (std.ascii.eqlIgnoreCase(prefix, "bnd")) return match.p_bnd;
    if (std.ascii.eqlIgnoreCase(prefix, "nobnd")) return match.p_nobnd;
    if (std.ascii.eqlIgnoreCase(prefix, "osp")) return match.p_osp;
    if (std.ascii.eqlIgnoreCase(prefix, "o16")) return match.p_o16;
    if (std.ascii.eqlIgnoreCase(prefix, "o32")) return match.p_o32;
    if (std.ascii.eqlIgnoreCase(prefix, "o64")) return match.p_o64;
    if (std.ascii.eqlIgnoreCase(prefix, "a16")) return match.p_a16;
    if (std.ascii.eqlIgnoreCase(prefix, "a32")) return match.p_a32;
    if (std.ascii.eqlIgnoreCase(prefix, "a64")) return match.p_a64;
    return segmentPrefixValueByName(prefix) catch null;
}

fn operandFromText(ins: *match.Instruction, src: []const u8, resolver: ?ExpressionResolver) EncodeError!ParsedOperandEntry {
    const text = std.mem.trim(u8, src, " \t\r\n");
    if (text.len == 0) return error.UnsupportedOperandSyntax;

    const decorated = try splitOperandDecorators(text);
    if (decorated.core.len == 0) {
        return .{ .er_sae = try parseStandaloneDecoratorOperand(decorated.decorations) };
    }

    const decoflags = try parseDecoratorSuffix(decorated.decorations);
    const qualified = try stripOperandQualifiers(decorated.core);
    applyOperandQualifierInstructionEffects(ins, qualified.qualifiers);
    if (try parseMemoryText(ins, qualified.core, resolver)) |operand| {
        return .{ .operand = applyDecoFlags(applyMemoryParserFlags(applyOperandQualifiers(operand, qualified.qualifiers)), decoflags) };
    }
    if (try registerOperandFromCore(qualified.core)) |operand| {
        return .{ .operand = applyDecoFlags(applyOperandQualifiers(operand, qualified.qualifiers), decoflags) };
    }
    if (try immediateOperandFromCore(qualified.core, qualified.qualifiers, decoflags, resolver)) |operand| {
        return .{ .operand = operand };
    }
    return error.UnsupportedOperandSyntax;
}

fn immediateOperandFromCore(
    core: []const u8,
    qualifiers: OperandQualifiers,
    decoflags: u16,
    resolver: ?ExpressionResolver,
) EncodeError!?match.Operand {
    if (try parseIntLiteralForEncode(core)) |value| {
        var operand: match.Operand = .{
            .kind = .immediate,
            .type_bits = match.imm_normal,
            .opflags = types.opflag_simple,
            .offset = value,
        };
        operand = applyOperandQualifiers(operand, qualifiers);
        setImmFlags(&operand, 0);
        return applyDecoFlags(operand, decoflags);
    }
    if (try resolveExpressionOperand(resolver, core)) |resolved| {
        var operand: match.Operand = .{
            .kind = .immediate,
            .type_bits = match.imm_normal,
            .opflags = if (resolved.simple) types.opflag_simple else 0,
            .offset = resolved.value,
        };
        if (!resolved.known) operand.opflags |= types.opflag_unknown;
        operand.symbolic = resolved.symbolic;
        operand = applyOperandQualifiers(operand, qualifiers);
        setImmFlags(&operand, 0);
        return applyDecoFlags(operand, decoflags);
    }
    return null;
}

const OperandQualifiers = struct {
    type_bits: u64 = 0,
    opflags: i32 = 0,
    eaflags: i32 = 0,
};

const QualifiedOperandText = struct {
    qualifiers: OperandQualifiers,
    core: []const u8,
};

const OperandQualifierPrefix = struct {
    name: []const u8,
    bits: u64,
};

const DecoratedOperandText = struct {
    core: []const u8,
    decorations: []const u8,
};

const brc_rn: i32 = types.brc_rn;
const brc_rd: i32 = types.brc_rd;
const brc_ru: i32 = types.brc_ru;
const brc_rz: i32 = types.brc_rz;
const brc_sae: i32 = types.brc_sae;

const operand_qualifier_prefixes = [_]OperandQualifierPrefix{
    .{ .name = "strict", .bits = types.strict },
    .{ .name = "byte", .bits = match.bits8 },
    .{ .name = "word", .bits = match.bits16 },
    .{ .name = "dword", .bits = match.bits32 },
    .{ .name = "qword", .bits = match.bits64 },
    .{ .name = "tword", .bits = match.bits80 },
    .{ .name = "oword", .bits = match.bits128 },
    .{ .name = "xword", .bits = match.bits128 },
    .{ .name = "yword", .bits = match.bits256 },
    .{ .name = "zword", .bits = match.bits512 },
    .{ .name = "near", .bits = match.near },
    .{ .name = "far", .bits = match.far },
    .{ .name = "short", .bits = match.short },
    .{ .name = "abs", .bits = match.abs },
};

fn stripOperandQualifiers(text: []const u8) EncodeError!QualifiedOperandText {
    var qualifiers: OperandQualifiers = .{};
    var rest = std.mem.trim(u8, text, " \t\r\n");

    while (true) {
        const token_end = firstWhitespace(rest) orelse break;
        const head = rest[0..token_end];
        const tail = std.mem.trim(u8, rest[token_end..], " \t\r\n");

        if (std.ascii.eqlIgnoreCase(head, "rel")) {
            qualifiers.opflags |= types.opflag_relative;
            qualifiers.eaflags |= ea.eaf_rel;
            rest = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "ptr")) {
            rest = tail;
            continue;
        }
        if (operandQualifierPrefix(head)) |prefix| {
            qualifiers.type_bits |= prefix.bits;
            rest = tail;
            continue;
        }
        break;
    }

    if (rest.len == 0) return error.UnsupportedOperandSyntax;
    return .{
        .qualifiers = qualifiers,
        .core = rest,
    };
}

fn firstWhitespace(text: []const u8) ?usize {
    for (text, 0..) |char, index| {
        if (std.ascii.isWhitespace(char)) return index;
    }
    return null;
}

fn operandQualifierPrefix(token: []const u8) ?OperandQualifierPrefix {
    for (operand_qualifier_prefixes) |prefix| {
        if (std.ascii.eqlIgnoreCase(token, prefix.name)) return prefix;
    }
    return null;
}

fn applyOperandQualifiers(operand: match.Operand, qualifiers: OperandQualifiers) match.Operand {
    var result = operand;
    result.type_bits |= qualifiers.type_bits;
    result.opflags |= qualifiers.opflags;
    result.eaflags |= qualifiers.eaflags;
    return result;
}

fn applyOperandQualifierInstructionEffects(ins: *match.Instruction, qualifiers: OperandQualifiers) void {
    if ((qualifiers.type_bits & (match.near | match.short)) != 0) {
        ins.opt |= types.optim_no_jcc_relax | types.optim_no_jmp_relax;
    }
}

fn automaticBranchRelaxationCandidate(ins: *const match.Instruction) bool {
    if (ins.operands != 1) return false;
    if (!match.opcodeHasRelaxTemplate(ins.opcode)) return false;

    const operand = ins.oprs[0];
    if (operand.kind != .immediate) return false;
    if ((operand.type_bits & (match.near | match.short | match.far | types.strict)) != 0) return false;
    return true;
}

fn applyMemoryParserFlags(operand: match.Operand) match.Operand {
    var result = operand;
    const operand_size_bits = result.type_bits & match.size_mask;
    if (operand_size_bits == 0 or operand_size_bits == match.bits16) {
        result.type_bits |= match.rm_sel;
    }
    return result;
}

fn splitOperandDecorators(text: []const u8) EncodeError!DecoratedOperandText {
    var bracket_depth: i32 = 0;
    for (text, 0..) |char, index| {
        switch (char) {
            '[' => bracket_depth += 1,
            ']' => {
                bracket_depth -= 1;
                if (bracket_depth < 0) return error.UnsupportedOperandSyntax;
            },
            '{' => {
                if (bracket_depth == 0) {
                    return .{
                        .core = std.mem.trim(u8, text[0..index], " \t\r\n"),
                        .decorations = std.mem.trim(u8, text[index..], " \t\r\n"),
                    };
                }
            },
            else => {},
        }
    }
    if (bracket_depth != 0) return error.UnsupportedOperandSyntax;
    return .{
        .core = std.mem.trim(u8, text, " \t\r\n"),
        .decorations = "",
    };
}

fn parseDecoratorSuffix(text: []const u8) EncodeError!u16 {
    var decoflags: u16 = 0;
    var rest = std.mem.trim(u8, text, " \t\r\n");
    while (rest.len != 0) {
        if (!std.mem.startsWith(u8, rest, "{")) return error.UnsupportedOperandSyntax;
        const end = std.mem.indexOfScalar(u8, rest, '}') orelse return error.UnsupportedOperandSyntax;
        const inner = std.mem.trim(u8, rest[1..end], " \t\r\n");
        if (inner.len == 0) return error.UnsupportedOperandSyntax;
        try applySuffixDecorator(&decoflags, inner);
        rest = std.mem.trim(u8, rest[end + 1 ..], " \t\r\n");
    }
    return decoflags;
}

fn applySuffixDecorator(decoflags: *u16, inner: []const u8) EncodeError!void {
    if (std.ascii.eqlIgnoreCase(inner, "z")) {
        decoflags.* |= types.z_mask;
        return;
    }
    if (std.ascii.eqlIgnoreCase(inner, "1to2")) {
        decoflags.* |= types.brdcast_mask;
        decoflags.* &= ~types.brnum_mask;
        return;
    }
    if (std.ascii.eqlIgnoreCase(inner, "1to4")) {
        decoflags.* |= types.brdcast_mask;
        decoflags.* = (decoflags.* & ~types.brnum_mask) | (@as(u16, 1) << @intCast(types.brnum_shift));
        return;
    }
    if (std.ascii.eqlIgnoreCase(inner, "1to8")) {
        decoflags.* |= types.brdcast_mask;
        decoflags.* = (decoflags.* & ~types.brnum_mask) | (@as(u16, 2) << @intCast(types.brnum_shift));
        return;
    }
    if (std.ascii.eqlIgnoreCase(inner, "1to16")) {
        decoflags.* |= types.brdcast_mask;
        decoflags.* = (decoflags.* & ~types.brnum_mask) | (@as(u16, 3) << @intCast(types.brnum_shift));
        return;
    }
    if (std.ascii.eqlIgnoreCase(inner, "1to32")) {
        decoflags.* |= types.brdcast_mask;
        decoflags.* = (decoflags.* & ~types.brnum_mask) | (@as(u16, 4) << @intCast(types.brnum_shift));
        return;
    }
    if (try parseOpmaskDecorator(inner)) |mask| {
        decoflags.* = (decoflags.* & ~types.opmask_mask) | mask;
        return;
    }
    return error.UnsupportedOperandSyntax;
}

fn parseOpmaskDecorator(text: []const u8) EncodeError!?u16 {
    if (text.len < 2 or (text[0] != 'k' and text[0] != 'K')) return null;
    const register = tables.registerByName(text) orelse return error.UnsupportedOperandSyntax;
    if ((register.flags & match.reg_class_opmask) == 0) return error.UnsupportedOperandSyntax;
    const index = std.fmt.parseInt(u16, text[1..], 10) catch return error.UnsupportedOperandSyntax;
    return index & types.opmask_mask;
}

fn parseStandaloneDecoratorOperand(decorations: []const u8) EncodeError!ErSaeDecorator {
    var rest = std.mem.trim(u8, decorations, " \t\r\n");
    var evex_rm: ?i32 = null;
    var decoflags: u16 = 0;

    while (rest.len != 0) {
        if (!std.mem.startsWith(u8, rest, "{")) return error.UnsupportedOperandSyntax;
        const end = std.mem.indexOfScalar(u8, rest, '}') orelse return error.UnsupportedOperandSyntax;
        const inner = std.mem.trim(u8, rest[1..end], " \t\r\n");
        const current: ?i32 = if (std.ascii.eqlIgnoreCase(inner, "rn-sae"))
            brc_rn
        else if (std.ascii.eqlIgnoreCase(inner, "rd-sae"))
            brc_rd
        else if (std.ascii.eqlIgnoreCase(inner, "ru-sae"))
            brc_ru
        else if (std.ascii.eqlIgnoreCase(inner, "rz-sae"))
            brc_rz
        else if (std.ascii.eqlIgnoreCase(inner, "sae"))
            brc_sae
        else
            null;
        const value = current orelse return error.UnsupportedOperandSyntax;
        if (evex_rm != null) return error.UnsupportedOperandSyntax;
        evex_rm = value;
        decoflags |= if (value == brc_sae) types.sae_mask else types.staticrnd_mask;
        rest = std.mem.trim(u8, rest[end + 1 ..], " \t\r\n");
    }

    return .{
        .evex_rm = evex_rm orelse return error.UnsupportedOperandSyntax,
        .decoflags = decoflags,
    };
}

fn applyDecoFlags(operand: match.Operand, decoflags: u16) match.Operand {
    var result = operand;
    result.decoflags |= decoflags;
    return result;
}

fn resolveExpressionOperand(resolver: ?ExpressionResolver, text: []const u8) ExpressionResolveError!?ResolvedExpr {
    const active = resolver orelse return null;
    return active.resolve(text);
}

fn registerOperand(register: tables.RegisterInfo) match.Operand {
    return .{
        .kind = .register,
        .type_bits = @intCast(register.flags),
        .basereg = register.expr_reg,
    };
}

fn registerOperandFromCore(core: []const u8) EncodeError!?match.Operand {
    if (tables.registerByName(core)) |register| {
        return registerOperand(register);
    }

    const split = splitTopLevelDelimiter(core, '+') orelse return null;
    const lhs = std.mem.trim(u8, split.left, " \t\r\n");
    const rhs = std.mem.trim(u8, split.right, " \t\r\n");
    const register = tables.registerByName(lhs) orelse return null;
    const delta = (try parseIntLiteralForEncode(rhs)) orelse return error.UnsupportedOperandSyntax;

    var operand = registerOperand(register);
    operand.type_bits |= try registerSetFlagFromDelta(delta);
    return operand;
}

fn registerSetFlagFromDelta(delta: i64) EncodeError!u64 {
    if (delta < 0) return error.UnsupportedOperandSyntax;
    const regset_size_i64 = @addWithOverflow(delta, 1);
    if (regset_size_i64[1] != 0) return error.IntegerOverflow;
    const regset_size: u64 = @intCast(regset_size_i64[0]);
    if (regset_size == 0 or
        (regset_size & (regset_size - 1)) != 0 or
        regset_size >= (@as(u64, 1) << @intCast(types.regset_bits)))
    {
        return error.UnsupportedOperandSyntax;
    }
    return (regset_size >> 1) << @intCast(types.regset_shift);
}

fn isClass(class: u64, op: u64) bool {
    return (class & ~op) == 0;
}

fn applyMemoryRegisterFlags(operand: *match.Operand, register_flags: u64) void {
    operand.type_bits &= register_flags | ~match.rn_l16;
}

fn applyMemoryIndexFlags(operand: *match.Operand, register_flags: u64) void {
    if (isClass(match.reg_class_rm_xmm, register_flags)) {
        operand.type_bits |= match.xmem;
    } else if (isClass(match.reg_class_rm_ymm, register_flags)) {
        operand.type_bits |= match.ymem;
    } else if (isClass(match.reg_class_rm_zmm, register_flags)) {
        operand.type_bits |= match.zmem;
    }
}

fn parseMemoryText(ins: *match.Instruction, text: []const u8, resolver: ?ExpressionResolver) EncodeError!?match.Operand {
    if (std.mem.startsWith(u8, text, "[") and std.mem.endsWith(u8, text, "]")) {
        const inner = std.mem.trim(u8, text[1 .. text.len - 1], " \t\r\n");
        if (inner.len == 0) return error.UnsupportedOperandSyntax;
        return try parseBracketedMemoryOperand(ins, inner, resolver);
    }

    const split = try splitSegmentOverride(text) orelse return null;
    if (!std.mem.startsWith(u8, split.rest, "[") or !std.mem.endsWith(u8, split.rest, "]")) {
        return error.UnsupportedOperandSyntax;
    }
    const inner = std.mem.trim(u8, split.rest[1 .. split.rest.len - 1], " \t\r\n");
    if (inner.len == 0) return error.UnsupportedOperandSyntax;
    try applySegmentOverride(ins, split.register);
    return try parseMemoryOperand(inner, resolver);
}

fn parseBracketedMemoryOperand(ins: *match.Instruction, inner: []const u8, resolver: ?ExpressionResolver) EncodeError!match.Operand {
    if (try splitSegmentOverride(inner)) |split| {
        try applySegmentOverride(ins, split.register);
        return parseEffectiveAddressMemoryOperand(ins, split.rest, resolver);
    }
    return parseEffectiveAddressMemoryOperand(ins, inner, resolver);
}

fn parseEffectiveAddressMemoryOperand(ins: *match.Instruction, text: []const u8, resolver: ?ExpressionResolver) EncodeError!match.Operand {
    const qualified = try stripEffectiveAddressQualifiers(text);
    try applyAddressSizeOverride(ins, qualified.address_prefix);
    var operand = try parseMemoryOperand(qualified.core, resolver);
    operand.eaflags |= qualified.eaflags;
    if (qualified.disp_size != 0) operand.disp_size = qualified.disp_size;
    return operand;
}

const EffectiveAddressQualifiers = struct {
    core: []const u8,
    eaflags: i32 = 0,
    disp_size: u8 = 0,
    address_prefix: i32 = match.p_none,
};

fn stripEffectiveAddressQualifiers(text: []const u8) EncodeError!EffectiveAddressQualifiers {
    var result: EffectiveAddressQualifiers = .{ .core = std.mem.trim(u8, text, " \t\r\n") };

    while (true) {
        const token_end = firstWhitespace(result.core) orelse break;
        const head = result.core[0..token_end];
        const tail = std.mem.trim(u8, result.core[token_end..], " \t\r\n");

        if (std.ascii.eqlIgnoreCase(head, "ptr")) {
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "nosplit")) {
            result.eaflags |= ea.eaf_timestwo;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "rel")) {
            result.eaflags |= ea.eaf_rel;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "abs")) {
            result.eaflags |= ea.eaf_abs;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "byte")) {
            result.disp_size = 8;
            result.eaflags |= ea.eaf_byteoffs;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "word")) {
            result.disp_size = 16;
            result.eaflags |= ea.eaf_wordoffs;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "dword") or std.ascii.eqlIgnoreCase(head, "long")) {
            result.disp_size = 32;
            result.eaflags |= ea.eaf_wordoffs;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "qword")) {
            result.disp_size = 64;
            result.eaflags |= ea.eaf_wordoffs;
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "a16")) {
            result.address_prefix = try mergeAddressPrefix(result.address_prefix, match.p_a16);
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "a32")) {
            result.address_prefix = try mergeAddressPrefix(result.address_prefix, match.p_a32);
            result.core = tail;
            continue;
        }
        if (std.ascii.eqlIgnoreCase(head, "a64")) {
            result.address_prefix = try mergeAddressPrefix(result.address_prefix, match.p_a64);
            result.core = tail;
            continue;
        }
        break;
    }

    if (result.core.len == 0) return error.UnsupportedOperandSyntax;
    return result;
}

fn mergeAddressPrefix(current: i32, next: i32) EncodeError!i32 {
    if (current != match.p_none and current != next) return error.UnsupportedPrefixes;
    return next;
}

const SegmentOverride = struct {
    register: tables.RegisterInfo,
    rest: []const u8,
};

fn splitSegmentOverride(text: []const u8) EncodeError!?SegmentOverride {
    const colon_index = std.mem.indexOfScalar(u8, text, ':') orelse return null;
    if (std.mem.indexOfScalar(u8, text[colon_index + 1 ..], ':') != null) {
        return error.UnsupportedOperandSyntax;
    }

    const raw_segment = std.mem.trim(u8, text[0..colon_index], " \t\r\n");
    const rest = std.mem.trim(u8, text[colon_index + 1 ..], " \t\r\n");
    if (raw_segment.len == 0 or rest.len == 0) return error.UnsupportedOperandSyntax;

    const register = tables.registerByName(raw_segment) orelse return error.UnsupportedOperandSyntax;
    if ((register.flags & match.reg_class_sreg) == 0) return error.UnsupportedOperandSyntax;
    return .{
        .register = register,
        .rest = rest,
    };
}

pub fn segmentPrefixValueByName(text: []const u8) error{UnsupportedOperandSyntax}!i32 {
    const raw_segment = std.mem.trim(u8, text, " \t\r\n");
    const register = tables.registerByName(raw_segment) orelse return error.UnsupportedOperandSyntax;
    if ((register.flags & match.reg_class_sreg) == 0) return error.UnsupportedOperandSyntax;
    return register.expr_reg;
}

fn applySegmentOverride(ins: *match.Instruction, register: tables.RegisterInfo) EncodeError!void {
    const slot = match.PrefixSlot.segment.index();
    const current = ins.prefixes[slot].raw();
    if (current != 0 and current != register.expr_reg) return error.UnsupportedPrefixes;
    ins.prefixes[slot] = .{ .value = register.expr_reg };
}

fn applyAddressSizeOverride(ins: *match.Instruction, prefix: i32) EncodeError!void {
    if (prefix == match.p_none) return;
    const slot = match.PrefixSlot.address_size.index();
    const current = ins.prefixes[slot].raw();
    if (current != match.p_none and current != prefix) return error.UnsupportedPrefixes;
    ins.prefixes[slot] = .{ .value = prefix };
}

fn setImmFlags(operand: *match.Operand, opt: u32) void {
    if ((operand.type_bits & match.immediate) == 0) return;

    const strict = (operand.type_bits & types.strict) != 0 or (opt & types.optim_strict_oper) != 0;
    if ((operand.opflags & types.opflag_unknown) != 0) {
        // Unknown values cannot safely select value-dependent short forms.
        // The final target may not preserve the sign-extension semantics used
        // by unity, four-bit, or sign-extended byte encodings.
        operand.type_bits |= match.imm_known;
        return;
    }

    if ((operand.opflags & types.opflag_simple) == 0) return;

    const value = operand.offset;
    operand.type_bits |= match.imm_known;
    if (!strict or (operand.type_bits & match.size_mask) == 0) {
        if (value == 1) operand.type_bits |= match.unity;
        if (value >= -16 and value <= 15) operand.type_bits |= match.fourbits;
    }
    if (strict) return;

    if (signExtendLowBits(value, 32) == signExtendLowBits(value, 8)) operand.type_bits |= match.sbytedword;
    if (signExtendLowBits(value, 16) == signExtendLowBits(value, 8)) operand.type_bits |= match.sbyteword;
    if (value >= 0 and value <= std.math.maxInt(u32)) {
        operand.type_bits |= match.udword;
    }
    if (value >= std.math.minInt(i32) and value <= std.math.maxInt(i32)) {
        operand.type_bits |= match.sdword_operand;
    }
}

fn signExtendLowBits(value: i64, comptime bits: u6) i64 {
    const mask = (@as(u64, 1) << bits) - 1;
    const sign = @as(u64, 1) << (bits - 1);
    const raw: u64 = @bitCast(value);
    const low = raw & mask;
    if ((low & sign) != 0) {
        const extended = low | ~mask;
        return @bitCast(extended);
    }
    return @intCast(low);
}

fn preferMemoryIndirectBranchForms(mnemonic: []const u8, ins: *match.Instruction) void {
    if (!std.ascii.eqlIgnoreCase(mnemonic, "call") and !std.ascii.eqlIgnoreCase(mnemonic, "jmp")) {
        return;
    }

    for (ins.oprs[0..ins.operands]) |*operand| {
        if (operand.kind != .memory) continue;

        if (ins.bits == 64 and
            operand.basereg == match.r_none and
            (operand.indexreg == match.r_none or operand.scale == 0) and
            (operand.eaflags & ea.eaf_abs) == 0 and
            (((operand.eaflags & ea.eaf_rel) != 0) or ins.default_rel))
        {
            operand.ip_relative = true;
        }

        operand.type_bits &= ~match.immediate;
    }
}

fn inferApxRaoUnsizedMemorySizeFromGprOperand(mnemonic: []const u8, ins: *match.Instruction) void {
    if (!isApxRaoMemoryRegisterMnemonic(mnemonic)) return;
    if (ins.operands != 2) return;

    const memory = &ins.oprs[0];
    const register = ins.oprs[1];
    if (memory.kind != .memory or register.kind != .register) return;
    if ((memory.type_bits & types.msize_mask) != 0) return;
    if (!isClass(match.reg_class_gpr, register.type_bits)) return;

    const register_size = register.type_bits & types.msize_mask;
    if (register_size != match.bits32 and register_size != match.bits64) return;
    memory.type_bits |= register_size;
}

fn isApxRaoMemoryRegisterMnemonic(mnemonic: []const u8) bool {
    return std.ascii.eqlIgnoreCase(mnemonic, "aadd") or
        std.ascii.eqlIgnoreCase(mnemonic, "aand") or
        std.ascii.eqlIgnoreCase(mnemonic, "aor") or
        std.ascii.eqlIgnoreCase(mnemonic, "axor");
}

fn parseMemoryOperand(inner: []const u8, resolver: ?ExpressionResolver) EncodeError!match.Operand {
    if (tables.registerByName(inner)) |register| {
        const register_flags: u64 = @intCast(register.flags);
        var operand = registerOperand(register);
        operand.kind = .memory;
        operand.type_bits = match.memory_any;
        if (isClass(match.reg_gpr, register_flags)) {
            applyMemoryRegisterFlags(&operand, register_flags);
        } else {
            operand.basereg = match.r_none;
            operand.indexreg = register.expr_reg;
            operand.scale = 1;
            applyMemoryRegisterFlags(&operand, register_flags);
            applyMemoryIndexFlags(&operand, register_flags);
        }
        return operand;
    }
    if (try parseIntLiteralForEncode(inner)) |value| {
        return .{
            .kind = .memory,
            .type_bits = match.memory_any | match.immediate | match.mem_offs,
            .basereg = match.r_none,
            .offset = value,
        };
    }
    if (splitTopLevelComma(inner)) |split| {
        return parseSplitEffectiveAddressOperand(split.left, split.right, resolver);
    }

    var index: usize = 0;
    var base: ?tables.RegisterInfo = null;
    var index_register: ?tables.RegisterInfo = null;
    var scale: i32 = 0;
    var offset: i64 = 0;
    var memory_opflags: i32 = 0;
    var memory_symbolic = false;
    var saw_term = false;
    var pending_sign: i8 = 1;

    while (index < inner.len) {
        while (index < inner.len and std.ascii.isWhitespace(inner[index])) index += 1;
        if (index >= inner.len) break;

        if (inner[index] == '+') {
            pending_sign = 1;
            index += 1;
            continue;
        }
        if (inner[index] == '-') {
            pending_sign = -1;
            index += 1;
            continue;
        }

        const start = index;
        index = try memoryTermEnd(inner, index);
        const term = std.mem.trim(u8, inner[start..index], " \t\r\n");
        if (term.len == 0) return error.UnsupportedOperandSyntax;

        if (try parseMemoryRegisterTerm(term)) |register_term| {
            if (pending_sign < 0) return error.UnsupportedOperandSyntax;
            const register_flags: u64 = @intCast(register_term.register.flags);
            if (register_term.scale != 0) {
                if (index_register != null) return error.UnsupportedOperandSyntax;
                if (isRspIndexRegister(register_term.register)) return error.InvalidRspIndexRegister;
                index_register = register_term.register;
                scale = register_term.scale;
            } else if (!isClass(match.reg_gpr, register_flags)) {
                if (index_register != null) return error.UnsupportedOperandSyntax;
                index_register = register_term.register;
                scale = 1;
            } else if (base == null) {
                base = register_term.register;
            } else if (index_register == null) {
                index_register = register_term.register;
                scale = 1;
            } else {
                return error.UnsupportedOperandSyntax;
            }
            saw_term = true;
        } else if (try parseIntLiteralForEncode(term)) |value| {
            offset = try applySignedOffsetTerm(offset, value, pending_sign);
            saw_term = true;
        } else if (try resolveExpressionOperand(resolver, term)) |resolved| {
            offset = try applySignedOffsetTerm(offset, resolved.value, pending_sign);
            if (!resolved.known) memory_opflags |= types.opflag_unknown;
            if (resolved.symbolic) memory_symbolic = true;
            saw_term = true;
        } else {
            return error.UnsupportedOperandSyntax;
        }
        pending_sign = 1;
    }

    if (!saw_term) return error.UnsupportedOperandSyntax;
    if (base != null or index_register != null) {
        var operand: match.Operand = .{
            .kind = .memory,
            .type_bits = match.memory_any,
            .basereg = if (base) |register| register.expr_reg else match.r_none,
            .indexreg = if (index_register) |index_reg| index_reg.expr_reg else match.r_none,
            .scale = scale,
            .offset = offset,
            .opflags = memory_opflags,
            .symbolic = memory_symbolic,
        };
        if (base) |register| {
            applyMemoryRegisterFlags(&operand, @intCast(register.flags));
        }
        if (index_register) |register| {
            applyMemoryRegisterFlags(&operand, @intCast(register.flags));
            applyMemoryIndexFlags(&operand, @intCast(register.flags));
        }
        return operand;
    }
    const operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory_any | match.immediate | match.mem_offs,
        .basereg = match.r_none,
        .indexreg = if (index_register) |index_reg| index_reg.expr_reg else match.r_none,
        .scale = scale,
        .offset = offset,
        .opflags = memory_opflags,
        .symbolic = memory_symbolic,
    };
    return operand;
}

fn isRspIndexRegister(register: tables.RegisterInfo) bool {
    return std.ascii.eqlIgnoreCase(register.name, "rsp") or
        std.ascii.eqlIgnoreCase(register.name, "esp") or
        std.ascii.eqlIgnoreCase(register.name, "sp");
}

fn memoryTermEnd(text: []const u8, start: usize) EncodeError!usize {
    var index = start;
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    var quote: u8 = 0;
    while (index < text.len) : (index += 1) {
        const ch = text[index];
        if (quote != 0) {
            if (ch == quote) quote = 0;
            continue;
        }
        switch (ch) {
            '\'', '"' => quote = ch,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth == 0) return error.UnsupportedOperandSyntax;
                paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth == 0) return error.UnsupportedOperandSyntax;
                bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth == 0) return error.UnsupportedOperandSyntax;
                brace_depth -= 1;
            },
            '+', '-' => {
                if (paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) return index;
            },
            else => {},
        }
    }
    if (paren_depth != 0 or bracket_depth != 0 or brace_depth != 0 or quote != 0) {
        return error.UnsupportedOperandSyntax;
    }
    return index;
}

const SplitEffectiveAddress = struct {
    left: []const u8,
    right: []const u8,
};

fn splitTopLevelComma(text: []const u8) ?SplitEffectiveAddress {
    return splitTopLevelDelimiter(text, ',');
}

fn splitTopLevelDelimiter(text: []const u8, delimiter: u8) ?SplitEffectiveAddress {
    var paren_depth: usize = 0;
    var bracket_depth: usize = 0;
    var brace_depth: usize = 0;
    var quote: u8 = 0;
    var index: usize = 0;
    while (index < text.len) : (index += 1) {
        const ch = text[index];
        if (quote != 0) {
            if (ch == quote) quote = 0;
            continue;
        }
        if (ch == delimiter and paren_depth == 0 and bracket_depth == 0 and brace_depth == 0) {
            const left = std.mem.trim(u8, text[0..index], " \t\r\n");
            const right = std.mem.trim(u8, text[index + 1 ..], " \t\r\n");
            if (left.len == 0 or right.len == 0) return null;
            if (std.mem.indexOfScalar(u8, right, delimiter) != null) return null;
            return .{ .left = left, .right = right };
        }
        switch (ch) {
            '\'', '"' => quote = ch,
            '(' => paren_depth += 1,
            ')' => {
                if (paren_depth > 0) paren_depth -= 1;
            },
            '[' => bracket_depth += 1,
            ']' => {
                if (bracket_depth > 0) bracket_depth -= 1;
            },
            '{' => brace_depth += 1,
            '}' => {
                if (brace_depth > 0) brace_depth -= 1;
            },
            else => {},
        }
    }
    return null;
}

fn parseSplitEffectiveAddressOperand(
    left: []const u8,
    right: []const u8,
    resolver: ?ExpressionResolver,
) EncodeError!match.Operand {
    var operand = try parseMemoryOperand(left, resolver);
    var index_operand = try parseMemoryOperand(right, resolver);

    if (index_operand.basereg != match.r_none and index_operand.indexreg == match.r_none) {
        index_operand.indexreg = index_operand.basereg;
        index_operand.scale = 1;
        index_operand.basereg = match.r_none;
    }
    if (operand.indexreg != match.r_none or
        index_operand.basereg != match.r_none or
        index_operand.indexreg == match.r_none or
        index_operand.offset != 0 or
        index_operand.segment != match.no_seg or
        index_operand.wrt != match.no_seg or
        index_operand.symbolic)
    {
        return error.UnsupportedOperandSyntax;
    }

    operand.indexreg = index_operand.indexreg;
    operand.scale = index_operand.scale;
    operand.opflags |= index_operand.opflags;
    operand.type_bits |= index_operand.type_bits & (match.xmem | match.ymem | match.zmem);
    if (operand.basereg != match.r_none) {
        operand.hintbase = operand.basereg;
        operand.hinttype = ea.eah_makebase;
    } else if (operand.indexreg != match.r_none) {
        operand.hintbase = operand.indexreg;
        operand.hinttype = ea.eah_notbase;
    } else {
        operand.hintbase = match.r_none;
        operand.hinttype = types.eah_nohint;
    }
    return operand;
}

const MemoryRegisterTerm = struct {
    register: tables.RegisterInfo,
    scale: i32 = 0,
};

fn parseMemoryRegisterTerm(term: []const u8) EncodeError!?MemoryRegisterTerm {
    if (tables.registerByName(term)) |register| {
        return .{ .register = register };
    }

    const star_index = std.mem.indexOfScalar(u8, term, '*') orelse return null;
    if (std.mem.indexOfScalar(u8, term[star_index + 1 ..], '*') != null) {
        return error.UnsupportedOperandSyntax;
    }

    const lhs = std.mem.trim(u8, term[0..star_index], " \t\r\n");
    const rhs = std.mem.trim(u8, term[star_index + 1 ..], " \t\r\n");
    if (lhs.len == 0 or rhs.len == 0) return error.UnsupportedOperandSyntax;

    if (tables.registerByName(lhs)) |register| {
        const parsed_scale = try parseMemoryScale(rhs);
        return .{ .register = register, .scale = parsed_scale };
    }
    if (tables.registerByName(rhs)) |register| {
        const parsed_scale = try parseMemoryScale(lhs);
        return .{ .register = register, .scale = parsed_scale };
    }
    return null;
}

fn parseMemoryScale(text: []const u8) EncodeError!i32 {
    const value = (try parseIntLiteralForEncode(text)) orelse return error.UnsupportedOperandSyntax;
    return switch (value) {
        1, 2, 4, 8 => @intCast(value),
        else => error.InvalidMemoryScale,
    };
}

fn applySignedOffsetTerm(current: i64, value: i64, sign: i8) EncodeError!i64 {
    const signed_value = if (sign < 0) blk: {
        const result = @subWithOverflow(@as(i64, 0), value);
        if (result[1] != 0) return error.IntegerOverflow;
        break :blk result[0];
    } else value;
    const result = @addWithOverflow(current, signed_value);
    if (result[1] != 0) return error.IntegerOverflow;
    return result[0];
}

pub fn materializeOutput(
    allocator: Allocator,
    units: []const EncodeUnit,
) MaterializeError![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    for (units) |unit| {
        if (unit.reserve_len != 0) return error.UnsupportedReserve;
        if (unit.fixup) |fixup| {
            const bytes = try materializeFixup(allocator, fixup);
            defer if (bytes.len > 0) allocator.free(bytes);
            try out.appendSlice(allocator, bytes);
        } else {
            try out.appendSlice(allocator, unit.bytes);
        }
    }

    return out.toOwnedSlice(allocator);
}

pub fn materializeFixup(allocator: Allocator, fixup: Fixup) MaterializeError![]u8 {
    if (fixup.tsegment != match.no_seg or fixup.twrt != match.no_seg) return error.UnresolvedFixup;

    const value = switch (fixup.kind) {
        .absolute => fixup.toffset,
        .relative => value: {
            const relative_value = std.math.sub(i64, fixup.toffset, fixup.relbase) catch return error.RelativeFixupOverflow;
            try validateRelativeFixupRange(relative_value, fixup.size);
            break :value relative_value;
        },
        .segment => return error.UnsupportedSegmentFixup,
    };
    return emitMaterializedValueBytes(allocator, value, fixup.size);
}

fn validateRelativeFixupRange(value: i64, byte_size: u8) MaterializeError!void {
    switch (byte_size) {
        1 => if (value < std.math.minInt(i8) or value > std.math.maxInt(i8)) return error.RelativeFixupOverflow,
        2 => if (value < std.math.minInt(i16) or value > std.math.maxInt(i16)) return error.RelativeFixupOverflow,
        4 => if (value < std.math.minInt(i32) or value > std.math.maxInt(i32)) return error.RelativeFixupOverflow,
        8 => {},
        else => return error.InvalidFixupSize,
    }
}

fn emitMaterializedValueBytes(allocator: Allocator, value: i64, byte_size: u8) MaterializeError![]u8 {
    if (byte_size == 0 or byte_size > 8) return error.InvalidFixupSize;
    const len: usize = byte_size;
    const bytes = try allocator.alloc(u8, len);
    errdefer if (bytes.len > 0) allocator.free(bytes);

    const raw: u64 = @bitCast(value);
    for (bytes, 0..) |*byte, index| {
        const shift: u6 = @intCast(index * 8);
        byte.* = @intCast((raw >> shift) & 0xff);
    }
    return bytes;
}

const IntegerLiteral = union(enum) {
    none,
    invalid,
    decimal: []const u8,
    hex: []const u8,
};

fn parseIntLiteralForEncode(text: []const u8) EncodeError!?i64 {
    if (std.mem.startsWith(u8, text, "~")) {
        const inner = std.mem.trim(u8, text[1..], " \t\r\n");
        const value = (try parseIntLiteralForEncode(inner)) orelse return null;
        const raw: u64 = @bitCast(value);
        return @bitCast(~raw);
    }
    if (parseQuotedLiteralWord(text)) |value| return value;
    return switch (classifyIntegerLiteral(text)) {
        .none => null,
        .invalid => error.InvalidIntegerLiteral,
        .decimal => |digits| try parseClassifiedInt(digits, 10),
        .hex => |digits| try parseClassifiedInt(digits, 16),
    };
}

fn parseIntLiteral(text: []const u8) ?i64 {
    if (std.mem.startsWith(u8, text, "~")) {
        const inner = std.mem.trim(u8, text[1..], " \t\r\n");
        const value = parseIntLiteral(inner) orelse return null;
        const raw: u64 = @bitCast(value);
        return @bitCast(~raw);
    }
    if (parseQuotedLiteralWord(text)) |value| return value;
    return switch (classifyIntegerLiteral(text)) {
        .none, .invalid => null,
        .decimal => |digits| parseClassifiedInt(digits, 10) catch null,
        .hex => |digits| parseClassifiedInt(digits, 16) catch null,
    };
}

fn parseQuotedLiteralWord(text: []const u8) ?i64 {
    if (text.len < 2) return null;
    const quote = text[0];
    if (quote != '\'' and quote != '"') return null;
    if (text[text.len - 1] != quote) return null;

    var value: usize = 0;
    var index: usize = 1;
    var output_index: usize = 0;
    while (index < text.len - 1 and output_index < @sizeOf(usize)) : (output_index += 1) {
        const byte = text[index];
        if (byte == quote and index + 1 < text.len - 1 and text[index + 1] == quote) {
            value +%= @as(usize, quote) << wordShift(output_index);
            index += 2;
            continue;
        }

        value +%= @as(usize, byte) << wordShift(output_index);
        index += 1;
    }
    return wordToI64(value);
}

fn wordShift(index: usize) std.math.Log2Int(usize) {
    return @intCast(index * 8);
}

fn wordToI64(value: usize) i64 {
    if (@bitSizeOf(usize) == 64) {
        return @bitCast(@as(u64, value));
    }
    return @intCast(value);
}

fn classifyIntegerLiteral(text: []const u8) IntegerLiteral {
    if (text.len == 0) return .none;

    var start: usize = 0;
    if (text[0] == '+' or text[0] == '-') {
        if (text.len == 1) return .invalid;
        start = 1;
    }

    if (std.mem.startsWith(u8, text[start..], "0x") or std.mem.startsWith(u8, text[start..], "0X")) {
        const digits_start = start + 2;
        return if (digits_start < text.len and allHexDigits(text[digits_start..]))
            .{ .hex = text }
        else
            .invalid;
    }
    if (std.mem.endsWith(u8, text, "h") or std.mem.endsWith(u8, text, "H")) {
        if (text.len - start == 1) return .none;
        if (!std.ascii.isDigit(text[start])) return .none;
        const digits = text[start .. text.len - 1];
        return if (allHexDigits(digits)) .{ .hex = text } else .invalid;
    }

    return if (allDecimalDigits(text[start..])) .{ .decimal = text } else .none;
}

fn parseClassifiedInt(text: []const u8, radix: u8) EncodeError!i64 {
    if (text.len == 0) return error.InvalidIntegerLiteral;
    var index: usize = 0;
    const negative = text[0] == '-';
    if (text[0] == '+' or text[0] == '-') index = 1;
    if (radix == 16 and index + 2 <= text.len and
        (std.mem.startsWith(u8, text[index..], "0x") or std.mem.startsWith(u8, text[index..], "0X")))
    {
        index += 2;
    }
    const end = if (radix == 16 and (std.mem.endsWith(u8, text, "h") or std.mem.endsWith(u8, text, "H")))
        text.len - 1
    else
        text.len;
    if (index >= end) return error.InvalidIntegerLiteral;

    var raw: u64 = 0;
    var saw_digit = false;
    while (index < end) : (index += 1) {
        const char = text[index];
        if (char == '_') continue;
        const digit = std.fmt.charToDigit(char, radix) catch return error.InvalidIntegerLiteral;
        if (radix == 16 and !negative) {
            raw = raw *% @as(u64, radix);
            raw = raw +% @as(u64, digit);
        } else {
            raw = std.math.mul(u64, raw, radix) catch return error.IntegerOverflow;
            raw = std.math.add(u64, raw, digit) catch return error.IntegerOverflow;
        }
        saw_digit = true;
    }
    if (!saw_digit) return error.InvalidIntegerLiteral;

    if (negative) {
        const limit = @as(u64, std.math.maxInt(i64)) + 1;
        if (raw > limit) return error.IntegerOverflow;
        if (raw == limit) return std.math.minInt(i64);
        const positive: i64 = @intCast(raw);
        return -positive;
    }
    if (radix == 10 and raw > std.math.maxInt(i64)) return error.IntegerOverflow;
    if (raw <= std.math.maxInt(i64)) return @intCast(raw);
    return @bitCast(raw);
}

fn allDecimalDigits(text: []const u8) bool {
    var saw_digit = false;
    for (text) |char| {
        if (char == '_') continue;
        if (!std.ascii.isDigit(char)) return false;
        saw_digit = true;
    }
    return saw_digit;
}

fn allHexDigits(text: []const u8) bool {
    var saw_digit = false;
    for (text) |char| {
        if (char == '_') continue;
        if (!std.ascii.isHex(char)) return false;
        saw_digit = true;
    }
    return saw_digit;
}

fn testUnknownExpressionResolver(context: *anyopaque, text: []const u8) ExpressionResolveError!?ResolvedExpr {
    if (@sizeOf(@TypeOf(context)) > 0 or text.len > 0) {}
    return .{
        .value = 0,
        .known = false,
        .current_known = false,
        .simple = false,
        .symbolic = true,
    };
}

fn testConstantExpressionResolver(context: *anyopaque, text: []const u8) ExpressionResolveError!?ResolvedExpr {
    if (@sizeOf(@TypeOf(context)) > 0) {}
    const trimmed = std.mem.trim(u8, text, " \t\r\n");
    if (std.mem.eql(u8, trimmed, "uptr * 2")) {
        return .{
            .value = 16,
            .known = true,
            .current_known = true,
            .simple = true,
            .symbolic = false,
        };
    }
    if (std.mem.eql(u8, trimmed, "4 * (STD_HASH_MAP_ENTRY_HEADER_SIZE + u64 + u64)")) {
        return .{
            .value = 128,
            .known = true,
            .current_known = true,
            .simple = true,
            .symbolic = false,
        };
    }
    if (std.mem.eql(u8, trimmed, "STD_HASH_MAP_ENTRY_HASH_OFFSET")) {
        return .{
            .value = 0,
            .known = true,
            .current_known = true,
            .simple = true,
            .symbolic = false,
        };
    }
    return null;
}

fn testRelativeFixup(delta: i64, byte_size: u8) Fixup {
    return .{
        .kind = .relative,
        .size = byte_size,
        .flags = 0,
        .toffset = delta,
        .tsegment = match.no_seg,
        .twrt = match.no_seg,
        .relbase = 0,
    };
}

test "materializeFixup validates relative width boundaries before emission" {
    const testing = std.testing;

    const legal_cases = [_]struct {
        size: u8,
        delta: i64,
        expected: []const u8,
    }{
        .{ .size = 1, .delta = -128, .expected = &.{0x80} },
        .{ .size = 1, .delta = 127, .expected = &.{0x7F} },
        .{ .size = 2, .delta = -32768, .expected = &.{ 0x00, 0x80 } },
        .{ .size = 2, .delta = 32767, .expected = &.{ 0xFF, 0x7F } },
        .{ .size = 4, .delta = -2147483648, .expected = &.{ 0x00, 0x00, 0x00, 0x80 } },
        .{ .size = 4, .delta = 2147483647, .expected = &.{ 0xFF, 0xFF, 0xFF, 0x7F } },
    };
    for (legal_cases) |case| {
        const bytes = try materializeFixup(testing.allocator, testRelativeFixup(case.delta, case.size));
        defer testing.allocator.free(bytes);
        try testing.expectEqualSlices(u8, case.expected, bytes);
    }

    const overflow_cases = [_]struct {
        size: u8,
        delta: i64,
    }{
        .{ .size = 1, .delta = 128 },
        .{ .size = 1, .delta = -129 },
        .{ .size = 2, .delta = 32768 },
        .{ .size = 2, .delta = -32769 },
        .{ .size = 4, .delta = 2147483648 },
        .{ .size = 4, .delta = -2147483649 },
    };
    for (overflow_cases) |case| {
        try testing.expectError(
            error.RelativeFixupOverflow,
            materializeFixup(testing.allocator, testRelativeFixup(case.delta, case.size)),
        );
    }
}

test "materializeFixup rejects zero-width absolute fixups" {
    const fixup: Fixup = .{
        .kind = .absolute,
        .size = 0,
        .flags = 0,
        .toffset = 0,
        .tsegment = match.no_seg,
        .twrt = match.no_seg,
        .relbase = 0,
    };
    try std.testing.expectError(
        error.InvalidFixupSize,
        materializeFixup(std.testing.allocator, fixup),
    );
}

test "encodeBuiltinUnits preserves current zero-operand batch bytes" {
    const testing = std.testing;

    var nop = try encodeBuiltinUnits(testing.allocator, "nop", &.{}, EncodeContext.init(64));
    defer nop.deinit(testing.allocator);
    const nop_bytes_owned = try materializeOutput(testing.allocator, nop.units());
    defer if (nop_bytes_owned.len > 0) testing.allocator.free(nop_bytes_owned);
    try testing.expectEqualSlices(u8, &.{0x90}, nop_bytes_owned);

    var ret = try encodeBuiltinUnits(testing.allocator, "RET", &.{}, EncodeContext.init(16));
    defer ret.deinit(testing.allocator);
    const ret_bytes_owned = try materializeOutput(testing.allocator, ret.units());
    defer if (ret_bytes_owned.len > 0) testing.allocator.free(ret_bytes_owned);
    try testing.expectEqualSlices(u8, &.{0xC3}, ret_bytes_owned);
}

test "encodeBuiltinUnits emits standalone x86 legacy prefixes through prefixByte" {
    const testing = std.testing;

    var rep = try encodeBuiltinUnits(testing.allocator, "rep", &.{}, EncodeContext.init(16));
    defer rep.deinit(testing.allocator);
    const rep_bytes = try materializeOutput(testing.allocator, rep.units());
    defer if (rep_bytes.len > 0) testing.allocator.free(rep_bytes);
    try testing.expectEqualSlices(u8, &.{0xF3}, rep_bytes);

    var o32 = try encodeBuiltinUnits(testing.allocator, "o32", &.{}, EncodeContext.init(16));
    defer o32.deinit(testing.allocator);
    const o32_bytes = try materializeOutput(testing.allocator, o32.units());
    defer if (o32_bytes.len > 0) testing.allocator.free(o32_bytes);
    try testing.expectEqualSlices(u8, &.{0x66}, o32_bytes);
}

test "encodeBuiltinUnits projects APX DFV prefix into x86 context state" {
    const testing = std.testing;

    var encoded = try encodeBuiltinUnits(testing.allocator, "nop", &.{}, EncodeContext.init(64).withApxDfv(1));
    defer encoded.deinit(testing.allocator);
    const bytes = try materializeOutput(testing.allocator, encoded.units());
    defer if (bytes.len > 0) testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &.{0x90}, bytes);
}

test "encodeBuiltinUnits projects x86 braced encoding prefixes into PPS_REX" {
    const testing = std.testing;

    var rex = try encodeBuiltinUnits(testing.allocator, "add", &.{ "eax", "edx" }, EncodeContext.init(64).withEncodingPrefix(.rex));
    defer rex.deinit(testing.allocator);
    const rex_bytes = try materializeOutput(testing.allocator, rex.units());
    defer if (rex_bytes.len > 0) testing.allocator.free(rex_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x40, 0x01, 0xD0 }, rex_bytes);

    var evex = try encodeBuiltinUnits(testing.allocator, "vcomisd", &.{ "xmm0", "xmm1" }, EncodeContext.init(64).withEncodingPrefix(.evex));
    defer evex.deinit(testing.allocator);
    const evex_bytes = try materializeOutput(testing.allocator, evex.units());
    defer if (evex_bytes.len > 0) testing.allocator.free(evex_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0xF1, 0xFD, 0x08, 0x2F, 0xC1 }, evex_bytes);
}

test "encodeBuiltinUnits projects x86 APX register-pair colon operands" {
    const testing = std.testing;

    var push_pair = try encodeBuiltinUnits(testing.allocator, "push", &.{"rax:rbx"}, EncodeContext.init(64));
    defer push_pair.deinit(testing.allocator);
    const push_pair_bytes = try materializeOutput(testing.allocator, push_pair.units());
    defer if (push_pair_bytes.len > 0) testing.allocator.free(push_pair_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0xF4, 0x7C, 0x18, 0xFF, 0xF3 }, push_pair_bytes);

    var pop_pair = try encodeBuiltinUnits(testing.allocator, "pop", &.{"rax:rbx"}, EncodeContext.init(64));
    defer pop_pair.deinit(testing.allocator);
    const pop_pair_bytes = try materializeOutput(testing.allocator, pop_pair.units());
    defer if (pop_pair_bytes.len > 0) testing.allocator.free(pop_pair_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0xF4, 0x64, 0x18, 0x8F, 0xC0 }, pop_pair_bytes);
}

test "encodeBuiltinUnits routes register operands through x86 encoder runtime pipeline" {
    const testing = std.testing;

    var encoded = try encodeBuiltinUnits(testing.allocator, "push", &.{"r8"}, EncodeContext.init(64));
    defer encoded.deinit(testing.allocator);

    const bytes = try materializeOutput(testing.allocator, encoded.units());
    defer if (bytes.len > 0) testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &.{ 0x41, 0x50 }, bytes);
}

test "encodeBuiltinUnits projects source-backed operand classes without instruction patches" {
    const testing = std.testing;

    var pop = try encodeBuiltinUnits(testing.allocator, "pop", &.{"r8"}, EncodeContext.init(64));
    defer pop.deinit(testing.allocator);
    const pop_bytes = try materializeOutput(testing.allocator, pop.units());
    defer if (pop_bytes.len > 0) testing.allocator.free(pop_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x41, 0x58 }, pop_bytes);

    var mov_reg = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "rbx" }, EncodeContext.init(64));
    defer mov_reg.deinit(testing.allocator);
    const mov_reg_bytes = try materializeOutput(testing.allocator, mov_reg.units());
    defer if (mov_reg_bytes.len > 0) testing.allocator.free(mov_reg_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x89, 0xD8 }, mov_reg_bytes);

    var mov_quoted_imm = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "edx", "'A'" }, EncodeContext.init(64));
    defer mov_quoted_imm.deinit(testing.allocator);
    const mov_quoted_imm_bytes = try materializeOutput(testing.allocator, mov_quoted_imm.units());
    defer if (mov_quoted_imm_bytes.len > 0) testing.allocator.free(mov_quoted_imm_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xBA, 0x41, 0x00, 0x00, 0x00 }, mov_quoted_imm_bytes);

    var mov_mem = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[rbx]" }, EncodeContext.init(64));
    defer mov_mem.deinit(testing.allocator);
    const mov_mem_bytes = try materializeOutput(testing.allocator, mov_mem.units());
    defer if (mov_mem_bytes.len > 0) testing.allocator.free(mov_mem_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x03 }, mov_mem_bytes);

    var add = try encodeBuiltinUnits(testing.allocator, "add", &.{ "rax", "1" }, EncodeContext.init(64));
    defer add.deinit(testing.allocator);
    const add_bytes = try materializeOutput(testing.allocator, add.units());
    defer if (add_bytes.len > 0) testing.allocator.free(add_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x83, 0xC0, 0x01 }, add_bytes);

    var jmp = try encodeBuiltinUnits(testing.allocator, "jmp", &.{"0"}, EncodeContext.init(64));
    defer jmp.deinit(testing.allocator);
    const jmp_bytes = try materializeOutput(testing.allocator, jmp.units());
    defer if (jmp_bytes.len > 0) testing.allocator.free(jmp_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xEB, 0xFE }, jmp_bytes);
}

test "encodeBuiltinUnits preserves x86 selector register templates" {
    const testing = std.testing;

    var lar = try encodeBuiltinUnits(testing.allocator, "lar", &.{ "ax", "bx" }, EncodeContext.init(64));
    defer lar.deinit(testing.allocator);
    const lar_bytes = try materializeOutput(testing.allocator, lar.units());
    defer if (lar_bytes.len > 0) testing.allocator.free(lar_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x66, 0x0F, 0x02, 0xC3 }, lar_bytes);
}

test "encodeBuiltinUnits projects simple memory expressions into x86 EA state" {
    const testing = std.testing;

    var pure_offset = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "cl", "[0x100]" }, EncodeContext.init(64).withDefaultRel(true));
    defer pure_offset.deinit(testing.allocator);
    const pure_offset_bytes = try materializeOutput(testing.allocator, pure_offset.units());
    defer if (pure_offset_bytes.len > 0) testing.allocator.free(pure_offset_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x8A, 0x0C, 0x25, 0x00, 0x01, 0x00, 0x00 }, pure_offset_bytes);

    var disp8 = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[rbx + 4]" }, EncodeContext.init(64));
    defer disp8.deinit(testing.allocator);
    const disp8_bytes = try materializeOutput(testing.allocator, disp8.units());
    defer if (disp8_bytes.len > 0) testing.allocator.free(disp8_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x43, 0x04 }, disp8_bytes);

    var negative = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[rbx - 4]" }, EncodeContext.init(64));
    defer negative.deinit(testing.allocator);
    const negative_bytes = try materializeOutput(testing.allocator, negative.units());
    defer if (negative_bytes.len > 0) testing.allocator.free(negative_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x43, 0xFC }, negative_bytes);

    var disp32 = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[1024 + rbx]" }, EncodeContext.init(64));
    defer disp32.deinit(testing.allocator);
    const disp32_bytes = try materializeOutput(testing.allocator, disp32.units());
    defer if (disp32_bytes.len > 0) testing.allocator.free(disp32_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x83, 0x00, 0x04, 0x00, 0x00 }, disp32_bytes);
}

test "encodeBuiltinUnits projects index scale memory expressions into x86 EA state" {
    const testing = std.testing;

    var vsib_index_only = try encodeBuiltinUnits(testing.allocator, "vgatherdpd", &.{ "xmm0", "[xmm2]", "xmm3" }, EncodeContext.init(64));
    defer vsib_index_only.deinit(testing.allocator);
    const vsib_index_only_bytes = try materializeOutput(testing.allocator, vsib_index_only.units());
    defer if (vsib_index_only_bytes.len > 0) testing.allocator.free(vsib_index_only_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xC4, 0xE2, 0xE1, 0x92, 0x04, 0x15, 0x00, 0x00, 0x00, 0x00 }, vsib_index_only_bytes);

    var sib = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[rbx + rcx*4 + 8]" }, EncodeContext.init(64));
    defer sib.deinit(testing.allocator);
    const sib_bytes = try materializeOutput(testing.allocator, sib.units());
    defer if (sib_bytes.len > 0) testing.allocator.free(sib_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x44, 0x8B, 0x08 }, sib_bytes);

    var index_only = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[4*rcx + 16]" }, EncodeContext.init(64));
    defer index_only.deinit(testing.allocator);
    const index_only_bytes = try materializeOutput(testing.allocator, index_only.units());
    defer if (index_only_bytes.len > 0) testing.allocator.free(index_only_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x8B, 0x04, 0x8D, 0x10, 0x00, 0x00, 0x00 }, index_only_bytes);
}

test "encodeBuiltinUnits lets resolver fold multiplicative displacement terms" {
    const testing = std.testing;

    var resolver_context: u8 = 0;
    const resolver: ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = testConstantExpressionResolver,
    };
    var encoded = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "cmp",
        &.{ "qword [r11 + 128 + uptr * 2]", "r10" },
        EncodeContext.init(64),
        false,
        resolver,
    );
    defer encoded.deinit(testing.allocator);
    const bytes = try materializeOutput(testing.allocator, encoded.units());
    defer if (bytes.len > 0) testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &.{ 0x4D, 0x39, 0x93, 0x90, 0x00, 0x00, 0x00 }, bytes);

    var parenthesized = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "mov",
        &.{ "r10", "qword [r11 + 4 * (STD_HASH_MAP_ENTRY_HEADER_SIZE + u64 + u64) + STD_HASH_MAP_ENTRY_HASH_OFFSET]" },
        EncodeContext.init(64),
        false,
        resolver,
    );
    defer parenthesized.deinit(testing.allocator);
    const parenthesized_bytes = try materializeOutput(testing.allocator, parenthesized.units());
    defer if (parenthesized_bytes.len > 0) testing.allocator.free(parenthesized_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x4D, 0x8B, 0x93, 0x80, 0x00, 0x00, 0x00 }, parenthesized_bytes);
}

test "encodeBuiltinUnits projects segment override memory prefixes into x86 prefix state" {
    const testing = std.testing;

    var fs_mem = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "fs:[rbx]" }, EncodeContext.init(64));
    defer fs_mem.deinit(testing.allocator);
    const fs_bytes = try materializeOutput(testing.allocator, fs_mem.units());
    defer if (fs_bytes.len > 0) testing.allocator.free(fs_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x64, 0x48, 0x8B, 0x03 }, fs_bytes);
    try testing.expectEqual(@as(usize, 0), fs_mem.encoded.warnings.items.len);

    var gs_inner = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[gs:rbx + 4]" }, EncodeContext.init(64));
    defer gs_inner.deinit(testing.allocator);
    const gs_bytes = try materializeOutput(testing.allocator, gs_inner.units());
    defer if (gs_bytes.len > 0) testing.allocator.free(gs_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x65, 0x48, 0x8B, 0x43, 0x04 }, gs_bytes);

    var es_mem = try encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "es:[rbx]" }, EncodeContext.init(64));
    defer es_mem.deinit(testing.allocator);
    const es_bytes = try materializeOutput(testing.allocator, es_mem.units());
    defer if (es_bytes.len > 0) testing.allocator.free(es_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x26, 0x48, 0x8B, 0x03 }, es_bytes);
    try testing.expectEqual(@as(usize, 1), es_mem.encoded.warnings.items.len);
    try testing.expectEqualStrings("segment override ignored in 64-bit mode", es_mem.encoded.warnings.items[0]);

    try testing.expectError(
        error.UnsupportedOperandSyntax,
        encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[fs:gs:rbx]" }, EncodeContext.init(64)),
    );
}

test "encodeBuiltinUnits projects x86 register-set operands" {
    const testing = std.testing;

    var v4fmadd = try encodeBuiltinUnits(testing.allocator, "v4fmaddps", &.{ "zmm0", "zmm1+3", "[rax]" }, EncodeContext.init(64));
    defer v4fmadd.deinit(testing.allocator);
    const v4fmadd_bytes = try materializeOutput(testing.allocator, v4fmadd.units());
    defer testing.allocator.free(v4fmadd_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0xF2, 0x77, 0x48, 0x9A, 0x00 }, v4fmadd_bytes);

    var v4fnmadd = try encodeBuiltinUnits(testing.allocator, "v4fnmaddps", &.{ "zmm2", "zmm3", "[rax]" }, EncodeContext.init(64));
    defer v4fnmadd.deinit(testing.allocator);
    const v4fnmadd_bytes = try materializeOutput(testing.allocator, v4fnmadd.units());
    defer testing.allocator.free(v4fnmadd_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0xF2, 0x67, 0x48, 0xAA, 0x10 }, v4fnmadd_bytes);
}

test "encodeBuiltinUnits projects EVEX static rounding decorator operands" {
    const testing = std.testing;

    var encoded = try encodeBuiltinUnits(testing.allocator, "vaddps", &.{ "zmm8{k4}{z}", "zmm9", "zmm10", "{rn-sae}" }, EncodeContext.init(64));
    defer encoded.deinit(testing.allocator);
    const bytes = try materializeOutput(testing.allocator, encoded.units());
    defer if (bytes.len > 0) testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0x51, 0x34, 0x9C, 0x58, 0xC2 }, bytes);
}

test "encodeBuiltinUnits matches APX DFV spec4 CCMP templates" {
    const testing = std.testing;

    var encoded = try encodeBuiltinUnits(testing.allocator, "ccmpl", &.{ "0x9", "rdx", "r30" }, EncodeContext.init(64));
    defer encoded.deinit(testing.allocator);
    const bytes = try materializeOutput(testing.allocator, encoded.units());
    defer testing.allocator.free(bytes);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0x64, 0xCC, 0x0C, 0x39, 0xF2 }, bytes);
}

test "encodeBuiltinUnits projects explicit memory size prefixes into x86 operand bits" {
    const testing = std.testing;

    var inc_byte = try encodeBuiltinUnits(testing.allocator, "inc", &.{"byte [rbx]"}, EncodeContext.init(64));
    defer inc_byte.deinit(testing.allocator);
    const inc_byte_bytes = try materializeOutput(testing.allocator, inc_byte.units());
    defer if (inc_byte_bytes.len > 0) testing.allocator.free(inc_byte_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xFE, 0x03 }, inc_byte_bytes);

    var inc_qword = try encodeBuiltinUnits(testing.allocator, "inc", &.{"qword [rbx]"}, EncodeContext.init(64));
    defer inc_qword.deinit(testing.allocator);
    const inc_qword_bytes = try materializeOutput(testing.allocator, inc_qword.units());
    defer if (inc_qword_bytes.len > 0) testing.allocator.free(inc_qword_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0xFF, 0x03 }, inc_qword_bytes);
}

test "encodeBuiltinUnits projects jump size prefixes into x86 operand bits" {
    const testing = std.testing;

    var near_ins = match.Instruction.init(match.opcodeByMnemonic("jmp") orelse return error.UnexpectedTestResult, 64);
    const near_operand = switch (try operandFromText(&near_ins, "near 0", null)) {
        .operand => |operand| operand,
        .er_sae => return error.UnexpectedTestResult,
    };
    try testing.expect((near_operand.type_bits & match.near) != 0);
    try testing.expect((near_ins.opt & (types.optim_no_jcc_relax | types.optim_no_jmp_relax)) != 0);
    var short_ins = match.Instruction.init(match.opcodeByMnemonic("jmp") orelse return error.UnexpectedTestResult, 64);
    const short_operand = switch (try operandFromText(&short_ins, "short 0", null)) {
        .operand => |operand| operand,
        .er_sae => return error.UnexpectedTestResult,
    };
    try testing.expect((short_operand.type_bits & match.short) != 0);
    try testing.expect((short_ins.opt & (types.optim_no_jcc_relax | types.optim_no_jmp_relax)) != 0);

    var short_jmp = try encodeBuiltinUnits(testing.allocator, "jmp", &.{"short 0"}, EncodeContext.init(64));
    defer short_jmp.deinit(testing.allocator);
    const short_jmp_bytes = try materializeOutput(testing.allocator, short_jmp.units());
    defer if (short_jmp_bytes.len > 0) testing.allocator.free(short_jmp_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xEB, 0xFE }, short_jmp_bytes);

    var near_jmp = try encodeBuiltinUnits(testing.allocator, "jmp", &.{"near 0"}, EncodeContext.init(64));
    defer near_jmp.deinit(testing.allocator);
    const near_jmp_bytes = try materializeOutput(testing.allocator, near_jmp.units());
    defer if (near_jmp_bytes.len > 0) testing.allocator.free(near_jmp_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xE9, 0xFB, 0xFF, 0xFF, 0xFF }, near_jmp_bytes);
}

test "encodeBuiltinUnits uses branch relaxation hint only for unknown automatic jumps" {
    const testing = std.testing;

    var resolver_context: u8 = 0;
    const resolver: ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = testUnknownExpressionResolver,
    };

    var default_jmp = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "jmp",
        &.{"target"},
        EncodeContext.init(64),
        false,
        resolver,
    );
    defer default_jmp.deinit(testing.allocator);
    try testing.expectEqual(@as(?BranchRelaxationDecision, null), default_jmp.branch_relaxation_decision);
    try testing.expect(default_jmp.units().len >= 1);
    try testing.expectEqualSlices(u8, &.{0xEB}, default_jmp.units()[0].bytes);

    const current_known = false;
    var hinted_jmp = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "jmp",
        &.{"target"},
        EncodeContext.init(64)
            .withBranchRelaxationHint(.near)
            .withBranchRelaxationCurrentKnown(&current_known),
        false,
        resolver,
    );
    defer hinted_jmp.deinit(testing.allocator);
    try testing.expectEqual(@as(?BranchRelaxationDecision, null), hinted_jmp.branch_relaxation_decision);
    try testing.expect(hinted_jmp.units().len >= 1);
    try testing.expectEqualSlices(u8, &.{0xE9}, hinted_jmp.units()[0].bytes);

    var known_short = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "jmp",
        &.{"0"},
        EncodeContext.init(64).withBranchRelaxationHint(.near),
        false,
        null,
    );
    defer known_short.deinit(testing.allocator);
    try testing.expectEqual(@as(?BranchRelaxationDecision, .rel8), known_short.branch_relaxation_decision);
    const known_short_bytes = try materializeOutput(testing.allocator, known_short.units());
    defer if (known_short_bytes.len > 0) testing.allocator.free(known_short_bytes);
    try testing.expectEqualSlices(u8, &.{ 0xEB, 0xFE }, known_short_bytes);
}

test "encodeBuiltinUnits keeps unknown immediates on conservative fixup widths" {
    const testing = std.testing;
    var resolver_context: u8 = 0;
    const resolver: ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = testUnknownExpressionResolver,
    };

    var add = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "add",
        &.{ "r11", "target" },
        EncodeContext.init(64),
        false,
        resolver,
    );
    defer add.deinit(testing.allocator);
    const add_fixup = add.units()[add.units().len - 1].fixup orelse return error.UnexpectedTestResult;
    try testing.expectEqual(@as(u8, 4), add_fixup.size);
    try testing.expectEqual(FixupValueRange.signed, fixupValueRange(add_fixup));

    var mov = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "mov",
        &.{ "rax", "target" },
        EncodeContext.init(64),
        false,
        resolver,
    );
    defer mov.deinit(testing.allocator);
    const mov_fixup = mov.units()[mov.units().len - 1].fixup orelse return error.UnexpectedTestResult;
    try testing.expectEqual(@as(u8, 8), mov_fixup.size);
    try testing.expectEqual(FixupValueRange.wrap, fixupValueRange(mov_fixup));
}

test "encodeBuiltinUnits preserves symbolic near Jcc fixup at nonzero origin" {
    const testing = std.testing;
    var resolver_context: u8 = 0;
    const resolver: ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = testUnknownExpressionResolver,
    };
    const current_known = false;

    var result = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "jne",
        &.{"target"},
        EncodeContext.init(64)
            .withOutputPosition(0x0040_1000)
            .withBranchRelaxationHint(.near)
            .withBranchRelaxationCurrentKnown(&current_known),
        false,
        resolver,
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), result.units().len);
    try testing.expectEqualSlices(u8, &.{0x0F}, result.units()[0].bytes);
    try testing.expectEqualSlices(u8, &.{0x85}, result.units()[1].bytes);
    const fixup = result.units()[2].fixup orelse return error.UnexpectedTestResult;
    try testing.expectEqual(FixupKind.relative, fixup.kind);
    try testing.expectEqual(@as(u8, 4), fixup.size);
    try testing.expectEqual(@as(i64, 0x0040_1006), fixup.relbase);
}

test "encodeBuiltinUnits preserves symbolic RIP-relative memory fixup" {
    const testing = std.testing;
    var resolver_context: u8 = 0;
    const resolver: ExpressionResolver = .{
        .context = &resolver_context,
        .resolveFn = testUnknownExpressionResolver,
    };

    var result = try encodeBuiltinUnitsWithResolver(
        testing.allocator,
        "mov",
        &.{ "eax", "[rel target]" },
        EncodeContext.init(64).withOutputPosition(0x0050_2000),
        false,
        resolver,
    );
    defer result.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 3), result.units().len);
    try testing.expectEqualSlices(u8, &.{0x8B}, result.units()[0].bytes);
    try testing.expectEqualSlices(u8, &.{0x05}, result.units()[1].bytes);
    const fixup = result.units()[2].fixup orelse return error.UnexpectedTestResult;
    try testing.expectEqual(FixupKind.relative, fixup.kind);
    try testing.expectEqual(@as(u8, 4), fixup.size);
    try testing.expectEqual(@as(i64, 0x0050_2006), fixup.relbase);
}

test "encodeBuiltinUnits rejects cmp r64 immediates that cannot sign-extend from imm32" {
    const testing = std.testing;

    var small = try encodeBuiltinUnits(testing.allocator, "cmp", &.{ "rax", "0x7fffffff" }, EncodeContext.init(64));
    defer small.deinit(testing.allocator);
    const small_bytes = try materializeOutput(testing.allocator, small.units());
    defer if (small_bytes.len > 0) testing.allocator.free(small_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x3D, 0xFF, 0xFF, 0xFF, 0x7F }, small_bytes);

    var negative = try encodeBuiltinUnits(testing.allocator, "cmp", &.{ "rax", "-2147483648" }, EncodeContext.init(64));
    defer negative.deinit(testing.allocator);
    const negative_bytes = try materializeOutput(testing.allocator, negative.units());
    defer if (negative_bytes.len > 0) testing.allocator.free(negative_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x48, 0x3D, 0x00, 0x00, 0x00, 0x80 }, negative_bytes);

    try testing.expectError(
        error.CmpR64ImmediateOutOfRange,
        encodeBuiltinUnits(testing.allocator, "cmp", &.{ "rax", "0x1122334455667788" }, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.CmpR64ImmediateOutOfRange,
        encodeBuiltinUnits(testing.allocator, "cmp", &.{ "rax", "0xffffffff" }, EncodeContext.init(64)),
    );

    var eax = try encodeBuiltinUnits(testing.allocator, "cmp", &.{ "eax", "0xffffffff" }, EncodeContext.init(64));
    defer eax.deinit(testing.allocator);
    const eax_bytes = try materializeOutput(testing.allocator, eax.units());
    defer if (eax_bytes.len > 0) testing.allocator.free(eax_bytes);
    try testing.expectEqualSlices(u8, &.{ 0x83, 0xF8, 0xFF }, eax_bytes);
}

test "x86 integer literal classifier does not steal labels ending in h" {
    const testing = std.testing;

    try testing.expectEqual(@as(?i64, null), try parseIntLiteralForEncode("finish"));
    try testing.expectEqual(@as(?i64, null), try parseIntLiteralForEncode("branch_target_h"));
    try testing.expectEqual(@as(?i64, null), try parseIntLiteralForEncode("deadbeefh"));
    try testing.expectEqual(@as(?i64, 0x0e0), try parseIntLiteralForEncode("0E0h"));
    try testing.expectEqual(@as(?i64, 0x80000001), try parseIntLiteralForEncode("80000001h"));
    try testing.expectError(error.InvalidIntegerLiteral, parseIntLiteralForEncode("12gh"));
}

test "encodeBuiltinUnits keeps operand parser and matcher failures explicit" {
    const testing = std.testing;

    try testing.expectError(
        error.InvalidIntegerLiteral,
        encodeBuiltinUnits(testing.allocator, "push", &.{"0x"}, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.IntegerOverflow,
        encodeBuiltinUnits(testing.allocator, "push", &.{"9223372036854775808"}, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.UnsupportedOperandSyntax,
        encodeBuiltinUnits(testing.allocator, "push", &.{"rax + 4"}, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.InvalidMemoryScale,
        encodeBuiltinUnits(testing.allocator, "mov", &.{ "rax", "[rbx + rcx*3]" }, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.NoMatchingTemplate,
        encodeBuiltinUnits(testing.allocator, "inc", &.{"byte rbx"}, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.AmbiguousMemorySize,
        encodeBuiltinUnits(testing.allocator, "inc", &.{"[rbx]"}, EncodeContext.init(64)),
    );
    try testing.expectError(
        error.UnsupportedPrefixes,
        encodeBuiltinUnits(testing.allocator, "cmp", &.{ "[rbx]", "eax" }, EncodeContext.init(64).withLock(true)),
    );
}
