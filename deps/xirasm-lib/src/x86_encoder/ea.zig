//! x86 `asm/assemble.c` EA / REX helper translation.
//!
//! This batch lands the register-to-REX helper slice used by `calcsize`
//! plus the x86 `memory_mod` displacement selector used by `process_ea`.

const std = @import("std");
const match = @import("match.zig");
const regs = @import("regs.zig");
const tables = @import("tables.zig");
const types = @import("types.zig");

pub const ea_stage_functions = [_][]const u8{ "rexflags", "op_rexflags", "op_evexflags", "ea_evex_flags", "memory_mod", "process_ea" };

pub const rex_b: u32 = types.rex_b;
pub const rex_x: u32 = types.rex_x;
pub const rex_r: u32 = types.rex_r;
pub const rex_p: u32 = types.rex_p;
pub const rex_h: u32 = types.rex_h;
pub const rex_nh: u32 = types.rex_nh;
pub const rex_b1: u32 = types.rex_b1;
pub const rex_x1: u32 = types.rex_x1;
pub const rex_r1: u32 = types.rex_r1;
pub const rex_nw: u32 = types.rex_nw;
pub const rex_bv: u32 = types.rex_bv;
pub const rex_xv: u32 = types.rex_xv;
pub const rex_rv: u32 = types.rex_rv;

pub const rex_rB: u32 = types.rex_rB;
pub const rex_rX: u32 = types.rex_rX;
pub const rex_rR: u32 = types.rex_rR;

pub const EaError = regs.RegisterError || error{
    InvalidEvexOperand,
    InvalidEvexVectorLength,
    InvalidEffectiveAddress,
    BroadcastNotAllowedWithRegisterOperand,
    EmbeddedRoundingRequiresRegister,
    SibCannotBeRipRelative,
};

pub const eaf_byteoffs: i32 = types.eaf_byteoffs;
pub const eaf_wordoffs: i32 = types.eaf_wordoffs;
pub const eaf_timestwo: i32 = types.eaf_timestwo;
pub const eaf_rel: i32 = types.eaf_rel;
pub const eaf_abs: i32 = types.eaf_abs;
pub const eaf_mib: i32 = types.eaf_mib;
pub const eaf_sib: i32 = types.eaf_sib;

pub const eah_makebase: i32 = types.eah_makebase;
pub const eah_notbase: i32 = types.eah_notbase;
pub const eah_summed: i32 = types.eah_summed;

const evex_w: u32 = types.evex_w;
const evex_ll: u32 = types.evex_ll;
const evex_rc: u32 = evex_ll;
const evex_aaa: u32 = types.evex_aaa;
const evex_b: u32 = types.evex_b;
const evex_z: u32 = types.evex_z;

const opmask_mask: u16 = types.opmask_mask;
const z_mask: u16 = types.z_mask;
const brdcast_mask: u16 = types.brdcast_mask;
const er_mask: u16 = types.staticrnd_mask;
const sae_mask: u16 = types.sae_mask;

const brc_rn: i32 = types.brc_rn;
const reg_num_esp: i32 = generatedRegisterValue("esp");
const reg_num_ebp: i32 = generatedRegisterValue("ebp");
const reg32: u64 = match.reg_gpr | match.bits32;
const reg64: u64 = match.reg_gpr | match.bits64;
const xmmreg: u64 = match.reg_class_rm_xmm | match.reg_ea;
const ymmreg: u64 = match.reg_class_rm_ymm | match.reg_ea;
const zmmreg: u64 = match.reg_class_rm_zmm | match.reg_ea;
const vector_vsib_registers: u64 = match.reg_class_vector & ~match.reg_ea;
const r_bp: i32 = generatedRegisterExprReg("bp");
const r_bx: i32 = generatedRegisterExprReg("bx");
const r_di: i32 = generatedRegisterExprReg("di");
const r_si: i32 = generatedRegisterExprReg("si");

fn isClass(class: u64, op: u64) bool {
    return (class & ~op) == 0;
}

fn genSib(scale: u8, index: u8, base: u8) u8 {
    return (scale << 6) | (index << 3) | base;
}

fn genModrm(mod_bits: u8, reg_bits: i32, rm_bits: u8) u8 {
    return (mod_bits << 6) | ((@as(u8, @intCast(reg_bits)) & 7) << 3) | (rm_bits & 7);
}

