//! x86 `asm.h` / `insns.h` / `opflags.h` shared x86 domain types.

const std = @import("std");
const generated = @import("generated_match_tables.zig");
const generated_registers = @import("generated_registers.zig");
const tables = @import("tables.zig");

pub const max_prefix: usize = generated.maxprefix;
pub const max_operands: usize = generated.max_operands;
pub const no_seg: i32 = generated.no_seg;
// x86 `assemble.c` uses -1 as ordinary EA/register absence state.
pub const r_none: i32 = -1;
pub const expr_reg_start: i32 = generated.expr_reg_start;
pub const reg_enum_limit: i32 = generated.reg_enum_limit;

pub const prefix_enum_start: i32 = generated.prefix_enum_start;

pub const p_none: i32 = generated.p_none;
pub const p_any: i32 = generated.p_any;
pub const p_a16: i32 = generated.p_a16;
pub const p_a32: i32 = generated.p_a32;
pub const p_a64: i32 = generated.p_a64;
pub const p_asp: i32 = generated.p_asp;
pub const p_lock: i32 = generated.p_lock;
pub const p_o16: i32 = generated.p_o16;
pub const p_o32: i32 = generated.p_o32;
pub const p_o64: i32 = generated.p_o64;
pub const p_osp: i32 = generated.p_osp;
pub const p_rep: i32 = generated.p_rep;
pub const p_repe: i32 = generated.p_repe;
pub const p_repne: i32 = generated.p_repne;
pub const p_repnz: i32 = generated.p_repnz;
pub const p_repz: i32 = generated.p_repz;
pub const p_wait: i32 = generated.p_wait;
pub const p_xacquire: i32 = generated.p_xacquire;
pub const p_xrelease: i32 = generated.p_xrelease;
pub const p_bnd: i32 = generated.p_bnd;
pub const p_nobnd: i32 = generated.p_nobnd;
pub const p_rex: i32 = generated.p_rex;
pub const p_rex2: i32 = generated.p_rex2;
pub const p_evex: i32 = generated.p_evex;
pub const p_vex: i32 = generated.p_vex;
pub const p_vex3: i32 = generated.p_vex3;
pub const p_vex2: i32 = generated.p_vex2;
pub const p_nf: i32 = generated.p_nf;
pub const p_zu: i32 = generated.p_zu;
pub const p_pt: i32 = generated.p_pt;
pub const p_pn: i32 = generated.p_pn;

pub const optim_no_jcc_relax: u32 = generated.optim_no_jcc_relax;
pub const optim_no_jmp_relax: u32 = generated.optim_no_jmp_relax;
pub const optim_strict_instr: u32 = generated.optim_strict_instr;
pub const optim_strict_oper: u32 = generated.optim_strict_oper;
pub const optim_disable_fwref: u32 = generated.optim_disable_fwref;
pub const optim_strict_osize: u32 = generated.optim_strict_osize;

pub const register: u64 = generated.register;
pub const immediate: u64 = generated.immediate;
pub const regmem: u64 = generated.regmem;
pub const memory: u64 = generated.memory;
pub const to: u64 = generated.to;
pub const colon: u64 = generated.colon;
pub const reg_class_shift: u32 = generated.reg_class_shift;
pub const subclass_shift: u32 = generated.subclass_shift;
pub const size_shift: u32 = generated.size_shift;
pub const size_mask: u64 = generated.size_mask;
pub const bits8: u64 = generated.bits8;
pub const bits16: u64 = generated.bits16;
pub const bits32: u64 = generated.bits32;
pub const bits64: u64 = generated.bits64;
pub const bits80: u64 = generated.bits80;
pub const bits128: u64 = generated.bits128;
pub const bits256: u64 = generated.bits256;
pub const bits512: u64 = generated.bits512;
pub const far: u64 = generated.far;
pub const near: u64 = generated.near;
pub const short: u64 = generated.short;
pub const abs: u64 = generated.abs;

