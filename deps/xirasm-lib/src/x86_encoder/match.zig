//! x86 `asm/assemble.c` match-stage translation.
//!
//! This module owns the runtime control-flow landing point for
//! `find_match`, `matches`, and `jmp_match`. It consumes the source-backed
//! generated match tables; it does not hand-code instruction families.

const std = @import("std");
const generated = @import("generated_match_tables.zig");
const registers = @import("generated_registers.zig");
const tables = @import("tables.zig");
const types = @import("types.zig");

pub const match_stage_functions = [_][]const u8{ "find_match", "matches", "jmp_match" };

pub const max_prefix = types.max_prefix;
pub const max_operands = types.max_operands;
pub const no_seg = types.no_seg;
pub const r_none = types.r_none;
pub const expr_reg_start = types.expr_reg_start;
pub const reg_enum_limit = types.reg_enum_limit;

const prefix_enum_start = types.prefix_enum_start;

pub const p_none = types.p_none;
pub const p_any = types.p_any;
pub const p_a16 = types.p_a16;
pub const p_a32 = types.p_a32;
pub const p_a64 = types.p_a64;
pub const p_asp = types.p_asp;
pub const p_lock = types.p_lock;
pub const p_o16 = types.p_o16;
pub const p_o32 = types.p_o32;
pub const p_o64 = types.p_o64;
pub const p_osp = types.p_osp;
pub const p_rep = types.p_rep;
pub const p_repe = types.p_repe;
pub const p_repne = types.p_repne;
pub const p_repnz = types.p_repnz;
pub const p_repz = types.p_repz;
pub const p_wait = types.p_wait;
pub const p_xacquire = types.p_xacquire;
pub const p_xrelease = types.p_xrelease;
pub const p_bnd = types.p_bnd;
pub const p_nobnd = types.p_nobnd;
pub const p_rex = types.p_rex;
pub const p_rex2 = types.p_rex2;
pub const p_evex = types.p_evex;
pub const p_vex = types.p_vex;
pub const p_vex3 = types.p_vex3;
pub const p_vex2 = types.p_vex2;
pub const p_nf = types.p_nf;
pub const p_zu = types.p_zu;
pub const p_pt = types.p_pt;
pub const p_pn = types.p_pn;

pub const optim_no_jcc_relax = types.optim_no_jcc_relax;
pub const optim_no_jmp_relax = types.optim_no_jmp_relax;
pub const optim_strict_instr = types.optim_strict_instr;

pub const register = types.register;
pub const immediate = types.immediate;
pub const regmem = types.regmem;
pub const memory = types.memory;
pub const to = types.to;
pub const colon = types.colon;
pub const reg_class_shift = types.reg_class_shift;
pub const subclass_shift = types.subclass_shift;
pub const size_shift = types.size_shift;
pub const size_mask = types.size_mask;
pub const bits8 = types.bits8;
pub const bits16 = types.bits16;
pub const bits32 = types.bits32;
pub const bits64 = types.bits64;
pub const bits80 = types.bits80;
pub const bits128 = types.bits128;
pub const bits256 = types.bits256;
pub const bits512 = types.bits512;
pub const far = types.far;
pub const near = types.near;
pub const short = types.short;
pub const abs = types.abs;