pub fn rexflags(val: i32, flags: u64, mask: u32) u32 {
    var rex: u32 = 0;

    if (val < 0 or !isClass(match.register, flags)) {
        return 0;
    }

    if ((val & 8) != 0) {
        rex |= rex_b | rex_x | rex_r;
    }
    if ((val & 16) != 0) {
        rex |= rex_b1 | rex_x1 | rex_r1;
    }

    if ((flags & match.reg_class_vector) != 0) {
        rex |= rex_bv | rex_xv | rex_rv;
    } else if (isClass(match.reg8, flags)) {
        if (isClass(match.reg_high, flags)) {
            rex |= rex_h;
        } else if (val >= 4) {
            rex |= rex_p;
        }
    }

    return rex & mask;
}

pub fn opRexflags(operand: *const match.Operand, mask: u32) EaError!u32 {
    if (!match.isRegister(operand.basereg)) return error.InvalidRegisterOperand;
    return rexflags(try regs.regval(operand), try regs.regflag(operand), mask);
}

pub fn opEvexflags(operand: *const match.Operand, mask: u32) u32 {
    return evexflags(operand.decoflags, mask);
}

pub fn eaEvexFlags(ins: *match.Instruction, operand: *const match.Operand) EaError!void {
    const er_sae_operand = if (ins.evex_brerop) |op_index| blk: {
        if (op_index >= ins.operands) return error.InvalidEvexOperand;
        break :blk &ins.oprs[op_index];
    } else null;
    const deco = if (er_sae_operand) |op| op.decoflags else 0;

    if ((deco & (er_mask | sae_mask)) != 0) {
        if (!ins.itemp_lig) {
            const vlen = evexField(evex_ll, ins.evex);
            if (vlen != 2) {
                return error.InvalidEvexVectorLength;
            }
        }

        ins.evex &= ~evex_rc;
        ins.evex ^= evex_b;
        if ((deco & er_mask) != 0) {
            ins.evex ^= evexFieldVal(evex_rc, ins.evex_rm - brc_rn);
        }
    } else if ((operand.decoflags & brdcast_mask) != 0) {
        ins.evex ^= evex_b;
    }
}

pub fn processEa(input: *match.Operand, rfield: i32, rflags: u64, ins: *match.Instruction, expected: match.EaType) EaError!void {
    const long_mode = ins.bits == 64;
    const addrbits = ins.addr_size;
    const eaflags = input.eaflags;

    ins.ea = .{};
    ins.ea.ea_type = .scalar;
    ins.ea.rex |= rexflags(rfield, rflags, rex_rR);

    if (isClass(match.register, input.type_bits)) {
        if (!match.isRegister(input.basereg)) return invalidEa(ins);

        const base_flags = try regs.regflag(input);
        const base_value = try regs.regval(input);
        if (!isClass(match.reg_ea, base_flags)) return invalidEa(ins);
        if ((input.decoflags & brdcast_mask) != 0) {
            ins.ea.ea_type = .invalid;
            return error.BroadcastNotAllowedWithRegisterOperand;
        }

        ins.ea.rex |= rexflags(base_value, base_flags, rex_rB);
        ins.ea.sib_present = false;
        ins.ea.bytes = 0;
        ins.ea.modrm = genModrm(3, rfield, @intCast(base_value & 7));
    } else {
        if ((input.decoflags & (er_mask | sae_mask)) != 0) {
            ins.ea.ea_type = .invalid;
            return error.EmbeddedRoundingRequiresRegister;
        }

        if (input.basereg == match.r_none and (input.indexreg == match.r_none or input.scale == 0)) {
            if (long_mode) {
                if (isClass(match.immediate, input.type_bits)) {
                    if ((input.eaflags & eaf_abs) == 0 and
                        (((input.eaflags & eaf_rel) != 0) or ins.default_rel))
                    {
                        input.ip_relative = true;
                    }
                }
                if (input.ip_relative and !ins.first_pass and absoluteOp(input)) {
                    input.ip_relative = false;
                    input.kind = .memory;
                    input.type_bits |= match.memory;
                }
            }

            if (long_mode and input.ip_relative and ((eaflags & eaf_sib) != 0)) {
                ins.ea.ea_type = .invalid;
                return error.SibCannotBeRipRelative;
            }

            if (((eaflags & eaf_sib) != 0) or (long_mode and !input.ip_relative)) {
                ins.ea.sib_present = true;
                ins.ea.sib = genSib(0, 4, 5);
                ins.ea.bytes = 4;
                ins.ea.modrm = genModrm(0, rfield, 4);
                ins.ea.rip = false;
            } else {
                ins.ea.sib_present = false;
                ins.ea.bytes = if (addrbits != 16) 4 else 2;
                ins.ea.modrm = genModrm(0, rfield, if (addrbits != 16) 5 else 6);
                ins.ea.rip = long_mode;
            }
        } else {
            var i = input.indexreg;
            const b = input.basereg;
            var s = input.scale;
            const known = (input.opflags & types.opflag_unknown) == 0 and input.segment == match.no_seg;
            const hb = input.hintbase;
            const ht = input.hinttype;

            if (s == 0) i = match.r_none;

            var it: i32 = match.r_none;
            var ix: u64 = 0;
            if (match.isRegister(i)) {
                it = try registerValue(i);
                ix = try registerFlags(i);
            }

            var bt: i32 = match.r_none;
            var bx: u64 = 0;
            if (match.isRegister(b)) {
                bt = try registerValue(b);
                bx = try registerFlags(b);
            }

            if (((ix | bx) & vector_vsib_registers) != 0) {
                try processVectorVsibEa(input, rfield, ins, eaflags, known, &it, &ix, &bt, &bx, &s);
            } else if (((ix | bx) & (match.bits32 | match.bits64)) != 0) {
                try processGprIndirectEa(input, rfield, ins, eaflags, known, i, b, hb, ht, &it, &ix, &bt, &bx, &s);
            } else {
                try process16BitIndirectEa(input, rfield, ins, eaflags, known, i, b, s);
            }
        }
    }

    ins.ea.size = 1 + @as(u8, @intFromBool(ins.ea.sib_present)) + ins.ea.bytes;
    if (ins.ea.ea_type != expected) return invalidEa(ins);
}