pub const reg_class_cdt: u64 = generated.reg_class_cdt;
pub const reg_class_gpr: u64 = generated.reg_class_gpr;
pub const reg_class_sreg: u64 = generated.reg_class_sreg;
pub const reg_class_fpureg: u64 = generated.reg_class_fpureg;
pub const reg_class_rm_mmx: u64 = generated.reg_class_rm_mmx;
pub const reg_class_rm_xmm: u64 = generated.reg_class_rm_xmm;
pub const reg_class_rm_ymm: u64 = generated.reg_class_rm_ymm;
pub const reg_class_rm_zmm: u64 = generated.reg_class_rm_zmm;
pub const reg_class_opmask: u64 = generated.reg_class_opmask;
pub const reg_class_bnd: u64 = generated.reg_class_bnd;
pub const reg_class_rm_tmm: u64 = generated.reg_class_rm_tmm;
pub const reg_class_vector: u64 = generated.reg_class_vector;
pub const reg_ea: u64 = generated.reg_ea;
pub const rn_l16: u64 = generated.rn_l16;
pub const rm_l16: u64 = generated.rm_l16;
pub const rm_zero: u64 = generated.rm_zero;
pub const rm_nzero: u64 = generated.rm_nzero;
pub const rm_sel: u64 = generated.rm_sel;
pub const reg_gpr: u64 = generated.reg_gpr;
pub const rm_gpr: u64 = generated.rm_gpr;
pub const rm_mmx: u64 = generated.rm_mmx;
pub const rm_xmm: u64 = generated.rm_xmm;
pub const rm_ymm: u64 = generated.rm_ymm;
pub const rm_zmm: u64 = generated.rm_zmm;
pub const rm_opmask: u64 = generated.rm_opmask;
pub const rm_bnd: u64 = generated.rm_bnd;
pub const reg16: u64 = generated.reg16;
pub const reg32: u64 = generated.reg32;
pub const reg64: u64 = generated.reg64;
pub const reg8: u64 = generated.reg8;
pub const reg_high: u64 = generated.reg_high;
pub const mem_offs: u64 = generated.mem_offs;
pub const memory_any: u64 = generated.memory_any;
pub const xmem: u64 = generated.xmem;
pub const ymem: u64 = generated.ymem;
pub const zmem: u64 = generated.zmem;
pub const imm_normal: u64 = generated.imm_normal;
pub const unity: u64 = generated.unity;
pub const sbyteword: u64 = generated.sbyteword;
pub const sbytedword: u64 = generated.sbytedword;
pub const sdword_operand: u64 = generated.sdword_operand;
pub const udword: u64 = generated.udword;
pub const fourbits: u64 = generated.fourbits;
pub const imm_known: u64 = generated.imm_known;

pub const optype_shift: u32 = generated.optype_shift;
pub const optype_bits: u32 = generated.optype_bits;
pub const modifier_shift: u32 = generated.modifier_shift;
pub const modifier_bits: u32 = generated.modifier_bits;
pub const reg_class_bits: u32 = generated.reg_class_bits;
pub const regset_shift: u32 = generated.regset_shift;
pub const regset_bits: u32 = generated.regset_bits;

pub const regset_mask: u64 = generated.regset_mask;
pub const strict: u64 = generated.strict;
pub const byte_ext_mask: u64 = generated.byteextmask;
pub const dword_ext_mask: u64 = generated.dwordextmask;
pub const sdword: u64 = generated.sdword;
pub const opflag_forward: i32 = generated.opflag_forward;
pub const opflag_extern: i32 = generated.opflag_extern;
pub const opflag_unknown: i32 = generated.opflag_unknown;
pub const opflag_relative: i32 = generated.opflag_relative;
pub const opflag_simple: i32 = generated.opflag_simple;