pub const reg_class_cdt = types.reg_class_cdt;
pub const reg_class_gpr = types.reg_class_gpr;
pub const reg_class_sreg = types.reg_class_sreg;
pub const reg_class_fpureg = types.reg_class_fpureg;
pub const reg_class_rm_mmx = types.reg_class_rm_mmx;
pub const reg_class_rm_xmm = types.reg_class_rm_xmm;
pub const reg_class_rm_ymm = types.reg_class_rm_ymm;
pub const reg_class_rm_zmm = types.reg_class_rm_zmm;
pub const reg_class_opmask = types.reg_class_opmask;
pub const reg_class_bnd = types.reg_class_bnd;
pub const reg_class_rm_tmm = types.reg_class_rm_tmm;
pub const reg_class_vector = types.reg_class_vector;
pub const reg_ea = types.reg_ea;
pub const rn_l16 = types.rn_l16;
pub const rm_l16 = types.rm_l16;
pub const rm_zero = types.rm_zero;
pub const rm_nzero = types.rm_nzero;
pub const rm_sel = types.rm_sel;
pub const reg_gpr = types.reg_gpr;
pub const rm_gpr = types.rm_gpr;
pub const rm_mmx = types.rm_mmx;
pub const rm_xmm = types.rm_xmm;
pub const rm_ymm = types.rm_ymm;
pub const rm_zmm = types.rm_zmm;
pub const rm_opmask = types.rm_opmask;
pub const rm_bnd = types.rm_bnd;
pub const reg16 = types.reg16;
pub const reg32 = types.reg32;
pub const reg64 = types.reg64;
pub const reg8 = types.reg8;
pub const reg_high = types.reg_high;
pub const mem_offs = types.mem_offs;
pub const memory_any = types.memory_any;
pub const xmem = types.xmem;
pub const ymem = types.ymem;
pub const zmem = types.zmem;
pub const imm_normal = types.imm_normal;
pub const unity = types.unity;
pub const sbyteword = types.sbyteword;
pub const sbytedword = types.sbytedword;
pub const sdword_operand = types.sdword_operand;
pub const udword = types.udword;
pub const fourbits = types.fourbits;
pub const imm_known = types.imm_known;

const optype_shift = types.optype_shift;
const optype_bits = types.optype_bits;
const modifier_shift = types.modifier_shift;
const modifier_bits = types.modifier_bits;
const reg_class_bits = types.reg_class_bits;
const regset_shift = types.regset_shift;
const regset_bits = types.regset_bits;

const regset_mask = types.regset_mask;
const strict = types.strict;
const byte_ext_mask = types.byte_ext_mask;
const dword_ext_mask = types.dword_ext_mask;
const sdword = types.sdword;
const opflag_unknown = types.opflag_unknown;

const if_sm0 = types.if_sm0;
const if_ar0 = types.if_ar0;
const if_sb = types.if_sb;
const if_nwsize = types.if_nwsize;
const if_osize = types.if_osize;
const if_asize = types.if_asize;
const if_anysize = types.if_anysize;
const if_sx = types.if_sx;
const if_sdword = types.if_sdword;
const if_jmp_relax = types.if_jmp_relax;
const if_opt = types.if_opt;
const if_latevex = types.if_latevex;
const if_norex = types.if_norex;
const if_noapx = types.if_noapx;
const if_nf = types.if_nf;
const if_nf_r = types.if_nf_r;
const if_zu = types.if_zu;
const if_nolong = types.if_nolong;
const if_long = types.if_long;
const if_nohle = types.if_nohle;
const if_bnd = types.if_bnd;
const if_rex2 = types.if_rex2;
const if_fl = types.if_fl;
const if_vex = types.if_vex;
const if_evex = types.if_evex;
const if_apx = types.if_apx;
const if_cpu_field = types.if_cpu_field;
const if_field_count = types.if_field_count;
const if_cpu_level_mask = types.if_cpu_level_mask;

const ifm_sm0 = types.ifm_sm0;
const ifm_sm1 = types.ifm_sm1;
const ifm_sm2 = types.ifm_sm2;
const ifm_sm3 = types.ifm_sm3;
const ifm_sm4 = types.ifm_sm4;
const ifm_ar0 = types.ifm_ar0;
const ifm_ar1 = types.ifm_ar1;
const ifm_ar2 = types.ifm_ar2;
const ifm_ar3 = types.ifm_ar3;
const ifm_ar4 = types.ifm_ar4;
const ifm_sb = types.ifm_sb;
const ifm_sw = types.ifm_sw;
const ifm_sd = types.ifm_sd;
const ifm_sq = types.ifm_sq;
const ifm_st = types.ifm_st;
const ifm_so = types.ifm_so;
const ifm_sy = types.ifm_sy;
const ifm_sz = types.ifm_sz;
const ifm_nwsize = types.ifm_nwsize;
const ifm_osize = types.ifm_osize;
const ifm_asize = types.ifm_asize;
const ifm_anysize = types.ifm_anysize;
const ifm_sx = types.ifm_sx;