fn generatedRegisterExprReg(comptime name: []const u8) i32 {
    for (tables.all) |register| {
        if (std.mem.eql(u8, register.name, name)) return register.expr_reg;
    }
    @compileError("missing generated generated x86 register metadata for " ++ name);
}

fn generatedRegisterValue(comptime name: []const u8) i32 {
    for (tables.all) |register| {
        if (std.mem.eql(u8, register.name, name)) return register.value;
    }
    @compileError("missing generated generated x86 register metadata for " ++ name);
}

pub fn memoryMod(eaflags: i32, ins: *match.Instruction, offset: i64, known: bool, zerook: bool) u8 {
    if ((eaflags & eaf_wordoffs) != 0) {
        return 2;
    }

    ins.ea.disp8_shift = getDisp8Shift(ins);
    const shifted = offset >> @as(u6, @intCast(ins.ea.disp8_shift));
    const truncated: u8 = @truncate(@as(u64, @bitCast(shifted)));
    ins.ea.disp8 = @bitCast(truncated);
    ins.ea.disp8_ok = known and
        (@as(i64, ins.ea.disp8) << @as(u6, @intCast(ins.ea.disp8_shift))) == sext(offset, ins.addr_size);

    if ((eaflags & eaf_byteoffs) != 0) {
        return 1;
    }
    if (!known) {
        return 2;
    }
    if (offset == 0 and zerook) {
        return 0;
    }

    return if (ins.ea.disp8_ok) 1 else 2;
}

fn invalidEa(ins: *match.Instruction) EaError {
    ins.ea.ea_type = .invalid;
    return error.InvalidEffectiveAddress;
}

fn absoluteOp(operand: *const match.Operand) bool {
    return operand.segment == match.no_seg and
        operand.wrt == match.no_seg and
        (operand.opflags & types.opflag_relative) == 0 and !operand.symbolic;
}

fn processVectorVsibEa(
    input: *const match.Operand,
    rfield: i32,
    ins: *match.Instruction,
    eaflags: i32,
    known: bool,
    it: *i32,
    ix: *u64,
    bt: *i32,
    bx: *u64,
    s: *i32,
) EaError!void {
    const addrbits = ins.addr_size;
    var sok: u64 = match.bits32 | match.bits64;
    const o = truncateI32(input.offset);

    if (it.* == match.r_none or ((bx.* & vector_vsib_registers) != 0)) {
        if (s.* == 0) {
            s.* = 1;
        } else if (s.* != 1) {
            return invalidEa(ins);
        }

        swapI32(bt, it);
        swapU64(bx, ix);
    }

    if (bt.* != match.r_none) {
        if (!isClass(match.reg_gpr, bx.*)) return invalidEa(ins);
        if (isClass(reg64, bx.*) or isClass(reg32, bx.*)) {
            sok &= bx.*;
        } else {
            return invalidEa(ins);
        }
    }

    if (input.disp_size == 16 or input.disp_size == 64) return invalidEa(ins);
    if (addrbits == 16 or
        (addrbits == 32 and (sok & match.bits32) == 0) or
        (addrbits == 64 and (sok & match.bits64) == 0))
    {
        return invalidEa(ins);
    }

    ins.ea.ea_type = vectorEaType(ix.*) orelse return invalidEa(ins);
    ins.ea.rex |= rexflags(it.*, ix.*, rex_rX);
    ins.ea.rex |= rexflags(bt.*, bx.*, rex_rB);

    const index: u8 = @intCast(it.* & 7);
    const scale: u8 = switch (s.*) {
        1 => 0,
        2 => 1,
        4 => 2,
        8 => 3,
        else => return invalidEa(ins),
    };

    const base: u8 = if (bt.* == match.r_none) 5 else @intCast(bt.* & 7);
    const mod_bits: u8 = if (bt.* == match.r_none) 0 else memoryMod(eaflags, ins, o, known, base != reg_num_ebp);

    ins.ea.sib_present = true;
    ins.ea.bytes = if (bt.* == match.r_none or mod_bits == 2) 4 else mod_bits;
    ins.ea.modrm = genModrm(mod_bits, rfield, 4);
    ins.ea.sib = genSib(scale, index, base);
}