pub const if_sm0: u32 = generated.if_sm0;
pub const if_ar0: u32 = generated.if_ar0;
pub const if_sb: u32 = generated.if_sb;
pub const if_nwsize: u32 = generated.if_nwsize;
pub const if_osize: u32 = generated.if_osize;
pub const if_asize: u32 = generated.if_asize;
pub const if_anysize: u32 = generated.if_anysize;
pub const if_sx: u32 = generated.if_sx;
pub const if_sdword: u32 = generated.if_sdword;
pub const if_jmp_relax: u32 = generated.if_jmp_relax;
pub const if_jcc_hint: u32 = generated.if_jcc_hint;
pub const if_opt: u32 = generated.if_opt;
pub const if_latevex: u32 = generated.if_latevex;
pub const if_norex: u32 = generated.if_norex;
pub const if_noapx: u32 = generated.if_noapx;
pub const if_nf: u32 = generated.if_nf;
pub const if_nf_r: u32 = generated.if_nf_r;
pub const if_zu: u32 = generated.if_zu;
pub const if_ww: u32 = generated.if_ww;
pub const if_sib: u32 = generated.if_sib;
pub const if_lock: u32 = generated.if_lock;
pub const if_lock1: u32 = generated.if_lock1;
pub const if_nolong: u32 = generated.if_nolong;
pub const if_long: u32 = generated.if_long;
pub const if_nohle: u32 = generated.if_nohle;
pub const if_mib: u32 = generated.if_mib;
pub const if_bnd: u32 = generated.if_bnd;
pub const if_rex2: u32 = generated.if_rex2;
pub const if_fl: u32 = generated.if_fl;
pub const if_vex: u32 = generated.if_vex;
pub const if_evex: u32 = generated.if_evex;
pub const if_apx: u32 = generated.if_apx;
pub const if_x86_64: u32 = generated.if_x86_64;
pub const if_default: u32 = generated.if_default;
pub const if_cpu_field: usize = generated.if_cpu_field;
pub const if_feature_field: usize = generated.if_feature_field;
pub const if_feature_nfields: usize = generated.if_feature_nfields;
pub const if_field_count: usize = generated.if_field_count;
pub const if_cpu_level_mask: u32 = generated.if_cpu_level_mask;

pub const ifm_sm0: u32 = generated.ifm_sm0;
pub const ifm_sm1: u32 = generated.ifm_sm1;
pub const ifm_sm2: u32 = generated.ifm_sm2;
pub const ifm_sm3: u32 = generated.ifm_sm3;
pub const ifm_sm4: u32 = generated.ifm_sm4;
pub const ifm_ar0: u32 = generated.ifm_ar0;
pub const ifm_ar1: u32 = generated.ifm_ar1;
pub const ifm_ar2: u32 = generated.ifm_ar2;
pub const ifm_ar3: u32 = generated.ifm_ar3;
pub const ifm_ar4: u32 = generated.ifm_ar4;
pub const ifm_sb: u32 = generated.ifm_sb;
pub const ifm_sw: u32 = generated.ifm_sw;
pub const ifm_sd: u32 = generated.ifm_sd;
pub const ifm_sq: u32 = generated.ifm_sq;
pub const ifm_st: u32 = generated.ifm_st;
pub const ifm_so: u32 = generated.ifm_so;
pub const ifm_sy: u32 = generated.ifm_sy;
pub const ifm_sz: u32 = generated.ifm_sz;
pub const ifm_nwsize: u32 = generated.ifm_nwsize;
pub const ifm_osize: u32 = generated.ifm_osize;
pub const ifm_asize: u32 = generated.ifm_asize;
pub const ifm_anysize: u32 = generated.ifm_anysize;
pub const ifm_sx: u32 = generated.ifm_sx;
pub const ifm_default: u32 = generated.ifm_default;

pub const if_tsmask: u32 = generated.if_tsmask;
pub const if_smask: u32 = generated.if_smask;
pub const if_armask: u32 = generated.if_armask;
pub const if_smmask: u32 = generated.if_smmask;

pub fn defaultCpuIflagField(field_index: usize) u32 {
    if (field_index >= if_feature_field and field_index < if_feature_field + if_feature_nfields) {
        return ~@as(u32, 0);
    }
    if (field_index == if_cpu_field) return ifm_default;
    return 0;
}

pub const rex_mask: u32 = generated.rex_mask;
pub const rex_b: u32 = generated.rex_b;
pub const rex_x: u32 = generated.rex_x;
pub const rex_r: u32 = generated.rex_r;
pub const rex_w: u32 = generated.rex_w;
pub const rex_l: u32 = generated.rex_l;
pub const rex_p: u32 = generated.rex_p;
pub const rex_h: u32 = generated.rex_h;
pub const rex_v: u32 = generated.rex_v;
pub const rex_nh: u32 = generated.rex_nh;
pub const rex_ev: u32 = generated.rex_ev;
pub const rex_2: u32 = generated.rex_2;
pub const rex_b1: u32 = generated.rex_b1;
pub const rex_x1: u32 = generated.rex_x1;
pub const rex_r1: u32 = generated.rex_r1;
pub const rex_nw: u32 = generated.rex_nw;
pub const rex_bv: u32 = generated.rex_bv;
pub const rex_xv: u32 = generated.rex_xv;
pub const rex_rv: u32 = generated.rex_rv;
pub const rex_bxr0: u32 = generated.rex_bxr0;
pub const rex_bxr1: u32 = generated.rex_bxr1;
pub const rex_bxr: u32 = generated.rex_bxr;
pub const rex_bxrv: u32 = generated.rex_bxrv;
pub const rex_rB: u32 = generated.rex_rb;
pub const rex_rX: u32 = generated.rex_rx;
pub const rex_rR: u32 = generated.rex_rr;