const if_tsmask = types.if_tsmask;
const if_smask = types.if_smask;
const if_armask = types.if_armask;
const if_smmask = types.if_smmask;

const opmask_mask = types.opmask_mask;
const z_mask = types.z_mask;
const brdcast_mask = types.brdcast_mask;
const staticrnd_mask = types.staticrnd_mask;
const sae_mask = types.sae_mask;
const brsize_mask = types.brsize_mask;
const brnum_shift = types.brnum_shift;
const brnum_mask = types.brnum_mask;

const jsize_mask = types.jsize_mask;
const msize_mask = types.msize_mask;

pub const PrefixSlot = types.PrefixSlot;
pub const PrefixToken = types.PrefixToken;
pub const Location = types.Location;
pub const SpeculativeSize = types.SpeculativeSize;
pub const OperandKind = types.OperandKind;
pub const EaType = types.EaType;
pub const TupleType = types.TupleType;
pub const EaData = types.EaData;
pub const Operand = types.Operand;
pub const Instruction = types.Instruction;
pub const MatchResult = types.MatchResult;
pub const TemplateRef = tables.TemplateRef;
pub const opcodeByMnemonic = tables.opcodeByMnemonic;
pub const templateAt = tables.templateAt;

fn isClass(class: u64, op: u64) bool {
    return types.isClass(class, op);
}

pub fn isRegister(reg: i32) bool {
    return types.isRegister(reg);
}

fn hasPrefix(ins: *const Instruction, pos: PrefixSlot, prefix: i32) bool {
    return ins.prefixes[pos.index()].raw() == prefix;
}

fn isPower2(value: u64) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

fn modeToOp(bits_mode: u8) u64 {
    return @as(u64, bits_mode) << (size_shift - 3);
}

fn brsizeToSize(brbits: u16) u64 {
    return @as(u64, brbits & brsize_mask) << (size_shift - 8);
}

fn getBroadcastNum(opflags: u64, brsize: u64) ?u32 {
    const opsize = (opflags & size_mask) >> size_shift;
    if (brsize == 0 or brsize > bits64) return null;
    const shift: u6 = if (opsize > (bits64 >> size_shift)) 1 else 0;
    return @intCast(((opsize / (bits64 >> size_shift)) * (bits64 / brsize)) >> shift);
}

fn cpuIflagTest(context: anytype, bit: u32) bool {
    const field_index: usize = @intCast(bit >> 5);
    if (field_index >= if_field_count) return false;
    const mask = @as(u32, 1) << @as(u5, @intCast(bit & 31));
    return (context.cpuIflagField(field_index) & mask) != 0;
}

fn cpuLevelBits(context: anytype) u32 {
    return context.cpuIflagField(if_cpu_field) & if_cpu_level_mask;
}

const CpuLevelOrder = enum {
    below,
    equal,
    above,
};

fn ifcomp(a: u32, b: u32) CpuLevelOrder {
    if (a > b) return .above;
    if (a < b) return .below;
    return .equal;
}

fn iflagCmpCpuLevel(itemp: TemplateRef, context: anytype) CpuLevelOrder {
    return ifcomp(itemp.cpuLevelBits(), cpuLevelBits(context));
}