fn vectorEaType(flags: u64) ?match.EaType {
    if ((flags & (zmmreg & ~match.reg_ea)) != 0) return .zmm_vsib;
    if ((flags & (ymmreg & ~match.reg_ea)) != 0) return .ymm_vsib;
    if ((flags & (xmmreg & ~match.reg_ea)) != 0) return .xmm_vsib;
    return null;
}

fn processGprIndirectEa(
    input: *const match.Operand,
    rfield: i32,
    ins: *match.Instruction,
    eaflags: i32,
    known: bool,
    i: i32,
    b: i32,
    hb: i32,
    ht: i32,
    it: *i32,
    ix: *u64,
    bt: *i32,
    bx: *u64,
    s: *i32,
) EaError!void {
    const addrbits = ins.addr_size;
    var sok: u64 = match.bits32 | match.bits64;
    const o = truncateI32(input.offset);

    if (it.* != match.r_none) {
        if (isClass(reg64, ix.*) or isClass(reg32, ix.*)) {
            sok &= ix.*;
        } else {
            return invalidEa(ins);
        }
    }

    if (bt.* != match.r_none) {
        if (!isClass(match.reg_gpr, bx.*)) return invalidEa(ins);
        if (((~sok) & bx.* & match.size_mask) != 0) return invalidEa(ins);
        sok &= bx.*;
    }

    if (input.disp_size == 16 or input.disp_size == 64) return invalidEa(ins);
    if (addrbits == 16 or
        (addrbits == 32 and (sok & match.bits32) == 0) or
        (addrbits == 64 and (sok & match.bits64) == 0))
    {
        return invalidEa(ins);
    }

    if (s.* == 1 and bt.* != it.* and bt.* != match.r_none and it.* != match.r_none and
        ((hb == b and ht == eah_notbase) or (hb == i and ht == eah_makebase)))
    {
        swapI32(bt, it);
        swapU64(bx, ix);
    }

    if (bt.* == match.r_none and s.* == 1 and !(hb == i and ht == eah_notbase)) {
        bt.* = it.*;
        bx.* = ix.*;
        it.* = match.r_none;
        ix.* = 0;
    }

    if ((eaflags & eaf_mib) != 0) {
        if (it.* == match.r_none and hb == b and ht == eah_notbase) {
            it.* = bt.*;
            ix.* = bx.*;
            bt.* = match.r_none;
            bx.* = 0;
            s.* = 1;
        }
        if (ht == eah_summed and bt.* == match.r_none) {
            bt.* = it.*;
            bx.* = ix.*;
            s.* -= 1;
        }
    } else {
        if ((((s.* == 2 and it.* != reg_num_esp and
            (((eaflags & eaf_timestwo) == 0) or ht == eah_summed)) or
            s.* == 3 or s.* == 5 or s.* == 9)) and bt.* == match.r_none)
        {
            bt.* = it.*;
            bx.* = ix.*;
            s.* -= 1;
        }
        if (it.* == match.r_none and (bt.* & 7) != reg_num_esp and
            (eaflags & eaf_timestwo) != 0 and hb == b and ht == eah_notbase)
        {
            it.* = bt.*;
            ix.* = bx.*;
            bt.* = match.r_none;
            bx.* = 0;
            s.* = 1;
        }
    }

    if (s.* == 1 and it.* == reg_num_esp) {
        swapI32(it, bt);
        swapU64(ix, bx);
    }

    if (it.* == reg_num_esp or ((s.* != 1 and s.* != 2 and s.* != 4 and s.* != 8) and it.* != match.r_none)) {
        return invalidEa(ins);
    }

    ins.ea.rex |= rexflags(it.*, ix.*, rex_rX);
    ins.ea.rex |= rexflags(bt.*, bx.*, rex_rB);

    if (it.* == match.r_none and (bt.* & 7) != reg_num_esp and (eaflags & eaf_sib) == 0) {
        const rm: u8 = if (bt.* == match.r_none) 5 else @intCast(bt.* & 7);
        const mod_bits: u8 = if (bt.* == match.r_none) 0 else memoryMod(eaflags, ins, o, known, rm != reg_num_ebp);

        ins.ea.sib_present = false;
        ins.ea.bytes = if (bt.* == match.r_none or mod_bits == 2) 4 else mod_bits;
        ins.ea.modrm = genModrm(mod_bits, rfield, rm);
    } else {
        const index: u8 = if (it.* == match.r_none) blk: {
            s.* = 1;
            break :blk 4;
        } else @intCast(it.* & 7);
        const scale: u8 = switch (s.*) {
            1 => 0,
            2 => 1,
            4 => 2,
            8 => 3,
            else => return invalidEa(ins),
        };
        const base: u8 = if (bt.* == match.r_none) 5 else @intCast(bt.* & 7);
        const mod_bits: u8 = if (bt.* == match.r_none) 0 else memoryMod(eaflags, ins, o, known, base != reg_num_ebp);

        ins.ea.sib_present = true;
        ins.ea.bytes = if (bt.* == match.r_none or mod_bits == 2) 4 else mod_bits;
        ins.ea.modrm = genModrm(mod_bits, rfield, 4);
        ins.ea.sib = genSib(scale, index, base);
    }
}