pub const evex_w: u32 = generated.evex_w;
pub const evex_ll: u32 = generated.evex_ll;
pub const evex_rc: u32 = generated.evex_rc;
pub const evex_aaa: u32 = generated.evex_aaa;
pub const evex_nf: u32 = generated.evex_nf;
pub const evex_v4: u32 = generated.evex_v4;
pub const evex_b4: u32 = generated.evex_b4;
pub const evex_nd: u32 = generated.evex_nd;
pub const evex_x4: u32 = generated.evex_x4;
pub const evex_r4: u32 = generated.evex_r4;
pub const evex_x3: u32 = generated.evex_x3;
pub const evex_b: u32 = generated.evex_b;
pub const evex_z: u32 = generated.evex_z;

pub const out_wrap: u8 = generated.out_wrap;
pub const out_signed: u8 = generated.out_signed;
pub const out_unsigned: u8 = generated.out_unsigned;
pub const out_signmask: u8 = generated.out_signmask;
pub const out_nowarn: u8 = generated.out_nowarn;

pub const eaf_byteoffs: i32 = generated.eaf_byteoffs;
pub const eaf_wordoffs: i32 = generated.eaf_wordoffs;
pub const eaf_timestwo: i32 = generated.eaf_timestwo;
pub const eaf_rel: i32 = generated.eaf_rel;
pub const eaf_abs: i32 = generated.eaf_abs;
pub const eaf_mib: i32 = generated.eaf_mib;
pub const eaf_sib: i32 = generated.eaf_sib;
pub const eaf_notfsgs: i32 = generated.eaf_notfsgs;
pub const eaf_fs: i32 = generated.eaf_fs;
pub const eaf_gs: i32 = generated.eaf_gs;

pub const eah_nohint: i32 = generated.eah_nohint;
pub const eah_makebase: i32 = generated.eah_makebase;
pub const eah_notbase: i32 = generated.eah_notbase;
pub const eah_summed: i32 = generated.eah_summed;

pub const pfe_null: i32 = generated.pfe_null;
pub const pfe_multi: i32 = generated.pfe_multi;
pub const pfe_err: i32 = generated.pfe_err;
pub const pfe_what: i32 = generated.pfe_what;

const r_cs: i32 = exprRegByEnumName("R_CS");
const r_ds: i32 = exprRegByEnumName("R_DS");
const r_es: i32 = exprRegByEnumName("R_ES");
const r_fs: i32 = exprRegByEnumName("R_FS");
const r_gs: i32 = exprRegByEnumName("R_GS");
const r_ss: i32 = exprRegByEnumName("R_SS");

pub const rv_vex: i32 = generated.rv_vex;
pub const rv_xop: i32 = generated.rv_xop;
pub const rv_evex: i32 = generated.rv_evex;

pub const brc_1to2: i32 = generated.brc_1to2;
pub const brc_1to4: i32 = generated.brc_1to4;
pub const brc_1to8: i32 = generated.brc_1to8;
pub const brc_1to16: i32 = generated.brc_1to16;
pub const brc_1to32: i32 = generated.brc_1to32;
pub const brc_rn: i32 = generated.brc_rn;
pub const brc_rd: i32 = generated.brc_rd;
pub const brc_ru: i32 = generated.brc_ru;
pub const brc_rz: i32 = generated.brc_rz;
pub const brc_sae: i32 = generated.brc_sae;
pub const brc_z: i32 = generated.brc_z;

pub const opmask_mask: u16 = generated.opmask_mask;
pub const z_mask: u16 = generated.z_mask;
pub const brdcast_mask: u16 = generated.brdcast_mask;
pub const staticrnd_mask: u16 = generated.staticrnd_mask;
pub const sae_mask: u16 = generated.sae_mask;
pub const brsize_mask: u16 = generated.brsize_mask;
pub const brnum_shift: u32 = generated.brnum_shift;
pub const brnum_mask: u16 = generated.brnum_mask;

pub const jsize_mask: u64 = near | far | short | abs;
pub const msize_mask: u64 = size_mask & ~jsize_mask;