pub fn findMatch(context: anytype, instruction: *Instruction) MatchResult {
    const bits_mode = instruction.bits;
    const rex = instruction.prefixes[PrefixSlot.rex.index()];
    var best: ?TemplateRef = null;
    var merr: MatchResult = .inval_op;
    var besti: i32 = -1;

    instruction.itemp = null;
    instruction.itempindex = -1;

    if (bits_mode != 64 and (rex.raw() == p_rex or rex.raw() == p_rex2)) {
        return .enc_mismatch;
    }

    if (instruction.opcode >= generated.instruction_buckets.len) return .inval_op;
    const bucket = generated.instruction_buckets[instruction.opcode];
    if (!bucket.hasTemplates()) return .inval_op;

    const start: usize = @intCast(bucket.template_start);
    const end = start + @as(usize, bucket.template_count);
    var local_index: i32 = 0;
    for (start..end) |global_index| {
        const temp = TemplateRef{ .index = global_index };
        const m = matches(context, temp, instruction);
        if (m.rank() > merr.rank() or
            (m.isSuccess() and m == merr and best != null and preferSameRankMatch(best.?, temp)))
        {
            best = temp;
            besti = local_index;
            merr = m;
            if (merr == .ok_good and !shouldContinueExactOverrideSearch(temp)) break;
        } else if (merr == .ok_good and best != null and !shouldContinueExactOverrideSearch(best.?)) {
            break;
        }
        local_index += 1;
    }

    if (merr.rank() >= MatchResult.ok_first.rank()) {
        merr = .ok_good;
        instruction.itemp = best;
        instruction.itempindex = besti;
    }

    return merr;
}

fn shouldContinueExactOverrideSearch(itemp: TemplateRef) bool {
    return itemp.iflagTest(if_opt) and
        isReg64Rm8Template(itemp) and
        !templateHasO64Bytecode(itemp);
}

fn preferSameRankMatch(current: TemplateRef, candidate: TemplateRef) bool {
    if (!current.iflagTest(if_opt) or candidate.iflagTest(if_opt)) return false;
    if (!sameOperandShape(current, candidate)) return false;

    // source-chain data has OPT byte-size aliases for reg64,rm8 forms and later exact
    // o64 rows for the same operands. The exact W row must win, while unrelated
    // OPT rows such as RDPID reg64 keep their shorter first-match encoding.
    return isReg64Rm8Template(candidate) and
        !templateHasO64Bytecode(current) and
        templateHasO64Bytecode(candidate);
}

fn sameOperandShape(a: TemplateRef, b: TemplateRef) bool {
    if (a.operandCount() != b.operandCount()) return false;
    for (0..a.operandCount()) |i| {
        if (a.operandTypeBits(i) != b.operandTypeBits(i)) return false;
        if (a.operandDecoratorRawBits(i) != b.operandDecoratorRawBits(i)) return false;
    }
    return true;
}

fn isReg64Rm8Template(itemp: TemplateRef) bool {
    if (itemp.operandCount() != 2) return false;
    const op0 = itemp.operandTypeBits(0);
    const op1 = itemp.operandTypeBits(1);
    return isClass(register, op0) and
        (op0 & size_mask) == bits64 and
        isClass(regmem, op1) and
        (op1 & size_mask) == bits8;
}

fn templateHasO64Bytecode(itemp: TemplateRef) bool {
    const bytes = generated.bytecodeForTemplate(itemp.raw()) orelse return false;
    for (bytes) |byte| {
        if (byte == 0o324) return true;
    }
    return false;
}

pub fn opcodeHasRelaxTemplate(opcode: u16) bool {
    if (opcode >= generated.instruction_buckets.len) return false;
    const bucket = generated.instruction_buckets[opcode];
    if (!bucket.hasTemplates()) return false;

    const start: usize = @intCast(bucket.template_start);
    const end = start + @as(usize, bucket.template_count);
    for (start..end) |global_index| {
        if ((TemplateRef{ .index = global_index }).iflagTest(if_jmp_relax)) return true;
    }
    return false;
}