fn process16BitIndirectEa(
    input: *const match.Operand,
    rfield: i32,
    ins: *match.Instruction,
    eaflags: i32,
    known: bool,
    input_i: i32,
    input_b: i32,
    s: i32,
) EaError!void {
    const addrbits = ins.addr_size;
    const o = truncateI16(input.offset);
    var i = input_i;
    var b = input_b;

    if (addrbits == 64) return invalidEa(ins);

    if ((b != match.r_none and !is16BitAddressReg(b)) or
        (i != match.r_none and !is16BitAddressReg(i)))
    {
        return invalidEa(ins);
    }

    if (input.disp_size == 32 or input.disp_size == 64) return invalidEa(ins);

    if (s != 1 and i != match.r_none) return invalidEa(ins);
    if (b == match.r_none and i != match.r_none) {
        swapI32(&b, &i);
    }
    if ((b == r_si or b == r_di) and i != match.r_none) {
        swapI32(&b, &i);
    }
    if (b == i) return invalidEa(ins);
    if (i != match.r_none and b != match.r_none and
        (i == r_bp or i == r_bx or b == r_si or b == r_di))
    {
        return invalidEa(ins);
    }
    if (b == match.r_none) return invalidEa(ins);

    const rm: u8 = if (i != match.r_none) blk: {
        if (i == r_si and b == r_bx) break :blk 0;
        if (i == r_di and b == r_bx) break :blk 1;
        if (i == r_si and b == r_bp) break :blk 2;
        if (i == r_di and b == r_bp) break :blk 3;
        return invalidEa(ins);
    } else blk: {
        if (b == r_si) break :blk 4;
        if (b == r_di) break :blk 5;
        if (b == r_bp) break :blk 6;
        if (b == r_bx) break :blk 7;
        return invalidEa(ins);
    };

    const mod_bits = memoryMod(eaflags, ins, o, known, rm != 6);
    ins.ea.sib_present = false;
    ins.ea.bytes = mod_bits;
    ins.ea.modrm = genModrm(mod_bits, rfield, rm);
}

fn is16BitAddressReg(expr_reg: i32) bool {
    return expr_reg == r_bp or expr_reg == r_bx or expr_reg == r_si or expr_reg == r_di;
}

fn registerFlags(expr_reg: i32) EaError!u64 {
    const register = regs.registerRef(expr_reg) orelse return error.MissingRegisterMetadata;
    if (register.flags < 0) return error.InvalidRegisterFlags;
    return @intCast(register.flags);
}

fn registerValue(expr_reg: i32) EaError!i32 {
    const register = regs.registerRef(expr_reg) orelse return error.MissingRegisterMetadata;
    return register.value;
}

fn truncateI32(value: i64) i32 {
    const raw: u64 = @bitCast(value);
    const low: u32 = @truncate(raw);
    return @bitCast(low);
}

