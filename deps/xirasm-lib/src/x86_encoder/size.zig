//! x86 `asm/assemble.c` size-stage translation.
//!
//! This module is the Zig landing point for `calcsize` and
//! `calcsize_speculative`. It walks the generated source-backed template bytecode
//! stream; instruction-specific behavior stays in the generated tables.

const std = @import("std");
const bytecode = @import("bytecode.zig");
const ea = @import("ea.zig");
const generated = @import("generated_match_tables.zig");
const generated_registers = @import("generated_registers.zig");
const match = @import("match.zig");
const regs = @import("regs.zig");
const types = @import("types.zig");

pub const size_stage_functions = [_][]const u8{ "insn_size", "insn_early_setup", "calcsize", "calcsize_speculative" };

pub const CalcSizeError = bytecode.BytecodeError || ea.EaError || error{
    MissingTemplate,
    MissingOperand,
    NeedsRegisterHelpers,
    NeedsEaStage,
    NeedsPrefixEmitter,
    NeedsCpuFeatureContext,
    InvalidAddressSize,
    InvalidOperandSize,
    InvalidPrefixEncoding,
    InvalidReserveOpcode,
    InvalidEvexTupleType,
    HighRegisterNotAllowed,
    ImpossibleAddressSize,
    SizeOverflow,
    UnsupportedBytecode,
};

const pfe_null: i32 = types.pfe_null;
const pfe_multi: i32 = types.pfe_multi;
const pfe_err: i32 = types.pfe_err;
const pfe_what: i32 = types.pfe_what;

const r_cs: i32 = exprRegByEnumName("R_CS");
const r_ds: i32 = exprRegByEnumName("R_DS");
const r_es: i32 = exprRegByEnumName("R_ES");
const r_fs: i32 = exprRegByEnumName("R_FS");
const r_gs: i32 = exprRegByEnumName("R_GS");
const r_ss: i32 = exprRegByEnumName("R_SS");

const bits16: u64 = match.bits16;
const bits32: u64 = match.bits32;
const bits64: u64 = match.bits64;
const immediate: u64 = match.immediate;

const optim_strict_osize: u32 = types.optim_strict_osize;
const if_noapx: u32 = types.if_noapx;
const if_ww: u32 = types.if_ww;
const if_lock: u32 = types.if_lock;
const if_lock1: u32 = types.if_lock1;
const if_sib: u32 = types.if_sib;
const if_jcc_hint: u32 = types.if_jcc_hint;
const if_mib: u32 = types.if_mib;
const if_bnd: u32 = types.if_bnd;
const if_apx: u32 = types.if_apx;
const if_x86_64: u32 = types.if_x86_64;
const rex_w: u32 = types.rex_w;
const rex_l: u32 = types.rex_l;
const rex_mask: u32 = types.rex_mask;
const rex_v: u32 = types.rex_v;
const rex_ev: u32 = types.rex_ev;
const rex_2: u32 = types.rex_2;
const rex_bxr1: u32 = types.rex_bxr1;
const rex_bxr: u32 = types.rex_bxr;
const rv_evex: u8 = @intCast(types.rv_evex);
pub const CalcSizeWarning = enum(u8) {
    jmp_short_bnd_prefix_dropped,
    instruction_not_lockable,
    superfluous_lock_xchg,
    hle_requires_lock,
    hle_invalid,
    invalid_branch_hint_dropped,
    forward_reserve_unstable,
};

pub const CalcSizeDiagnostics = struct {
    const warning_count = @typeInfo(CalcSizeWarning).@"enum".field_names.len;

    warnings: [warning_count]u32 = @splat(@as(u32, 0)),

    pub fn record(self: *CalcSizeDiagnostics, warning: CalcSizeWarning) void {
        const index = @intFromEnum(warning);
        if (self.warnings[index] < std.math.maxInt(u32)) {
            self.warnings[index] += 1;
        }
    }

    pub fn count(self: *const CalcSizeDiagnostics, warning: CalcSizeWarning) u32 {
        return self.warnings[@intFromEnum(warning)];
    }
};

pub const CpuFeatures = struct {
    x86_64: bool = false,
    apx: bool = false,
};

pub const CalcSizeContext = struct {
    cpu_features: ?CpuFeatures = null,
    global_bnd: bool = false,
    diagnostics: ?*CalcSizeDiagnostics = null,

    fn cpuFeature(self: CalcSizeContext, iflag: u32) CalcSizeError!bool {
        const features = self.cpu_features orelse return error.NeedsCpuFeatureContext;
        return switch (iflag) {
            if_apx => features.apx,
            if_x86_64 => features.x86_64,
            else => false,
        };
    }

    fn warn(self: CalcSizeContext, warning: CalcSizeWarning) void {
        if (self.diagnostics) |diagnostics| diagnostics.record(warning);
    }
};

pub const InsnSizeResult = union(enum) {
    size: i64,
    no_match: match.MatchResult,
};

pub fn insnSize(match_context: anytype, size_context: CalcSizeContext, ins: *match.Instruction) CalcSizeError!InsnSizeResult {
    try insnEarlySetup(ins);

    const result = match.findMatch(match_context, ins);
    if (!result.isSuccess()) {
        return .{ .no_match = result };
    }

    return .{ .size = try calcSizeWithContext(size_context, ins) };
}

pub fn calcSize(ins: *match.Instruction) CalcSizeError!i64 {
    return calcSizeWithContext(.{}, ins);
}

pub fn insnEarlySetup(ins: *match.Instruction) CalcSizeError!void {
    try addAsp(ins);
    setInitialOpSize(ins);
}