pub fn matches(context: anytype, itemp: TemplateRef, ins: *const Instruction) MatchResult {
    const bits_mode = ins.bits;
    const oprs: usize = ins.operands;
    var operand_size: [max_operands]u64 = @splat(@as(u64, 0));
    var tsize: [max_operands]u64 = @splat(@as(u64, 0));
    var itype: [max_operands]u64 = @splat(@as(u64, 0));

    if (itemp.opcode() != ins.opcode) return .inval_op;
    if (itemp.operandCount() != oprs) return .inval_op;
    if ((ins.opt & optim_strict_instr) != 0 and itemp.iflagTest(if_opt)) return .inval_op;

    switch (ins.prefixes[PrefixSlot.rex.index()].raw()) {
        p_evex => {
            if (!itemp.iflagTest(if_evex)) return .enc_mismatch;
        },
        p_vex, p_vex2, p_vex3 => {
            if (!itemp.iflagTest(if_vex)) return .enc_mismatch;
        },
        p_rex => {
            if (bits_mode != 64 or
                itemp.iflagTest(if_norex) or
                itemp.iflagTest(if_vex) or
                itemp.iflagTest(if_evex) or
                itemp.iflagTest(if_rex2))
            {
                return .enc_mismatch;
            }
        },
        p_rex2 => {
            if (bits_mode != 64 or itemp.iflagTest(if_noapx) or itemp.iflagTest(if_evex)) {
                return .enc_mismatch;
            }
        },
        else => {
            if (itemp.iflagTest(if_evex)) {
                if (!cpuIflagTest(context, if_evex)) return .bad_cpu;
            } else if (itemp.iflagTest(if_vex)) {
                if (!cpuIflagTest(context, if_vex)) {
                    return .bad_cpu;
                } else if (itemp.iflagTest(if_latevex)) {
                    if (!cpuIflagTest(context, if_latevex) and cpuIflagTest(context, if_evex)) return .bad_cpu;
                } else if (itemp.iflagTest(if_rex2)) {
                    if (bits_mode != 64 or !cpuIflagTest(context, if_apx)) return .bad_cpu;
                }
            }
        },
    }

    for (0..oprs) |i| {
        const op = ins.oprs[i];
        const ttype = itemp.operandTypeBits(i);

        operand_size[i] = op.type_bits & msize_mask;
        itype[i] = op.type_bits - operand_size[i];

        if ((op.type_bits & ~ttype & (colon | to)) != 0) return .inval_op;
        if (op.iflag != 0 and !itemp.hasOperandIflag(op.iflag)) return .wrong_imm;
    }

    var op_size = ins.op_size;
    if (bits_mode == 64 and itemp.iflagTest(if_nwsize) and op_size == 32) {
        op_size = bits_mode;
    }
    const opsize = modeToOp(op_size);

    const has_anysize = itemp.iflagTest(if_anysize);
    const has_sx = itemp.iflagTest(if_sx);

    for (0..oprs) |i| {
        const ttype = itemp.operandTypeBits(i);
        const deco = ins.oprs[i].decoflags;
        const ideco = itemp.operandDecoratorRawBits(i);
        const is_broadcast = (deco & brdcast_mask) != 0;

        if (!is_broadcast) {
            tsize[i] = ttype & msize_mask;
        } else {
            const ideco_brsize = ideco & brsize_mask;
            if ((~ideco & brdcast_mask) != 0) return .br_not_here;
            tsize[i] = if (ideco_brsize != 0) brsizeToSize(ideco_brsize) else 0;
        }

        if ((ttype & (near | short)) != 0) {
            if (operand_size[i] == bits8) {
                itype[i] |= short;
                operand_size[i] = 0;
            }

            if ((itype[i] & short) != 0) {
                itype[i] &= ~near;
            }

            if ((itype[i] & (far | short)) == 0) {
                itype[i] |= ttype & near;
            }

            if ((ttype & (near | short)) == (near | short) and (itype[i] & (far | abs)) == 0) {
                itype[i] |= near | short;
            }
        }

        if ((itype[i] & ttype & immediate) != 0) {
            if (operand_size[i] == bits8) {
                if ((ttype & byte_ext_mask) != 0) {
                    operand_size[i] = tsize[i];
                    itype[i] |= byte_ext_mask;
                }
            } else if (operand_size[i] == bits32 and (ttype & dword_ext_mask) != 0) {
                operand_size[i] = tsize[i];
            }

            if (!itemp.iflagTest(if_sdword)) {
                itype[i] |= sdword;
            }
        }

        if ((ttype & ~itype[i] & ~(msize_mask | regset_mask)) != 0) return .inval_op;
        if (((~ideco & deco) & opmask_mask) != 0) return .mask_not_here;
        if (((~ideco & deco) & (z_mask | staticrnd_mask | sae_mask)) != 0) return .deco_not_here;

        if (((~ttype & itype[i]) & regset_mask) != 0) {
            return if ((ttype & regset_mask) != 0) .reg_set_size else .reg_set;
        }
    }

    var arsize = itemp.baseSizeMask();
    if (itemp.usesOperandSize()) {
        arsize = opsize;
    } else if (itemp.usesAddressSize()) {
        arsize = modeToOp(ins.addr_size);
    }

    const armask = itemp.arxMask();
    const smmask = itemp.smxMask();

    if (!has_sx) {
        for (0..oprs) |i| {
            const bit = @as(u32, 1) << @as(u3, @intCast(i));
            if (operand_size[i] == 0) {
                if (isClass(register, itype[i]) and tsize[i] != 0) {
                    operand_size[i] = tsize[i];
                } else if ((armask & bit) != 0) {
                    operand_size[i] = arsize;
                }
            }
        }
    }

    var smsize = msize_mask;
    var sm_missing = false;
    if (smmask != 0) {
        var nosizemask: u32 = 0;
        for (0..oprs) |i| {
            const bit = @as(u32, 1) << @as(u3, @intCast(i));
            if (operand_size[i] != 0) {
                if ((smmask & bit) != 0) smsize &= operand_size[i];
            } else if (tsize[i] != 0 and !isClass(register, itype[i])) {
                nosizemask |= bit;
            }
        }
        sm_missing = (smmask & ~nosizemask) == 0;
    }

    for (0..oprs) |i| {
        const ttype = itemp.operandTypeBits(i);
        const deco = ins.oprs[i].decoflags;
        const ideco = itemp.operandDecoratorRawBits(i);
        const is_broadcast = (deco & brdcast_mask) != 0;
        const has_ar = ((armask >> @as(u5, @intCast(i))) & 1) != 0;
        const has_sm = ((smmask >> @as(u5, @intCast(i))) & 1) != 0;
        const type_bits = itype[i];
        const is_reg = isClass(register, type_bits);

        if (tsize[i] != 0) {
            if (operand_size[i] != tsize[i]) {
                if (has_ar and has_anysize) {
                    if (has_sm) smsize &= tsize[i];
                    continue;
                }

                if (has_ar and has_sx and !is_reg) return .op_size_inval;

                if (operand_size[i] != 0) {
                    return if (is_reg) .inval_op else .op_size_inval;
                }
            }

            if (has_sm) smsize &= tsize[i];
        } else if (has_sx and has_ar and operand_size[i] != 0) {
            return .op_size_inval;
        }

        if (isClass(reg_high, type_bits) and ins.prefixes[PrefixSlot.rex.index()].raw() != 0) {
            return .inval_op;
        }

        if (is_broadcast) {
            const ideco_brsize = ideco & brsize_mask;
            var brcast_num: u32 = 0;
            if (ideco_brsize != 0) {
                brcast_num = getBroadcastNum(ttype, tsize[i]) orelse return .br_num_mismatch;
            }

            const expected = @as(u32, 2) << @as(u5, @intCast((deco & brnum_mask) >> brnum_shift));
            if (brcast_num != expected) return .br_num_mismatch;
        }
    }

    if (smmask != 0) {
        if (smsize == 0) return .op_size_mismatch;
        if (!isPower2(smsize) or (has_sx and sm_missing)) return .op_size_missing;
    }

    if (iflagCmpCpuLevel(itemp, context) == .above) return .bad_cpu;

    if (itemp.iflagTest(if (bits_mode == 64) if_nolong else if_long)) return .bad_mode;

    if (itemp.iflagTest(if_nohle) and
        (hasPrefix(ins, .rep, p_xacquire) or hasPrefix(ins, .rep, p_xrelease)))
    {
        return .bad_hle;
    }

    if (hasPrefix(ins, .nf, p_nf)) {
        if (!itemp.iflagTest(if_nf) and (itemp.iflagTest(if_fl) or (ins.opt & optim_strict_instr) != 0)) {
            return .bad_nf;
        }
    } else if (itemp.iflagTest(if_nf_r)) {
        return .req_nf;
    }

    if (hasPrefix(ins, .zu, p_zu)) {
        if (!itemp.iflagTest(if_zu)) return .bad_zu;
        if ((ins.oprs[0].type_bits & register) == 0) return .mem_zu;
    }

    if (!itemp.iflagTest(if_bnd) and
        (hasPrefix(ins, .rep, p_bnd) or hasPrefix(ins, .rep, p_nobnd)))
    {
        return .bad_bnd;
    } else if (itemp.iflagTest(if_bnd) and
        (hasPrefix(ins, .rep, p_repne) or hasPrefix(ins, .rep, p_repnz)))
    {
        return .bad_repne;
    }

    if (itemp.iflagTest(if_jmp_relax)) {
        return jmpMatch(context, ins, itemp);
    }

    return .ok_good;
}