fn truncateI16(value: i64) i16 {
    const raw: u64 = @bitCast(value);
    const low: u16 = @truncate(raw);
    return @bitCast(low);
}

fn swapI32(a: *i32, b: *i32) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

fn swapU64(a: *u64, b: *u64) void {
    const tmp = a.*;
    a.* = b.*;
    b.* = tmp;
}

fn evexflags(decoflags: u16, mask: u32) u32 {
    var evex: u32 = 0;

    if ((decoflags & z_mask) != 0) {
        evex |= evex_z;
    }
    if ((decoflags & opmask_mask) != 0) {
        evex |= (@as(u32, decoflags) << 24) & evex_aaa;
    }

    return evex & mask;
}

fn evexField(mask: u32, value: u32) u32 {
    return (value & mask) >> @as(u5, @intCast(@ctz(mask)));
}

fn evexFieldVal(mask: u32, value: i32) u32 {
    const shift: u5 = @intCast(@ctz(mask));
    return (@as(u32, @bitCast(value)) << shift) & mask;
}

fn getDisp8Shift(ins: *const match.Instruction) u8 {
    const has_evex_b = (ins.evex & evex_b) != 0;
    const has_evex_w: u8 = @intFromBool((ins.evex & evex_w) != 0);
    const vectlen: u8 = @intCast((ins.evex & evex_ll) >> 29);

    return switch (ins.evex_tuple) {
        .none => 0,
        .fv => if (has_evex_b) 2 + has_evex_w else vectlen + 4,
        .hv => if (has_evex_b) 2 + has_evex_w else vectlen + 3,
        .fvm => vectlen + 4,
        .t1s8 => 0,
        .t1s16 => 1,
        .t1s => 2 + has_evex_w,
        .t1f32 => 2,
        .t1f64 => 3,
        .t2 => 3 + has_evex_w,
        .t4 => 4 + has_evex_w,
        .t8 => 5 + has_evex_w,
        .hvm => vectlen + 3,
        .qvm => vectlen + 2,
        .ovm => vectlen + 1,
        .m128 => 4,
        .dup => if (vectlen == 0) 3 else vectlen + 4,
    };
}

fn sext(value: i64, bits: u8) i64 {
    if (bits == 0 or bits >= 64) return value;
    const shift: u6 = @intCast(64 - bits);
    const raw: u64 = @bitCast(value);
    const shifted: i64 = @bitCast(raw << shift);
    return shifted >> shift;
}

test "rexflags mirrors x86 register extension flags" {
    const testing = std.testing;
    const rax = tables.registerByName("rax") orelse return error.UnexpectedTestResult;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;
    const ah = tables.registerByName("ah") orelse return error.UnexpectedTestResult;

    try testing.expectEqual(@as(u32, 0), rexflags(rax.value, @intCast(rax.flags), rex_rB));
    try testing.expectEqual(rex_b, rexflags(r8.value, @intCast(r8.flags), rex_rB));
    try testing.expectEqual(rex_h, rexflags(ah.value, @intCast(ah.flags), rex_rB));
    try testing.expectEqual(@as(u32, 0), rexflags(-1, @intCast(rax.flags), rex_rB));
}

test "opRexflags reads operand basereg metadata" {
    const testing = std.testing;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;
    const operand: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(r8.flags),
        .basereg = r8.expr_reg,
    };

    try testing.expectEqual(rex_b, try opRexflags(&operand, rex_rB));
}

test "opEvexflags maps x86 decorator bits into EVEX fields" {
    const testing = std.testing;
    const operand: match.Operand = .{ .decoflags = z_mask | 3 };

    try testing.expectEqual(evex_z | (@as(u32, 3) << 24), opEvexflags(&operand, evex_z | evex_aaa));
    try testing.expectEqual(@as(u32, 0), opEvexflags(&operand, evex_b));
}

test "eaEvexFlags mirrors x86 broadcast and ER/SAE handling" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    const broadcast: match.Operand = .{ .decoflags = brdcast_mask };

    try eaEvexFlags(&ins, &broadcast);
    try testing.expectEqual(evex_b, ins.evex & evex_b);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{ .decoflags = er_mask };
    ins.evex_brerop = 0;
    ins.evex_rm = brc_rn + 2;
    try testing.expectError(error.InvalidEvexVectorLength, eaEvexFlags(&ins, &broadcast));

    ins.itemp_lig = true;
    try eaEvexFlags(&ins, &broadcast);
    try testing.expectEqual(evex_b, ins.evex & evex_b);
    try testing.expectEqual(@as(u32, 2), evexField(evex_rc, ins.evex));
}