pub fn calcSizeWithContext(context: CalcSizeContext, ins: *match.Instruction) CalcSizeError!i64 {
    const temp = ins.itemp orelse return error.MissingTemplate;
    const bits: i32 = ins.bits;
    var cursor = try bytecode.BytecodeCursor.init(temp);
    var length: i64 = 0;
    var opt_opsize: i32 = 0;
    var saw_prefix_state = false;
    var ea_type: match.EaType = .scalar;
    var hleok: u8 = 0;
    var lockcheck = true;
    var mib_index: i32 = match.r_none;

    ins.op_size = if (bits != 16) 32 else 16;
    ins.rex = 0;
    ins.evex = 0;
    ins.vexreg = 0;
    ins.veximm = 0;
    ins.vex_cm = 0;
    ins.vex_wlp = 0;
    ins.evex_tuple = .none;
    ins.ea = .{};
    ins.need_pfx = @splat(@as(i32, 0));

    while (cursor.peek()) |next_byte| {
        if (next_byte == 0) break;

        const c = try cursor.nextRequired();
        const indices = cursor.operandIndices(c);
        cursor.clearOpex();

        switch (c) {
            0o1...0o4 => {
                try cursor.consumeLiteralBytes(c);
                length += c;
            },
            0o5...0o7 => cursor.setOpex(c),
            0o10...0o13 => {
                const opx = try getOperand(ins, indices.primary);
                ins.rex |= try ea.opRexflags(opx, ea.rex_rB);
                try cursor.consumeRequiredByte();
                length += 1;
            },
            0o171 => {
                const selector = try cursor.nextRequired();
                const op2_index: u8 = (indices.secondary & ~@as(u8, 3)) | ((selector >> 3) & 3);
                const opy = try getOperand(ins, op2_index);
                ins.rex |= try ea.opRexflags(opy, ea.rex_rR);
                length += 1;
            },
            0o240...0o243 => {
                const opx = try getOperand(ins, indices.primary);
                try applyEvexSetup(ins, opx, &cursor);
            },
            0o250 => {
                try applyEvexSetup(ins, null, &cursor);
            },
            0o260...0o263 => {
                const opx = try getOperand(ins, indices.primary);
                try applyVexSetup(ins, opx, &cursor);
            },
            0o270 => {
                try applyVexSetup(ins, null, &cursor);
            },
            0o14...0o17 => {
                const opx = try getOperand(ins, indices.primary);
                mib_index = opx.basereg;
            },
            0o20...0o27, 0o50...0o53, 0o274...0o277, 0o300...0o303 => {
                length += 1;
            },
            0o30...0o33, 0o60...0o63, 0o74...0o77 => {
                length += 2;
            },
            0o34...0o37, 0o64...0o67 => {
                const opx = try getOperand(ins, indices.primary);
                if ((opx.type_bits & (bits16 | bits32 | bits64)) != 0) {
                    length += if ((opx.type_bits & bits16) != 0) 2 else 4;
                } else {
                    length += if (ins.op_size == 16) 2 else 4;
                }
            },
            0o40...0o43, 0o70...0o73, 0o254...0o257, 0o264...0o267 => {
                length += 4;
            },
            0o44...0o47 => {
                length += @as(i64, ins.addr_size >> 3);
            },
            0o54...0o57 => {
                length += 8;
            },
            0o172, 0o173 => {
                try cursor.consumeRequiredByte();
                length += 1;
            },
            0o174...0o177 => {
                length += 1;
            },
            0o271...0o273 => {
                hleok = c & 3;
            },
            0o304...0o307 => {
                length += 1;
                try cursor.consumeRequiredByte();
                try cursor.consumeRequiredByte();
            },
            0o310 => {
                ins.addr_size = 16;
                if (bits == 64) return error.InvalidAddressSize;
                const pfx = ins.prefixes[match.PrefixSlot.address_size.index()].raw();
                if (pfx != match.p_none) {
                    if (!(pfx == match.p_a16 or (bits == 32 and pfx == match.p_asp))) {
                        return error.InvalidAddressSize;
                    }
                } else {
                    ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a16 };
                    saw_prefix_state = true;
                }
            },
            0o311 => {
                ins.addr_size = 32;
                const pfx = ins.prefixes[match.PrefixSlot.address_size.index()].raw();
                if (pfx != match.p_none) {
                    if (!(pfx == match.p_a32 or (bits != 32 and pfx == match.p_asp))) {
                        return error.InvalidAddressSize;
                    }
                } else {
                    ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a32 };
                    saw_prefix_state = true;
                }
            },
            0o312 => {},
            0o313 => {
                ins.addr_size = 64;
                const pfx = ins.prefixes[match.PrefixSlot.address_size.index()].raw();
                if (bits != 64 or (pfx != match.p_none and pfx != match.p_a64)) {
                    return error.InvalidAddressSize;
                }
                ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a64 };
                saw_prefix_state = true;
            },
            0o314...0o317 => {},
            0o320 => try applyO16(ins, opt_opsize, &saw_prefix_state),
            0o321 => try applyO32(ins, bits, opt_opsize, &saw_prefix_state),
            0o322 => {},
            0o327 => {
                if (bits == 64) {
                    ins.rex |= ea.rex_nw;
                    if (ins.op_size == 32) ins.op_size = 64;
                }
            },
            0o323 => {
                ins.rex |= ea.rex_nw;
                try applyO64(ins, opt_opsize, &saw_prefix_state);
            },
            0o324 => try applyO64(ins, opt_opsize, &saw_prefix_state),
            0o325 => {
                ins.rex |= ea.rex_nh;
            },
            0o334 => {
                ins.rex |= rex_l;
            },
            0o335 => {},
            0o344...0o351 => {
                applyRexBytecode(ins, c);
            },
            0o355...0o357 => try applyLegacyOpmap(ins, c),
            0o326 => {},
            0o330 => try applyOsz(ins, bits, opt_opsize, &saw_prefix_state),
            0o331...0o333, 0o360, 0o361, 0o364...0o367 => try applyPrefixIntent(ins, c),
            0o336 => {
                if ((strictOsizeFlags(ins) & optim_strict_osize) == 0) {
                    opt_opsize = 16 | 32 | 64;
                }
            },
            0o337 => {
                if ((strictOsizeFlags(ins) & optim_strict_osize) == 0) {
                    opt_opsize = 64;
                }
            },
            0o340 => {
                const opx = try getOperand(ins, indices.primary);
                try applyReserveBytecode(context, ins, opx, &length);
            },
            0o341 => {
                if (ins.prefixes[match.PrefixSlot.wait.index()].raw() == match.p_none) {
                    ins.prefixes[match.PrefixSlot.wait.index()] = .{ .value = match.p_wait };
                    saw_prefix_state = true;
                }
            },
            0o342 => switch (bits) {
                16 => try applyO16(ins, opt_opsize, &saw_prefix_state),
                32 => try applyO32(ins, bits, opt_opsize, &saw_prefix_state),
                64 => try applyO64(ins, opt_opsize, &saw_prefix_state),
                else => return error.InvalidOperandSize,
            },
            0o370 => {},
            0o371 => {
                if (ins.prefixes[match.PrefixSlot.rep.index()].raw() == match.p_bnd) {
                    ins.prefixes[match.PrefixSlot.rep.index()] = match.PrefixToken.none;
                    if (!ins.dummy) context.warn(.jmp_short_bnd_prefix_dropped);
                    saw_prefix_state = true;
                }
            },
            0o373 => {
                length += 1;
            },
            0o374 => {
                ea_type = .xmm_vsib;
            },
            0o375 => {
                ea_type = .ymm_vsib;
            },
            0o376 => {
                ea_type = .zmm_vsib;
            },
            0o100...0o103,
            0o110...0o113,
            0o120...0o123,
            0o130...0o133,
            0o200...0o203,
            0o204...0o207,
            0o210...0o213,
            0o214...0o217,
            0o220...0o223,
            0o224...0o227,
            0o230...0o233,
            0o234...0o237,
            => {
                length += try applyEaBytecode(ins, temp, c, indices.primary, indices.secondary, mib_index, ea_type);
            },
            else => return error.UnsupportedBytecode,
        }
    }

    try normalizeRexBeforePrefixLength(ins);
    length += try encodingPrefixLength(context, temp, ins, &lockcheck);
    checkLockPrefix(context, temp, ins, lockcheck);
    badHleWarn(context, ins, hleok);
    applyGlobalBnd(context, temp, ins);
    dropInvalidBranchHintPrefix(context, temp, ins);
    length += try legacyPrefixLength(ins);
    return length;
}

pub fn calcSizeSpeculative(ins: *const match.Instruction, temp: match.TemplateRef) match.SpeculativeSize {
    return calcSizeSpeculativeImpl(ins, temp);
}