pub fn prefixByte(prefix: i32, bits: u8) i32 {
    return switch (prefix) {
        p_none, p_nf, p_nobnd, p_zu => pfe_null,
        p_wait => 0x9b,
        p_lock => 0xf0,
        p_repne, p_repnz, p_xacquire, p_bnd => 0xf2,
        p_repe, p_repz, p_rep, p_xrelease => 0xf3,
        r_cs, p_pn => 0x2e,
        r_ds, p_pt => 0x3e,
        r_es => 0x26,
        r_fs => 0x64,
        r_gs => 0x65,
        r_ss => 0x36,
        p_a16 => if (bits == 64) pfe_err else if (bits == 32) 0x67 else pfe_null,
        p_a32 => if (bits != 32) 0x67 else pfe_null,
        p_asp => 0x67,
        p_a64 => if (bits == 64) pfe_null else pfe_err,
        p_o16 => if (bits != 16) 0x66 else pfe_null,
        p_o32 => if (bits == 16) 0x66 else pfe_null,
        p_o64 => if (bits == 64) pfe_null else pfe_err,
        p_osp => 0x66,
        p_rex, p_rex2, p_vex, p_vex2, p_vex3, p_evex => pfe_multi,
        else => pfe_what,
    };
}

pub const PrefixSlot = enum(u8) {
    wait = generated.pps_wait,
    segment = generated.pps_seg,
    address_size = generated.pps_asize,
    lock = generated.pps_lock,
    operand_size = generated.pps_osize,
    rep = generated.pps_rep,
    rex = generated.pps_rex,
    nf = generated.pps_nf,
    zu = generated.pps_zu,

    pub fn index(self: PrefixSlot) usize {
        return @intFromEnum(self);
    }
};

pub const PrefixToken = struct {
    value: i32 = p_none,

    pub const none: PrefixToken = .{ .value = p_none };
    pub const lock: PrefixToken = .{ .value = p_lock };
    pub const xacquire: PrefixToken = .{ .value = p_xacquire };
    pub const xrelease: PrefixToken = .{ .value = p_xrelease };
    pub const bnd: PrefixToken = .{ .value = p_bnd };
    pub const nobnd: PrefixToken = .{ .value = p_nobnd };
    pub const rex: PrefixToken = .{ .value = p_rex };
    pub const rex2: PrefixToken = .{ .value = p_rex2 };
    pub const evex: PrefixToken = .{ .value = p_evex };
    pub const vex: PrefixToken = .{ .value = p_vex };
    pub const vex2: PrefixToken = .{ .value = p_vex2 };
    pub const vex3: PrefixToken = .{ .value = p_vex3 };
    pub const nf: PrefixToken = .{ .value = p_nf };
    pub const zu: PrefixToken = .{ .value = p_zu };
    pub const pt: PrefixToken = .{ .value = p_pt };
    pub const pn: PrefixToken = .{ .value = p_pn };

    pub fn raw(self: PrefixToken) i32 {
        return self.value;
    }
};

pub const Location = struct {
    segment: i32 = no_seg,
    offset: i64 = 0,
};

pub const SpeculativeSize = union(enum) {
    size: i64,
    would_error,
};

pub const OperandKind = enum {
    memory,
    register,
    immediate,
    other,
};

pub const EaType = enum {
    scalar,
    xmm_vsib,
    ymm_vsib,
    zmm_vsib,
    invalid,
};

pub const TupleType = enum(u8) {
    none = 0,
    fv = generated.fv,
    hv = generated.hv,
    fvm = generated.fvm,
    t1s8 = generated.t1s8,
    t1s16 = generated.t1s16,
    t1s = generated.t1s,
    t1f32 = generated.t1f32,
    t1f64 = generated.t1f64,
    t2 = generated.t2,
    t4 = generated.t4,
    t8 = generated.t8,
    hvm = generated.hvm,
    qvm = generated.qvm,
    ovm = generated.ovm,
    m128 = generated.m128,
    dup = generated.dup,
};

pub const EaData = struct {
    ea_type: EaType = .scalar,
    rex: u32 = 0,
    size: u8 = 0,
    bytes: u8 = 0,
    sib_present: bool = false,
    rip: bool = false,
    modrm: u8 = 0,
    sib: u8 = 0,
    disp8: i8 = 0,
    disp8_shift: u8 = 0,
    disp8_ok: bool = false,
};