test "processEa handles x86 direct register EA" {
    const testing = std.testing;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;
    var operand: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(r8.flags),
        .basereg = r8.expr_reg,
    };
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(@as(u8, 1), ins.ea.size);
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 0), ins.ea.bytes);
    try testing.expectEqual(genModrm(3, 2, @intCast(r8.value & 7)), ins.ea.modrm);
    try testing.expectEqual(rex_b, ins.ea.rex & rex_b);

    operand.decoflags = brdcast_mask;
    try testing.expectError(error.BroadcastNotAllowedWithRegisterOperand, processEa(&operand, 2, 0, &ins, .scalar));
}

test "processEa handles x86 pure-offset memory EA" {
    const testing = std.testing;
    var operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = match.r_none,
        .indexreg = match.r_none,
        .scale = 0,
    };
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    try processEa(&operand, 1, 0, &ins, .scalar);
    try testing.expect(ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 4), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 1, 4), ins.ea.modrm);
    try testing.expectEqual(genSib(0, 4, 5), ins.ea.sib);
    try testing.expect(!ins.ea.rip);

    var rip_operand: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .basereg = match.r_none,
        .indexreg = match.r_none,
        .eaflags = eaf_rel,
    };
    try processEa(&rip_operand, 1, 0, &ins, .scalar);
    try testing.expect(rip_operand.ip_relative);
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 4), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 1, 5), ins.ea.modrm);
    try testing.expect(ins.ea.rip);

    rip_operand.eaflags = eaf_rel | eaf_sib;
    try testing.expectError(error.SibCannotBeRipRelative, processEa(&rip_operand, 1, 0, &ins, .scalar));
}

test "processEa handles x86 32/64-bit GPR indirect EA" {
    const testing = std.testing;
    const rax = tables.registerByName("rax") orelse return error.UnexpectedTestResult;
    const rbp = tables.registerByName("rbp") orelse return error.UnexpectedTestResult;
    const rsp = tables.registerByName("rsp") orelse return error.UnexpectedTestResult;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    var operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = rax.expr_reg,
    };
    try processEa(&operand, 3, 0, &ins, .scalar);
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 0), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 3, 0), ins.ea.modrm);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = rbp.expr_reg,
    };
    try processEa(&operand, 3, 0, &ins, .scalar);
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 1), ins.ea.bytes);
    try testing.expectEqual(@as(i8, 0), ins.ea.disp8);
    try testing.expectEqual(genModrm(1, 3, 5), ins.ea.modrm);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = rsp.expr_reg,
    };
    try processEa(&operand, 3, 0, &ins, .scalar);
    try testing.expect(ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 0), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 3, 4), ins.ea.modrm);
    try testing.expectEqual(genSib(0, 4, 4), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = match.r_none,
        .indexreg = rax.expr_reg,
        .scale = 4,
        .offset = 16,
    };
    try processEa(&operand, 3, 0, &ins, .scalar);
    try testing.expect(ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 4), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 3, 4), ins.ea.modrm);
    try testing.expectEqual(genSib(2, 0, 5), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = r8.expr_reg,
    };
    try processEa(&operand, 3, 0, &ins, .scalar);
    try testing.expectEqual(rex_b, ins.ea.rex & rex_b);
    try testing.expectEqual(genModrm(0, 3, 0), ins.ea.modrm);
}

test "processEa handles x86 vector VSIB indirect EA" {
    const testing = std.testing;
    const rax = tables.registerByName("rax") orelse return error.UnexpectedTestResult;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;
    const xmm1 = tables.registerByName("xmm1") orelse return error.UnexpectedTestResult;
    const ymm2 = tables.registerByName("ymm2") orelse return error.UnexpectedTestResult;
    const zmm3 = tables.registerByName("zmm3") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    var operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = rax.expr_reg,
        .indexreg = xmm1.expr_reg,
        .scale = 4,
        .offset = 32,
    };
    try processEa(&operand, 2, 0, &ins, .xmm_vsib);
    try testing.expectEqual(match.EaType.xmm_vsib, ins.ea.ea_type);
    try testing.expect(ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 1), ins.ea.bytes);
    try testing.expectEqual(genModrm(1, 2, 4), ins.ea.modrm);
    try testing.expectEqual(genSib(2, 1, 0), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = match.r_none,
        .indexreg = ymm2.expr_reg,
        .scale = 2,
        .offset = 128,
    };
    try processEa(&operand, 2, 0, &ins, .ymm_vsib);
    try testing.expectEqual(match.EaType.ymm_vsib, ins.ea.ea_type);
    try testing.expectEqual(@as(u8, 4), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 2, 4), ins.ea.modrm);
    try testing.expectEqual(genSib(1, 2, 5), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = zmm3.expr_reg,
        .indexreg = match.r_none,
        .scale = 0,
    };
    try processEa(&operand, 2, 0, &ins, .zmm_vsib);
    try testing.expectEqual(match.EaType.zmm_vsib, ins.ea.ea_type);
    try testing.expectEqual(@as(u8, 4), ins.ea.bytes);
    try testing.expectEqual(genSib(0, 3, 5), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = r8.expr_reg,
        .indexreg = xmm1.expr_reg,
        .scale = 1,
    };
    try processEa(&operand, 2, 0, &ins, .xmm_vsib);
    try testing.expectEqual(rex_b, ins.ea.rex & rex_b);
    try testing.expectEqual(genSib(0, 1, 0), ins.ea.sib);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = xmm1.expr_reg,
        .indexreg = rax.expr_reg,
        .scale = 2,
    };
    try testing.expectError(error.InvalidEffectiveAddress, processEa(&operand, 2, 0, &ins, .xmm_vsib));
}