pub fn jmpMatch(context: anytype, ins: *const Instruction, temp: TemplateRef) MatchResult {
    const op0 = ins.oprs[0];
    if ((op0.type_bits & strict) != 0) return .inval_op;

    const opt = ins.opt;
    if ((opt & (optim_no_jcc_relax | optim_no_jmp_relax)) != 0) {
        switch (temp.bytecodeFirst()) {
            0o370 => {
                if ((opt & optim_no_jcc_relax) != 0) return .inval_op;
            },
            0o371 => {
                if ((opt & optim_no_jmp_relax) != 0) return .inval_op;
            },
            else => return .inval_op,
        }
    }

    if ((op0.opflags & opflag_unknown) != 0) return .ok_good;
    if (op0.segment != ins.loc.segment) return .inval_op;

    const initial_delta = @subWithOverflow(op0.offset, ins.loc.offset);
    if (initial_delta[1] != 0) return .inval_op;
    var delta = initial_delta[0];
    if (delta < -128 + 2 or delta > 127 + 15) {
        return .inval_op;
    } else if (delta >= -128 + 15 and delta <= 127 + 2) {
        // Guaranteed rel8 match; x86 stays on the fast path here.
    } else {
        const instr_size = switch (context.calcSizeSpeculative(ins, temp)) {
            .size => |value| value,
            .would_error => return .inval_op,
        };
        const adjusted_delta = @subWithOverflow(delta, instr_size);
        if (adjusted_delta[1] != 0) return .inval_op;
        delta = adjusted_delta[0];
        if (delta < std.math.minInt(i8) or delta > std.math.maxInt(i8)) return .inval_op;
        const narrowed: i8 = @intCast(delta);
        if (@as(i64, narrowed) != delta) return .inval_op;
    }

    return .ok_good;
}