fn calcSizeSpeculativeImpl(ins: *const match.Instruction, temp: match.TemplateRef) match.SpeculativeSize {
    var tmp = ins.*;
    tmp.dummy = true;
    tmp.itemp = temp;
    const value = calcSize(&tmp) catch return .would_error;
    return .{ .size = value };
}

fn getOperand(ins: *const match.Instruction, index: u8) CalcSizeError!*const match.Operand {
    if (index >= ins.operands) return error.MissingOperand;
    return &ins.oprs[index];
}

fn getOperandMut(ins: *match.Instruction, index: u8) CalcSizeError!*match.Operand {
    if (index >= ins.operands) return error.MissingOperand;
    return &ins.oprs[index];
}

fn addAsp(ins: *match.Instruction) CalcSizeError!void {
    const bits: i32 = ins.bits;
    var valid: i32 = if (bits == 64) 64 | 32 else 32 | 16;

    switch (ins.prefixes[match.PrefixSlot.address_size.index()].raw()) {
        match.p_a16 => valid &= 16,
        match.p_a32 => valid &= 32,
        match.p_a64 => valid &= 64,
        match.p_asp => valid &= if (bits == 32) 16 else 32,
        else => {},
    }

    for (ins.oprs[0..ins.operands]) |operand| {
        if (!isClass(match.memory, operand.type_bits)) continue;

        var index_flags = try registerFlagsForAddressSetup(operand.indexreg);
        const base_flags = try registerFlagsForAddressSetup(operand.basereg);
        if (operand.scale == 0) index_flags = 0;

        if (index_flags == 0 and base_flags == 0) {
            const disp_size: i32 = operand.disp_size;
            if ((bits != 64 and disp_size > 8) or (bits == 64 and disp_size == 16)) {
                valid &= disp_size;
            }
        } else {
            if ((match.reg16 & ~base_flags) == 0) valid &= 16;
            if ((match.reg32 & ~base_flags) == 0) valid &= 32;
            if ((match.reg64 & ~base_flags) == 0) valid &= 64;

            if ((match.reg16 & ~index_flags) == 0) valid &= 16;
            if ((match.reg32 & ~index_flags) == 0) valid &= 32;
            if ((match.reg64 & ~index_flags) == 0) valid &= 64;
        }
    }

    const asp_bits: i32 = if (bits == 32) 16 else 32;
    if ((valid & bits) != 0) {
        ins.addr_size = @intCast(bits);
    } else if ((valid & asp_bits) != 0) {
        ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = if (bits == 32) match.p_a16 else match.p_a32 };
        ins.addr_size = @intCast(asp_bits);
    } else {
        ins.addr_size = @intCast(bits);
        return error.ImpossibleAddressSize;
    }

    const defdisp: u8 = if (ins.addr_size == 16) 16 else 32;
    for (ins.oprs[0..ins.operands]) |*operand| {
        if (!isClass(match.mem_offs, operand.type_bits)) continue;

        const disp_size = if (operand.disp_size != 0) operand.disp_size else defdisp;
        if (disp_size != ins.addr_size) {
            operand.type_bits &= ~(match.mem_offs & ~match.memory);
        }
    }
}

fn setInitialOpSize(ins: *match.Instruction) void {
    ins.op_size = switch (ins.prefixes[match.PrefixSlot.operand_size.index()].raw()) {
        match.p_osp => if (ins.bits == 16) 32 else 16,
        match.p_o16 => 16,
        match.p_o32 => 32,
        match.p_o64 => 64,
        else => if (ins.bits == 16) 16 else 32,
    };
}

fn registerFlagsForAddressSetup(expr_reg: i32) CalcSizeError!u64 {
    if (!match.isRegister(expr_reg)) return 0;
    const register = regs.registerRef(expr_reg) orelse return error.MissingRegisterMetadata;
    if (register.flags < 0) return error.InvalidRegisterFlags;
    return @intCast(register.flags);
}

fn applyEvexSetup(ins: *match.Instruction, opx: ?*const match.Operand, cursor: *bytecode.BytecodeCursor) CalcSizeError!void {
    if (opx) |operand| {
        if ((operand.type_bits & immediate) != 0) {
            ins.veximm = truncateU8(operand.offset);
        } else {
            ins.vexreg = try regvalU8(operand);
        }
    } else {
        ins.vexreg = 0;
    }

    ins.rex |= rex_ev;
    ins.evex = 0x62;
    const payload = try cursor.consumeEvexPayload();
    ins.evex += @as(u32, payload.p0) << 8;
    ins.evex += @as(u32, payload.p1) << 16;
    ins.evex += @as(u32, payload.p2) << 24;
    ins.evex_tuple = try decodeTupleType(payload.tuple);
    ins.vex_cm = @as(u8, @intCast((ins.evex >> 8) & 7)) | (rv_evex << 6);
}

fn applyVexSetup(ins: *match.Instruction, opx: ?*const match.Operand, cursor: *bytecode.BytecodeCursor) CalcSizeError!void {
    if (opx) |operand| {
        if ((operand.type_bits & immediate) != 0) {
            ins.veximm = truncateU8(operand.offset);
        } else {
            ins.vexreg = try regvalU8(operand);
        }
    } else {
        ins.vexreg = 0;
    }

    ins.rex |= rex_v;
    const payload = try cursor.consumeVexPayload();
    ins.vex_cm = payload.cm;
    ins.vex_wlp = payload.wlp;
}

fn decodeTupleType(raw: u8) CalcSizeError!match.TupleType {
    if (raw < 0o300) return error.InvalidEvexTupleType;

    return switch (raw - 0o300) {
        0 => .none,
        1 => .fv,
        2 => .hv,
        3 => .fvm,
        4 => .t1s8,
        5 => .t1s16,
        6 => .t1s,
        7 => .t1f32,
        8 => .t1f64,
        9 => .t2,
        10 => .t4,
        11 => .t8,
        12 => .hvm,
        13 => .qvm,
        14 => .ovm,
        15 => .m128,
        16 => .dup,
        else => error.InvalidEvexTupleType,
    };
}

fn truncateU8(value: i64) u8 {
    const raw: u64 = @bitCast(value);
    return @truncate(raw);
}

fn regvalU8(operand: *const match.Operand) CalcSizeError!u8 {
    const value = try regs.regval(operand);
    if (value < 0 or value > std.math.maxInt(u8)) return error.InvalidOperandSize;
    return @intCast(value);
}

fn applyEaBytecode(
    ins: *match.Instruction,
    temp: match.TemplateRef,
    c: u8,
    op1: u8,
    op2: u8,
    mib_index: i32,
    ea_type: match.EaType,
) CalcSizeError!i64 {
    const opy = try getOperandMut(ins, op2);

    var rfield: i32 = 0;
    var rflags: u64 = 0;

    if (c <= 0o177) {
        const opx = try getOperand(ins, op1);
        rflags = try regs.regflag(opx);
        rfield = try regs.regval(opx);
    } else {
        rfield = c & 7;
    }

    if (temp.iflagTest(if_mib)) {
        opy.eaflags |= ea.eaf_mib;
        if (mib_index != match.r_none) {
            opy.indexreg = mib_index;
            opy.scale = 1;
            opy.hintbase = mib_index;
            opy.hinttype = ea.eah_notbase;
        }
    }

    if (temp.iflagTest(if_sib)) {
        opy.eaflags |= ea.eaf_sib;
    }

    try ea.eaEvexFlags(ins, opy);
    try ea.processEa(opy, rfield, rflags, ins, ea_type);
    ins.rex |= ins.ea.rex;
    return ins.ea.size;
}