pub const Operand = struct {
    kind: OperandKind = .memory,
    type_bits: u64 = 0,
    basereg: i32 = r_none,
    indexreg: i32 = r_none,
    scale: i32 = 0,
    hintbase: i32 = r_none,
    hinttype: i32 = 0,
    segment: i32 = no_seg,
    wrt: i32 = no_seg,
    offset: i64 = 0,
    opflags: i32 = 0,
    symbolic: bool = false,
    eaflags: i32 = 0,
    disp_size: u8 = 0,
    ip_relative: bool = false,
    iflag: i32 = 0,
    decoflags: u16 = 0,
};

pub const Instruction = struct {
    opcode: u16 = 0,
    loc: Location = .{},
    prefixes: [max_prefix]PrefixToken = @splat(@as(PrefixToken, .none)),
    need_pfx: [max_prefix]i32 = @splat(@as(i32, 0)),
    bits: u8 = 64,
    op_size: u8 = 32,
    addr_size: u8 = 64,
    operands: u8 = 0,
    rex: u32 = 0,
    evex: u32 = 0,
    vexreg: u8 = 0,
    veximm: u8 = 0,
    vex_cm: u8 = 0,
    vex_wlp: u8 = 0,
    rex_done: bool = false,
    evex_tuple: TupleType = .none,
    evex_brerop: ?u8 = null,
    evex_rm: i32 = 0,
    itemp_lig: bool = false,
    ea: EaData = .{},
    opt: u32 = 0,
    default_rel: bool = false,
    first_pass: bool = true,
    dummy: bool = false,
    itemp: ?tables.TemplateRef = null,
    itempindex: i32 = -1,
    oprs: [max_operands]Operand = @splat(@as(Operand, .{})),

    pub fn init(opcode: u16, bits_mode: u8) Instruction {
        return .{
            .opcode = opcode,
            .bits = bits_mode,
            .op_size = if (bits_mode == 16) 16 else 32,
            .addr_size = bits_mode,
        };
    }
};

pub const MatchResult = enum(i32) {
    inval_op = 0,
    op_size_inval = 1,
    op_size_missing = 2,
    op_size_mismatch = 3,
    mask_not_here = 4,
    br_not_here = 5,
    br_num_mismatch = 6,
    deco_not_here = 7,
    bad_zu = 8,
    mem_zu = 9,
    bad_nf = 10,
    req_nf = 11,
    bad_cpu = 12,
    bad_mode = 13,
    bad_hle = 14,
    enc_mismatch = 15,
    bad_bnd = 16,
    bad_repne = 17,
    reg_set_size = 18,
    reg_set = 19,
    wrong_imm = 20,
    ok_first = 21,
    ok_fuzzy8 = 22,
    ok_fuzzy7 = 23,
    ok_fuzzy6 = 24,
    ok_fuzzy5 = 25,
    ok_fuzzy4 = 26,
    ok_fuzzy3 = 27,
    ok_fuzzy2 = 28,
    ok_fuzzy1 = 29,
    ok_good = 30,

    pub fn rank(self: MatchResult) i32 {
        return @intFromEnum(self);
    }

    pub fn isSuccess(self: MatchResult) bool {
        return self.rank() >= MatchResult.ok_first.rank();
    }
};

pub fn isClass(class: u64, op: u64) bool {
    return (class & ~op) == 0;
}

pub fn isRegister(reg: i32) bool {
    return reg >= expr_reg_start and reg < reg_enum_limit;
}

fn exprRegByEnumName(comptime enum_name: []const u8) i32 {
    inline for (generated_registers.all) |row| {
        if (std.mem.eql(u8, row.enum_name, enum_name)) {
            return row.expr_reg;
        }
    }
    @compileError("missing generated register " ++ enum_name);
}

fn iflagMask(iflag: u32) u32 {
    return @as(u32, 1) << @as(u5, @intCast(iflag & 31));
}

test "default CPU iflags mirror x86 default CPU default feature layout" {
    const testing = @import("std").testing;

    try testing.expectEqual(@as(u32, 0), defaultCpuIflagField(0) & iflagMask(if_latevex));
    try testing.expect((defaultCpuIflagField(if_feature_field) & iflagMask(if_evex)) != 0);
    try testing.expect((defaultCpuIflagField(if_feature_field) & iflagMask(if_vex)) != 0);
    try testing.expectEqual(ifm_default, defaultCpuIflagField(if_cpu_field) & if_cpu_level_mask);
}