test "processEa handles x86 16-bit indirect EA" {
    const testing = std.testing;
    const bp = tables.registerByName("bp") orelse return error.UnexpectedTestResult;
    const bx = tables.registerByName("bx") orelse return error.UnexpectedTestResult;
    const si = tables.registerByName("si") orelse return error.UnexpectedTestResult;
    const di = tables.registerByName("di") orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 16);
    var operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = bx.expr_reg,
        .indexreg = si.expr_reg,
        .scale = 1,
    };
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expect(!ins.ea.sib_present);
    try testing.expectEqual(@as(u8, 0), ins.ea.bytes);
    try testing.expectEqual(genModrm(0, 2, 0), ins.ea.modrm);

    operand.indexreg = di.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 1), ins.ea.modrm);

    operand.basereg = bp.expr_reg;
    operand.indexreg = si.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 2), ins.ea.modrm);

    operand.indexreg = di.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 3), ins.ea.modrm);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = si.expr_reg,
    };
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 4), ins.ea.modrm);

    operand.basereg = di.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 5), ins.ea.modrm);

    operand.basereg = bp.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(@as(u8, 1), ins.ea.bytes);
    try testing.expectEqual(@as(i8, 0), ins.ea.disp8);
    try testing.expectEqual(genModrm(1, 2, 6), ins.ea.modrm);

    operand.basereg = bx.expr_reg;
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 7), ins.ea.modrm);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = match.r_none,
        .indexreg = si.expr_reg,
        .scale = 1,
    };
    try processEa(&operand, 2, 0, &ins, .scalar);
    try testing.expectEqual(genModrm(0, 2, 4), ins.ea.modrm);

    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = bx.expr_reg,
        .indexreg = si.expr_reg,
        .scale = 2,
    };
    try testing.expectError(error.InvalidEffectiveAddress, processEa(&operand, 2, 0, &ins, .scalar));

    var ins64 = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    operand = .{
        .kind = .memory,
        .type_bits = match.memory,
        .basereg = bx.expr_reg,
    };
    try testing.expectError(error.InvalidEffectiveAddress, processEa(&operand, 2, 0, &ins64, .scalar));
}

test "memoryMod mirrors x86 displacement selector" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    try testing.expectEqual(@as(u8, 0), memoryMod(0, &ins, 0, true, true));
    try testing.expectEqual(@as(u8, 1), memoryMod(0, &ins, 127, true, true));
    try testing.expectEqual(@as(u8, 2), memoryMod(0, &ins, 128, true, true));
    try testing.expectEqual(@as(i8, -128), ins.ea.disp8);
    try testing.expect(!ins.ea.disp8_ok);

    try testing.expectEqual(@as(u8, 2), memoryMod(0, &ins, 0, false, true));
    try testing.expectEqual(@as(u8, 1), memoryMod(eaf_byteoffs, &ins, 1024, true, true));
    try testing.expectEqual(@as(u8, 2), memoryMod(eaf_wordoffs, &ins, 0, true, true));
}

test "memoryMod applies x86 EVEX tuple compressed disp8 shift" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.evex_tuple = .fv;
    ins.evex = evex_b | evex_w;

    try testing.expectEqual(@as(u8, 1), memoryMod(0, &ins, 8, true, true));
    try testing.expectEqual(@as(u8, 3), ins.ea.disp8_shift);
    try testing.expectEqual(@as(i8, 1), ins.ea.disp8);
    try testing.expect(ins.ea.disp8_ok);
}