fn applyO16(ins: *match.Instruction, opt_opsize: i32, saw_prefix_state: *bool) CalcSizeError!void {
    const pfx = ins.prefixes[match.PrefixSlot.operand_size.index()].raw();
    ins.op_size = 16;
    if (ins.bits != 16 and pfx == match.p_osp) return;
    if (pfx != match.p_none and pfx != match.p_o16) return;
    if ((opt_opsize & 16) == 0) {
        ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o16 };
        saw_prefix_state.* = true;
    }
}

fn applyO32(ins: *match.Instruction, bits: i32, opt_opsize: i32, saw_prefix_state: *bool) CalcSizeError!void {
    const pfx = ins.prefixes[match.PrefixSlot.operand_size.index()].raw();
    ins.op_size = 32;
    if ((ins.rex & ea.rex_nw) != 0) return error.InvalidOperandSize;
    if (bits == 16 and pfx == match.p_osp) return;
    if (pfx != match.p_none and pfx != match.p_o32) return;
    if ((opt_opsize & 32) == 0) {
        ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o32 };
        saw_prefix_state.* = true;
    }
}

fn applyO64(ins: *match.Instruction, opt_opsize: i32, saw_prefix_state: *bool) CalcSizeError!void {
    const pfx = ins.prefixes[match.PrefixSlot.operand_size.index()].raw();
    ins.op_size = 64;
    if (pfx == match.p_osp) {
        if ((ins.rex & ea.rex_nw) == 0) ins.rex |= rex_w;
        return;
    }
    if (pfx != match.p_none and pfx != match.p_o64) return error.InvalidOperandSize;
    if ((opt_opsize & 64) == 0) {
        ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o64 };
        saw_prefix_state.* = true;
    }
}

fn applyOsz(ins: *match.Instruction, bits: i32, opt_opsize: i32, saw_prefix_state: *bool) CalcSizeError!void {
    switch (ins.prefixes[match.PrefixSlot.operand_size.index()].raw()) {
        match.p_none => switch (ins.op_size) {
            16 => try applyO16(ins, opt_opsize, saw_prefix_state),
            32 => try applyO32(ins, bits, opt_opsize, saw_prefix_state),
            64 => try applyO64(ins, opt_opsize, saw_prefix_state),
            else => return error.InvalidOperandSize,
        },
        match.p_osp => {
            if (bits == 16) {
                try applyO32(ins, bits, opt_opsize, saw_prefix_state);
            } else {
                try applyO16(ins, opt_opsize, saw_prefix_state);
            }
        },
        match.p_o16 => try applyO16(ins, opt_opsize, saw_prefix_state),
        match.p_o32 => try applyO32(ins, bits, opt_opsize, saw_prefix_state),
        match.p_o64 => try applyO64(ins, opt_opsize, saw_prefix_state),
        else => return error.InvalidOperandSize,
    }
}

fn applyRexBytecode(ins: *match.Instruction, c: u8) void {
    switch (c) {
        0o344 => ins.rex |= ea.rex_p | ea.rex_b,
        0o345 => ins.rex |= ea.rex_p | ea.rex_x,
        0o346 => ins.rex |= ea.rex_p | ea.rex_r,
        0o347 => ins.rex |= ea.rex_p | rex_w,
        0o350 => ins.rex |= ea.rex_p | rex_2,
        0o351 => ins.rex |= ea.rex_p | rex_2 | rex_w,
        else => {},
    }
}

fn applyLegacyOpmap(ins: *match.Instruction, c: u8) CalcSizeError!void {
    switch (c) {
        0o355...0o357 => {
            ins.vex_cm = c & 3;
        },
        else => return error.UnsupportedBytecode,
    }
}

fn normalizeRexBeforePrefixLength(ins: *match.Instruction) CalcSizeError!void {
    if ((ins.rex & ea.rex_nh) != 0) {
        if ((ins.rex & ea.rex_h) != 0) return error.HighRegisterNotAllowed;
        ins.rex &= ~ea.rex_p;
    }

    if (ins.prefixes[match.PrefixSlot.operand_size.index()].raw() == match.p_o64 and
        (ins.rex & ea.rex_nw) == 0)
    {
        ins.rex |= rex_w;
    }
}

fn encodingPrefixLength(context: CalcSizeContext, temp: match.TemplateRef, ins: *match.Instruction, lockcheck: *bool) CalcSizeError!i64 {
    const bits = ins.bits;
    const rex_prefix = ins.prefixes[match.PrefixSlot.rex.index()].raw();

    switch (rex_prefix) {
        match.p_evex => {
            if ((ins.rex & rex_ev) == 0) return error.InvalidPrefixEncoding;
        },
        match.p_vex, match.p_vex3, match.p_vex2 => {
            if ((ins.rex & rex_v) == 0) return error.InvalidPrefixEncoding;
        },
        match.p_rex => {
            if (bits != 64) return error.InvalidAddressSize;
            if ((ins.rex & (rex_v | rex_ev | rex_2)) != 0) return error.InvalidPrefixEncoding;
            ins.rex |= ea.rex_p;
        },
        match.p_rex2 => {
            if (bits != 64) return error.InvalidAddressSize;
            if ((ins.rex & (rex_v | rex_ev)) != 0 or rexHighvec(ins.rex) != 0) {
                return error.InvalidPrefixEncoding;
            }
            ins.rex |= ea.rex_p | rex_2;
        },
        else => {},
    }

    if ((ins.rex & (rex_v | rex_ev)) != 0) {
        return try vexEvexPrefixLength(temp, ins);
    }
    if ((ins.rex & (rex_bxr1 | rex_2)) != 0) {
        return try rex2PrefixLength(context, temp, ins);
    }
    if ((ins.rex & rex_mask) != 0) {
        return try rexPrefixLength(context, ins, lockcheck);
    }

    return @as(i64, @intFromBool(ins.vex_cm > 0)) + @as(i64, @intFromBool(ins.vex_cm > 1));
}

fn vexEvexPrefixLength(temp: match.TemplateRef, ins: *match.Instruction) CalcSizeError!i64 {
    var bad32: u32 = rex_bxr;
    if ((ins.rex & ea.rex_h) != 0) return error.HighRegisterNotAllowed;

    if (temp.iflagTest(if_ww)) {
        bad32 |= rex_w;
    } else {
        ins.rex = (ins.rex & ~rex_w) | (@as(u32, ins.vex_wlp >> 4) & rex_w);
    }

    if (ins.bits != 64 and (((ins.rex & bad32) != 0) or ins.vexreg > 7)) {
        return error.InvalidOperandSize;
    }

    if ((ins.rex & rex_ev) != 0) {
        return 4;
    }

    if (ins.vexreg > 15 or (ins.rex & rex_bxr1) != 0) {
        return error.InvalidOperandSize;
    }

    const rex_prefix = ins.prefixes[match.PrefixSlot.rex.index()].raw();
    if (ins.vex_cm != 1 or (ins.rex & (ea.rex_b | ea.rex_x | rex_w)) != 0 or rex_prefix == match.p_vex3) {
        if (rex_prefix == match.p_vex2) return error.InvalidPrefixEncoding;
        return 3;
    }

    return 2;
}