fn registerTypeBits(name: []const u8) ?u64 {
    for (registers.all) |reg| {
        if (std.ascii.eqlIgnoreCase(reg.name, name)) return @intCast(reg.flags);
    }
    return null;
}

const TestMatchContext = struct {
    fn cpuIflagField(context: @This(), field_index: usize) u32 {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return types.defaultCpuIflagField(field_index);
    }

    fn calcSizeSpeculative(context: @This(), ins: *const Instruction, temp: TemplateRef) SpeculativeSize {
        if (@sizeOf(@TypeOf(context)) > 0 or @sizeOf(@TypeOf(ins.*)) > 0 or @sizeOf(@TypeOf(temp)) > 0) {}
        return .{ .size = 2 };
    }
};

test "findMatch consumes generated buckets for zero-operand templates" {
    const testing = std.testing;

    var ins = Instruction.init(opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    const result = findMatch(TestMatchContext{}, &ins);

    try testing.expectEqual(MatchResult.ok_good, result);
    try testing.expect(ins.itemp != null);
    try testing.expectEqual(@as(usize, 0), ins.itemp.?.operandCount());
}

test "findMatch matches operand templates without hand-written opcode families" {
    const testing = std.testing;
    const rax_flags = registerTypeBits("rax") orelse return error.UnexpectedTestResult;

    var ins = Instruction.init(opcodeByMnemonic("push") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .register,
        .type_bits = rax_flags,
    };

    const result = findMatch(TestMatchContext{}, &ins);

    try testing.expectEqual(MatchResult.ok_good, result);
    try testing.expect(ins.itemp != null);
    try testing.expectEqual(@as(usize, 1), ins.itemp.?.operandCount());
}

test "findMatch matches x86 selector rm operands from generated flags" {
    const testing = std.testing;
    const ax_flags = registerTypeBits("ax") orelse return error.UnexpectedTestResult;
    const bx_flags = registerTypeBits("bx") orelse return error.UnexpectedTestResult;

    var ins = Instruction.init(opcodeByMnemonic("lar") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 2;
    ins.oprs[0] = .{ .kind = .register, .type_bits = ax_flags };
    ins.oprs[1] = .{ .kind = .register, .type_bits = bx_flags };

    const result = findMatch(TestMatchContext{}, &ins);
    try testing.expectEqual(MatchResult.ok_good, result);
    try testing.expect(ins.itemp != null);
}

test "findMatch prefers exact reg64 rm8 o64 override over OPT alias" {
    const testing = std.testing;
    const opcode = opcodeByMnemonic("crc32") orelse return error.UnexpectedTestResult;
    const r9_flags = registerTypeBits("r9") orelse return error.UnexpectedTestResult;
    const bucket = generated.instruction_buckets[opcode];
    const start: usize = @intCast(bucket.template_start);
    const end = start + @as(usize, bucket.template_count);
    var opt_alias: ?TemplateRef = null;
    var exact_o64: ?TemplateRef = null;
    for (start..end) |template_index| {
        const template = TemplateRef{ .index = template_index };
        if (!isReg64Rm8Template(template)) continue;
        if (template.iflagTest(if_opt) and !templateHasO64Bytecode(template)) {
            opt_alias = template;
        } else if (!template.iflagTest(if_opt) and templateHasO64Bytecode(template)) {
            exact_o64 = template;
        }
    }
    const opt_template = opt_alias orelse return error.UnexpectedTestResult;
    const exact_template = exact_o64 orelse return error.UnexpectedTestResult;

    var ins = Instruction.init(opcode, 64);
    ins.operands = 2;
    ins.oprs[0] = .{ .kind = .register, .type_bits = r9_flags };
    ins.oprs[1] = .{ .kind = .memory, .type_bits = opt_template.operandTypeBits(1) };

    try testing.expect(sameOperandShape(opt_template, exact_template));
    try testing.expect(preferSameRankMatch(opt_template, exact_template));
    try testing.expectEqual(MatchResult.ok_good, matches(TestMatchContext{}, opt_template, &ins));
    try testing.expectEqual(MatchResult.ok_good, matches(TestMatchContext{}, exact_template, &ins));
    try testing.expectEqual(MatchResult.ok_good, findMatch(TestMatchContext{}, &ins));
    try testing.expectEqual(exact_template.index, ins.itemp.?.index);
}

test "findMatch keeps register-only OPT aliases first" {
    const testing = std.testing;
    const opcode = opcodeByMnemonic("rdpid") orelse return error.UnexpectedTestResult;
    const rax_flags = registerTypeBits("rax") orelse return error.UnexpectedTestResult;

    var ins = Instruction.init(opcode, 64);
    ins.operands = 1;
    ins.oprs[0] = .{ .kind = .register, .type_bits = rax_flags };

    try testing.expectEqual(MatchResult.ok_good, findMatch(TestMatchContext{}, &ins));
    const selected = ins.itemp orelse return error.UnexpectedTestResult;
    try testing.expect(selected.iflagTest(if_opt));
    try testing.expect(!templateHasO64Bytecode(selected));
}