fn rex2PrefixLength(context: CalcSizeContext, temp: match.TemplateRef, ins: *match.Instruction) CalcSizeError!i64 {
    if (ins.bits != 64) return error.InvalidOperandSize;
    if (!try context.cpuFeature(if_apx)) return error.InvalidOperandSize;
    if (temp.iflagTest(if_noapx) or rexHighvec(ins.rex) != 0) {
        return error.InvalidOperandSize;
    }
    if ((ins.rex & ea.rex_h) != 0) return error.HighRegisterNotAllowed;

    ins.rex |= rex_2 | ea.rex_p;
    return 2;
}

fn rexPrefixLength(context: CalcSizeContext, ins: *match.Instruction, lockcheck: *bool) CalcSizeError!i64 {
    if ((ins.rex & ea.rex_h) != 0) return error.HighRegisterNotAllowed;
    if (ins.bits != 64) {
        if ((ins.rex & (rex_l | rex_w | rex_bxr)) == (rex_l | ea.rex_r) and
            try context.cpuFeature(if_x86_64))
        {
            try assertNoPrefix(ins, .lock);
            lockcheck.* = false;
            ins.rex &= ~ea.rex_p;
            return 1;
        }
        return error.InvalidOperandSize;
    }

    ins.rex &= ~rex_l;
    ins.rex |= ea.rex_p;
    return 1;
}

fn rexHighvec(rexflags: u32) u32 {
    return rexflags & (rexflags >> 4) & rex_bxr1;
}

fn legacyPrefixLength(ins: *const match.Instruction) CalcSizeError!i64 {
    var length: i64 = 0;
    for (ins.prefixes, ins.need_pfx) |prefix, required| {
        const prefix_raw = prefix.raw();
        var byte = try prefixByte(prefix_raw, ins.bits);

        if (required != 0 and required != byte and !(required <= 0 and byte <= 0)) {
            switch (prefix_raw) {
                match.p_none, match.p_o16, match.p_o32, match.p_o64, match.p_a16, match.p_a32, match.p_a64 => {
                    byte = required;
                },
                else => {},
            }
        }

        switch (byte) {
            pfe_null, pfe_multi => {},
            pfe_err => return prefixByteError(prefix_raw),
            pfe_what => return error.NeedsPrefixEmitter,
            else => {
                if (byte < 0 or byte > std.math.maxInt(u8)) return error.InvalidPrefixEncoding;
                const prefix_byte: u8 = @intCast(byte);
                if ((ins.rex & (rex_v | rex_ev)) != 0 and (prefix_byte == 0x66 or prefix_byte == 0xf2 or prefix_byte == 0xf3)) {
                    continue;
                }
                length += 1;
            },
        }
    }
    return length;
}

fn prefixByte(prefix: i32, bits: u8) CalcSizeError!i32 {
    return types.prefixByte(prefix, bits);
}

fn exprRegByEnumName(comptime enum_name: []const u8) i32 {
    inline for (generated_registers.all) |register| {
        if (std.mem.eql(u8, register.enum_name, enum_name)) {
            return register.expr_reg;
        }
    }
    @compileError("missing generated register " ++ enum_name);
}

fn prefixByteError(prefix: i32) CalcSizeError {
    return switch (prefix) {
        match.p_a16, match.p_a64 => error.InvalidAddressSize,
        match.p_o64 => error.InvalidOperandSize,
        else => error.InvalidPrefixEncoding,
    };
}

fn dropInvalidBranchHintPrefix(context: CalcSizeContext, temp: match.TemplateRef, ins: *match.Instruction) void {
    const segment_slot = match.PrefixSlot.segment.index();
    const segment_prefix = ins.prefixes[segment_slot].raw();
    if ((segment_prefix == match.p_pt or segment_prefix == match.p_pn) and !temp.iflagTest(if_jcc_hint)) {
        context.warn(.invalid_branch_hint_dropped);
        ins.prefixes[segment_slot] = match.PrefixToken.none;
    }
}

fn checkLockPrefix(context: CalcSizeContext, temp: match.TemplateRef, ins: *const match.Instruction, lockcheck: bool) void {
    if (!lockcheck or !hasPrefix(ins, .lock, match.p_lock)) return;

    const op0_is_memory = isClass(match.memory, operandTypeBits(ins, 0));
    const op1_is_memory = isClass(match.memory, operandTypeBits(ins, 1));
    if ((!temp.iflagTest(if_lock) or !op0_is_memory) and
        (!temp.iflagTest(if_lock1) or !op1_is_memory))
    {
        context.warn(.instruction_not_lockable);
    } else if (isXchgOpcode(temp.opcode())) {
        context.warn(.superfluous_lock_xchg);
    }
}

fn badHleWarn(context: CalcSizeContext, ins: *const match.Instruction, hleok: u8) void {
    const rep_pfx = ins.prefixes[match.PrefixSlot.rep.index()].raw();
    const row: usize = switch (rep_pfx) {
        match.p_xacquire => 0,
        match.p_xrelease => 1,
        else => return,
    };

    const Warn = enum { none, lock, invalid };
    const warn = [2][4]Warn{
        .{ .invalid, .invalid, .none, .lock },
        .{ .invalid, .none, .none, .lock },
    };
    var selected = warn[row][hleok & 3];
    if (!isClass(match.memory, operandTypeBits(ins, 0))) {
        selected = .invalid;
    }

    switch (selected) {
        .none => {},
        .lock => if (!hasPrefix(ins, .lock, match.p_lock)) context.warn(.hle_requires_lock),
        .invalid => context.warn(.hle_invalid),
    }
}

fn applyGlobalBnd(context: CalcSizeContext, temp: match.TemplateRef, ins: *match.Instruction) void {
    if (context.global_bnd and temp.iflagTest(if_bnd) and !hasPrefix(ins, .rep, match.p_nobnd)) {
        ins.prefixes[match.PrefixSlot.rep.index()] = match.PrefixToken.bnd;
    }
}

fn hasPrefix(ins: *const match.Instruction, slot: match.PrefixSlot, prefix: i32) bool {
    return ins.prefixes[slot.index()].raw() == prefix;
}

fn assertNoPrefix(ins: *const match.Instruction, slot: match.PrefixSlot) CalcSizeError!void {
    if (ins.prefixes[slot.index()].raw() != match.p_none) return error.InvalidPrefixEncoding;
}

fn operandTypeBits(ins: *const match.Instruction, index: usize) u64 {
    if (index >= ins.operands) return 0;
    return ins.oprs[index].type_bits;
}

fn isClass(class: u64, op: u64) bool {
    return (class & ~op) == 0;
}

fn isXchgOpcode(opcode: u16) bool {
    return opcode == generated.opcode_xchg;
}

fn applyPrefixIntent(ins: *match.Instruction, c: u8) CalcSizeError!void {
    switch (c) {
        0o331 => {
            ins.need_pfx[match.PrefixSlot.rep.index()] = pfe_null;
        },
        0o332 => {
            ins.need_pfx[match.PrefixSlot.rep.index()] = 0xf2;
        },
        0o333 => {
            ins.need_pfx[match.PrefixSlot.rep.index()] = 0xf3;
        },
        0o360 => {
            ins.need_pfx[match.PrefixSlot.rep.index()] = pfe_null;
            ins.need_pfx[match.PrefixSlot.operand_size.index()] = pfe_null;
        },
        0o361 => {
            ins.need_pfx[match.PrefixSlot.rep.index()] = pfe_null;
            ins.need_pfx[match.PrefixSlot.operand_size.index()] = 0x66;
        },
        0o364 => {
            ins.need_pfx[match.PrefixSlot.operand_size.index()] = pfe_null;
        },
        0o365 => {
            ins.need_pfx[match.PrefixSlot.address_size.index()] = pfe_null;
        },
        0o366 => {
            ins.need_pfx[match.PrefixSlot.operand_size.index()] = 0x66;
        },
        0o367 => {
            ins.need_pfx[match.PrefixSlot.address_size.index()] = 0x67;
        },
        else => return error.UnsupportedBytecode,
    }
}

fn absoluteOp(operand: *const match.Operand) bool {
    return operand.segment == match.no_seg and
        operand.wrt == match.no_seg and
        (operand.opflags & types.opflag_relative) == 0;
}

fn applyReserveBytecode(context: CalcSizeContext, ins: *const match.Instruction, operand: *const match.Operand, length: *i64) CalcSizeError!void {
    if (!absoluteOp(operand)) return error.InvalidOperandSize;
    if ((operand.opflags & types.opflag_forward) != 0) {
        context.warn(.forward_reserve_unstable);
    }

    const unit_size = generated.reserveUnitBytes(ins.opcode);
    if (unit_size == 0) return error.InvalidReserveOpcode;
    const reserve_len = try checkedMulI64(operand.offset, unit_size);
    length.* = try checkedAddI64(length.*, reserve_len);
}

fn checkedAddI64(lhs: i64, rhs: i64) CalcSizeError!i64 {
    const result = @addWithOverflow(lhs, rhs);
    if (result[1] != 0) return error.SizeOverflow;
    return result[0];
}

fn checkedMulI64(lhs: i64, rhs: i64) CalcSizeError!i64 {
    const result = @mulWithOverflow(lhs, rhs);
    if (result[1] != 0) return error.SizeOverflow;
    return result[0];
}

fn strictOsizeFlags(ins: *const match.Instruction) u32 {
    return ins.opt;
}

test "calcSize walks source-backed literal bytecode for nop" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));

    try testing.expectEqual(@as(i64, 1), try calcSize(&ins));
}

test "calcSizeSpeculative returns size without mutating source instruction" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));
    const temp = ins.itemp orelse return error.UnexpectedTestResult;

    const source_op_size = ins.op_size;
    try testing.expectEqual(@as(i64, 1), calcSizeSpeculative(&ins, temp).size);
    try testing.expectEqual(source_op_size, ins.op_size);
}

test "calcSize uses source-backed op_rexflags for opcode-plus-register bytecode" {
    const testing = std.testing;
    const rax = registerByName("rax") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("push") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .register,
        .type_bits = @intCast(rax.flags),
        .basereg = rax.expr_reg,
    };
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));

    try testing.expectEqual(@as(i64, 1), try calcSize(&ins));
}

test "applyEaBytecode calls x86 process_ea for ModRM memory bytecode" {
    const testing = std.testing;
    const al = registerByName("al") orelse return error.UnexpectedTestResult;
    const ebx = registerByName("ebx") orelse return error.UnexpectedTestResult;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("mov") orelse return error.UnexpectedTestResult, 32);
    ins.operands = 2;
    ins.oprs[0] = .{
        .kind = .register,
        .type_bits = @intCast(al.flags),
        .basereg = al.expr_reg,
    };
    ins.oprs[1] = .{
        .kind = .memory,
        .type_bits = match.memory | match.bits8,
        .basereg = ebx.expr_reg,
    };

    try testing.expectEqual(@as(i64, 1), try applyEaBytecode(&ins, temp, 0o100, 0, 1, match.r_none, .scalar));
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 0), ins.ea.bytes);
    try testing.expectEqual(@as(u8, 1), ins.ea.size);
}

test "calcSize resets x86 EA and EVEX staging state" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));
    ins.evex = 0xFFFF_FFFF;
    ins.vexreg = 9;
    ins.veximm = 10;
    ins.vex_cm = 11;
    ins.vex_wlp = 12;
    ins.evex_tuple = .fv;
    ins.ea.disp8_ok = true;
    ins.ea.size = 9;

    try testing.expectEqual(@as(i64, 1), try calcSize(&ins));
    try testing.expectEqual(@as(u32, 0), ins.evex);
    try testing.expectEqual(@as(u8, 0), ins.vexreg);
    try testing.expectEqual(@as(u8, 0), ins.veximm);
    try testing.expectEqual(@as(u8, 0), ins.vex_cm);
    try testing.expectEqual(@as(u8, 0), ins.vex_wlp);
    try testing.expectEqual(match.TupleType.none, ins.evex_tuple);
    try testing.expectEqual(match.EaData{}, ins.ea);
}

test "insnEarlySetup mirrors x86 address and operand-size prefix setup" {
    const testing = std.testing;
    const bx = registerByName("bx") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = bx.expr_reg,
    };
    try insnEarlySetup(&ins);
    try testing.expectEqual(@as(u8, 16), ins.addr_size);
    try testing.expectEqual(match.p_a16, ins.prefixes[match.PrefixSlot.address_size.index()].raw());
    try testing.expectEqual(@as(u8, 32), ins.op_size);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a32 };
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_osp };
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .memory,
        .type_bits = match.mem_offs,
        .disp_size = 64,
    };
    try insnEarlySetup(&ins);
    try testing.expectEqual(@as(u8, 32), ins.addr_size);
    try testing.expectEqual(@as(u8, 16), ins.op_size);
    try testing.expect((ins.oprs[0].type_bits & match.mem_offs) != match.mem_offs);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .memory,
        .type_bits = match.memory,
        .disp_size = 16,
    };
    try testing.expectError(error.ImpossibleAddressSize, insnEarlySetup(&ins));
    try testing.expectEqual(@as(u8, 64), ins.addr_size);
}

test "insnSize wires x86 ordinary instruction setup match and calcsize" {
    const testing = std.testing;
    const r8 = registerByName("r8") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("push") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .register,
        .type_bits = @intCast(r8.flags),
        .basereg = r8.expr_reg,
    };

    const result = try insnSize(SizeTestContext{}, .{}, &ins);
    switch (result) {
        .size => |value| try testing.expectEqual(@as(i64, 2), value),
        .no_match => return error.UnexpectedTestResult,
    }
    try testing.expect(ins.itemp != null);
}

test "insnSize keeps x86 no-match result explicit" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("push") orelse return error.UnexpectedTestResult, 64);
    const result = try insnSize(SizeTestContext{}, .{}, &ins);
    switch (result) {
        .size => return error.UnexpectedTestResult,
        .no_match => |miss| try testing.expect(!miss.isSuccess()),
    }
}

test "calcSize reserve bytecode mirrors x86 absolute_op and forward warning" {
    const testing = std.testing;
    var diagnostics: CalcSizeDiagnostics = .{};
    const context: CalcSizeContext = .{ .diagnostics = &diagnostics };

    var ins = match.Instruction.init(match.opcodeByMnemonic("resw") orelse return error.UnexpectedTestResult, 64);
    var length: i64 = 3;
    const forward_symbolic: match.Operand = .{
        .kind = .immediate,
        .segment = match.no_seg,
        .wrt = match.no_seg,
        .offset = 4,
        .opflags = types.opflag_forward,
        .symbolic = true,
    };
    try applyReserveBytecode(context, &ins, &forward_symbolic, &length);
    try testing.expectEqual(@as(i64, 11), length);
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.forward_reserve_unstable));

    var bad_wrt = forward_symbolic;
    bad_wrt.wrt = 7;
    try testing.expectError(error.InvalidOperandSize, applyReserveBytecode(context, &ins, &bad_wrt, &length));

    var relative = forward_symbolic;
    relative.opflags = types.opflag_relative;
    try testing.expectError(error.InvalidOperandSize, applyReserveBytecode(context, &ins, &relative, &length));

    length = std.math.maxInt(i64);
    var one_byte = ins;
    one_byte.opcode = match.opcodeByMnemonic("resb") orelse return error.UnexpectedTestResult;
    const one: match.Operand = .{
        .kind = .immediate,
        .segment = match.no_seg,
        .wrt = match.no_seg,
        .offset = 1,
    };
    try testing.expectError(error.SizeOverflow, applyReserveBytecode(context, &one_byte, &one, &length));
}

test "calcSize treats x86 repe bytecode as size no-op" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("cmpsb") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));

    try testing.expectEqual(@as(i64, 1), try calcSize(&ins));
}

test "calcSize VEX and EVEX setup bytecodes mutate x86 staging fields" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    const xmm1 = registerByName("xmm1") orelse return error.UnexpectedTestResult;
    const reg_operand: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(xmm1.flags),
        .basereg = xmm1.expr_reg,
    };
    const imm_operand: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 0x123,
    };

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    var evex_cursor: bytecode.BytecodeCursor = .{
        .template = temp,
        .bytes = &.{ 0x01, 0x02, 0x83, 0o301 },
    };
    try applyEvexSetup(&ins, &reg_operand, &evex_cursor);
    try testing.expectEqual(rex_ev, ins.rex & rex_ev);
    try testing.expectEqual(@as(u8, @intCast(xmm1.value)), ins.vexreg);
    try testing.expectEqual(@as(u32, 0x83020162), ins.evex);
    try testing.expectEqual(match.TupleType.fv, ins.evex_tuple);
    try testing.expectEqual(@as(u8, (rv_evex << 6) | 1), ins.vex_cm);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    var vex_cursor: bytecode.BytecodeCursor = .{
        .template = temp,
        .bytes = &.{ 0x01, 0x88 },
    };
    try applyVexSetup(&ins, &imm_operand, &vex_cursor);
    try testing.expectEqual(rex_v, ins.rex & rex_v);
    try testing.expectEqual(@as(u8, 0x23), ins.veximm);
    try testing.expectEqual(@as(u8, 0x01), ins.vex_cm);
    try testing.expectEqual(@as(u8, 0x88), ins.vex_wlp);

    ins.vexreg = 7;
    var vex_no_operand_cursor: bytecode.BytecodeCursor = .{
        .template = temp,
        .bytes = &.{ 0x02, 0x03 },
    };
    try applyVexSetup(&ins, null, &vex_no_operand_cursor);
    try testing.expectEqual(@as(u8, 0), ins.vexreg);
}

test "decodeTupleType rejects invalid EVEX tuple selectors" {
    const testing = std.testing;

    try testing.expectEqual(match.TupleType.none, try decodeTupleType(0o300));
    try testing.expectEqual(match.TupleType.dup, try decodeTupleType(0o320));
    try testing.expectError(error.InvalidEvexTupleType, decodeTupleType(0o277));
    try testing.expectError(error.InvalidEvexTupleType, decodeTupleType(0o321));
}

test "calcSize operand-size helpers preserve x86 REX.W/NW behavior" {
    const testing = std.testing;
    var saw_prefix_state = false;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_osp };
    try applyO64(&ins, 0, &saw_prefix_state);
    try testing.expectEqual(@as(u32, rex_w), ins.rex & rex_w);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = ea.rex_nw;
    try testing.expectError(error.InvalidOperandSize, applyO32(&ins, 64, 0, &saw_prefix_state));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 16);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o32 };
    try applyO16(&ins, 0, &saw_prefix_state);
    try testing.expectEqual(@as(u8, 16), ins.op_size);
    try testing.expectEqual(match.p_o32, ins.prefixes[match.PrefixSlot.operand_size.index()].raw());

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 16);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o16 };
    try applyO32(&ins, 16, 0, &saw_prefix_state);
    try testing.expectEqual(@as(u8, 32), ins.op_size);
    try testing.expectEqual(match.p_o16, ins.prefixes[match.PrefixSlot.operand_size.index()].raw());

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o64 };
    try normalizeRexBeforePrefixLength(&ins);
    try testing.expectEqual(@as(u32, rex_w), ins.rex & rex_w);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = ea.rex_nw;
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o64 };
    try normalizeRexBeforePrefixLength(&ins);
    try testing.expectEqual(@as(u32, 0), ins.rex & rex_w);
}

test "calcSize applies x86 REX marker bytecodes before prefix emission" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    applyRexBytecode(&ins, 0o344);
    try testing.expectEqual(ea.rex_p | ea.rex_b, ins.rex);

    applyRexBytecode(&ins, 0o351);
    try testing.expectEqual(ea.rex_p | ea.rex_b | rex_2 | rex_w, ins.rex);
}

test "calcSize normalizes x86 REX_NH before prefix length accounting" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.rex = ea.rex_nh | ea.rex_p;
    try normalizeRexBeforePrefixLength(&ins);
    try testing.expectEqual(ea.rex_nh, ins.rex);

    ins.rex = ea.rex_nh | ea.rex_h;
    try testing.expectError(error.HighRegisterNotAllowed, normalizeRexBeforePrefixLength(&ins));
}

test "encodingPrefixLength accounts x86 VEX EVEX and REX prefix sizes" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    var lockcheck = true;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_v;
    ins.vex_cm = 1;
    try testing.expectEqual(@as(i64, 2), try encodingPrefixLength(.{}, temp, &ins, &lockcheck));

    ins.rex = rex_v | ea.rex_b;
    ins.prefixes[match.PrefixSlot.rex.index()] = match.PrefixToken.vex2;
    try testing.expectError(error.InvalidPrefixEncoding, encodingPrefixLength(.{}, temp, &ins, &lockcheck));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_ev;
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_osp };
    try testing.expectEqual(@as(i64, 4), try encodingPrefixLength(.{}, temp, &ins, &lockcheck));
    try testing.expectEqual(@as(i64, 0), try legacyPrefixLength(&ins));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = ea.rex_b;
    try testing.expectEqual(@as(i64, 1), try encodingPrefixLength(.{}, temp, &ins, &lockcheck));
    try testing.expectEqual(ea.rex_p | ea.rex_b, ins.rex);
}

test "encodingPrefixLength keeps x86 REX2 APX path as explicit context gap" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    var lockcheck = true;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_2;
    try testing.expectError(error.NeedsCpuFeatureContext, encodingPrefixLength(.{}, temp, &ins, &lockcheck));

    try testing.expectEqual(
        @as(i64, 2),
        try encodingPrefixLength(.{ .cpu_features = .{ .apx = true } }, temp, &ins, &lockcheck),
    );
    try testing.expectEqual(rex_2 | ea.rex_p, ins.rex & (rex_2 | ea.rex_p));

    ins.rex = ea.rex_b1 | ea.rex_bv;
    try testing.expectError(error.InvalidOperandSize, encodingPrefixLength(.{ .cpu_features = .{ .apx = true } }, temp, &ins, &lockcheck));
}

test "encodingPrefixLength mirrors x86 non-64-bit LOCK-as-REX.R branch" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    var lockcheck = true;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.rex = rex_l | ea.rex_r | ea.rex_p;
    try testing.expectError(error.NeedsCpuFeatureContext, encodingPrefixLength(.{}, temp, &ins, &lockcheck));

    try testing.expectEqual(
        @as(i64, 1),
        try encodingPrefixLength(.{ .cpu_features = .{ .x86_64 = true } }, temp, &ins, &lockcheck),
    );
    try testing.expect(!lockcheck);
    try testing.expectEqual(@as(u32, rex_l | ea.rex_r), ins.rex);

    lockcheck = true;
    ins.rex = rex_l | ea.rex_r | ea.rex_p;
    ins.prefixes[match.PrefixSlot.lock.index()] = match.PrefixToken.lock;
    try testing.expectError(
        error.InvalidPrefixEncoding,
        encodingPrefixLength(.{ .cpu_features = .{ .x86_64 = true } }, temp, &ins, &lockcheck),
    );
}

test "calcSize applies x86 need_pfx bytecode state for legacy prefixes" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);

    try applyPrefixIntent(&ins, 0o361);
    try testing.expectEqual(pfe_null, ins.need_pfx[match.PrefixSlot.rep.index()]);
    try testing.expectEqual(@as(i32, 0x66), ins.need_pfx[match.PrefixSlot.operand_size.index()]);
    try testing.expectEqual(@as(i64, 1), try legacyPrefixLength(&ins));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o16 };
    try applyPrefixIntent(&ins, 0o364);
    try testing.expectEqual(@as(i64, 0), try legacyPrefixLength(&ins));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    try applyPrefixIntent(&ins, 0o367);
    try testing.expectEqual(@as(i64, 1), try legacyPrefixLength(&ins));
}

test "legacyPrefixLength counts x86 segment register prefixes" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = r_fs };
    try testing.expectEqual(@as(i32, 0x64), try prefixByte(r_fs, 64));
    try testing.expectEqual(@as(i64, 1), try legacyPrefixLength(&ins));

    ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = r_gs };
    try testing.expectEqual(@as(i32, 0x65), try prefixByte(r_gs, 64));
    try testing.expectEqual(@as(i64, 1), try legacyPrefixLength(&ins));
}

test "calcSize applies x86 legacy and REX2 opmap bytecodes" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.vex_cm = 9;
    try applyLegacyOpmap(&ins, 0o355);
    try testing.expectEqual(@as(u8, 1), ins.vex_cm);

    try applyLegacyOpmap(&ins, 0o357);
    try testing.expectEqual(@as(u8, 3), ins.vex_cm);
}

test "calcSize drops x86 PT PN branch hints for nonhintable templates" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const nonhint_temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    const hint_temp = firstTemplateWithIflag(if_jcc_hint) orelse return error.UnexpectedTestResult;
    var diagnostics: CalcSizeDiagnostics = .{};
    const context: CalcSizeContext = .{ .diagnostics = &diagnostics };

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.prefixes[match.PrefixSlot.segment.index()] = match.PrefixToken.pt;
    dropInvalidBranchHintPrefix(context, nonhint_temp, &ins);
    try testing.expectEqual(match.p_none, ins.prefixes[match.PrefixSlot.segment.index()].raw());
    try testing.expectEqual(@as(i64, 0), try legacyPrefixLength(&ins));
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.invalid_branch_hint_dropped));

    ins.prefixes[match.PrefixSlot.segment.index()] = match.PrefixToken.pn;
    dropInvalidBranchHintPrefix(context, hint_temp, &ins);
    try testing.expectEqual(match.p_pn, ins.prefixes[match.PrefixSlot.segment.index()].raw());
    try testing.expectEqual(@as(i64, 1), try legacyPrefixLength(&ins));
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.invalid_branch_hint_dropped));
}

test "calcSize context records x86 LOCK HLE and global BND post-loop behavior" {
    const testing = std.testing;
    const nop_bucket = generated.bucketByMnemonic("nop") orelse return error.UnexpectedTestResult;
    const nonlock_temp = match.templateAt(nop_bucket.template_start) orelse return error.UnexpectedTestResult;
    const bnd_temp = firstTemplateWithIflag(if_bnd) orelse return error.UnexpectedTestResult;
    var diagnostics: CalcSizeDiagnostics = .{};
    const context: CalcSizeContext = .{
        .global_bnd = true,
        .diagnostics = &diagnostics,
    };

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.prefixes[match.PrefixSlot.lock.index()] = match.PrefixToken.lock;
    checkLockPrefix(context, nonlock_temp, &ins, true);
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.instruction_not_lockable));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{ .kind = .memory, .type_bits = match.memory };
    ins.prefixes[match.PrefixSlot.rep.index()] = match.PrefixToken.xacquire;
    badHleWarn(context, &ins, 3);
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.hle_requires_lock));

    ins.oprs[0] = .{ .kind = .register, .type_bits = match.register };
    badHleWarn(context, &ins, 2);
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.hle_invalid));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    applyGlobalBnd(context, bnd_temp, &ins);
    try testing.expectEqual(match.p_bnd, ins.prefixes[match.PrefixSlot.rep.index()].raw());

    ins.prefixes[match.PrefixSlot.rep.index()] = match.PrefixToken.nobnd;
    applyGlobalBnd(context, bnd_temp, &ins);
    try testing.expectEqual(match.p_nobnd, ins.prefixes[match.PrefixSlot.rep.index()].raw());
}

const SizeTestContext = struct {
    pub fn cpuIflagField(context: @This(), field_index: usize) u32 {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return types.defaultCpuIflagField(field_index);
    }

    pub fn calcSizeSpeculative(context: @This(), ins: *const match.Instruction, temp: match.TemplateRef) match.SpeculativeSize {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return calcSizeSpeculativeImpl(ins, temp);
    }
};

fn registerByName(name: []const u8) ?@import("tables.zig").RegisterInfo {
    const registers = @import("generated_registers.zig");
    for (registers.all) |reg| {
        if (std.ascii.eqlIgnoreCase(reg.name, name)) return reg;
    }
    return null;
}

fn firstTemplateWithIflag(iflag: u32) ?match.TemplateRef {
    for (generated.templates, 0..) |_, index| {
        const temp = match.TemplateRef{ .index = index };
        if (temp.iflagTest(iflag)) return temp;
    }
    return null;
}
