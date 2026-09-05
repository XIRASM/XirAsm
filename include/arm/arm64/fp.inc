// A64 scalar floating point (M5a) — the FP/SIMD register file shares the
// encoding space; scalar S/D forms address the low lanes of V registers
// (ARM ARM B1.3.1). Vector forms live in arm64/simd.inc.
//
// FP load/store unsigned immediate (LLVM LDRSui/STRSui/LDRDui/STRDui):
//   size(31-30) 111(29-27) V=1(26) 01(25-24) opc(23-22) imm12(21-10)
//   Rn(9-5) Rt(4-0); opc 00 = STR, 01 = LDR; size 10 = S, 11 = D.
//   The imm12 is scaled by the access size (S: 4, D: 8).
//
// Scalar FP arithmetic (LLVM TwoOperandFPData / OneOperandFPData):
//   00011110(31-24) type(23-22) 1(21) Rm(20-16) opcode(15-12) 10(11-10)
//   Rn(9-5) Rd(4-0) for two-source; opcode 0000 FMUL, 0001 FDIV,
//   0010 FADD, 0011 FSUB. One-source forms: 0000 FMOV, 0001 FABS,
//   0010 FNEG, 0011 FSQRT at bits 17-15 with 10000(20-16) and 1(14).
//
// Compare (LLVM BaseTwoOperandFPComparison): 00011110 type 1 Rm 001000 Rn
// 0(4) 0000(3-0); the zero form sets Rm = 00000 and 01000 at 4-0.
// Register constants use arm64_vN (bit 7 tag); S/D are selected by the
// explicit type argument (0 = S, 1 = D) in the arithmetic emitters, and by
// size (2 = S, 3 = D) in the load/store emitters.

fn arm64_fldst_base(size: u64, scale: u64, is_load: bool, rt: u64, rn: u64, offset: u64, what: string) {
    assert(size == 2 || size == 3, sym.join(what, ": size must be S or D"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(arm64_is_v(rt) == 1, sym.join(what, ": Rt must be a V register"));
    assert(offset % scale == 0, sym.join(what, ": offset must be a multiple of the access size"));
    const imm12: u64 = offset / scale
    assert(imm12 <= 4095, sym.join(what, ": offset out of range"));
    let opc: u64 = 0
    if is_load {
        opc = 1
    }
    emit.u32((size << 30) | (0x7 << 27) | (1 << 26) | (1 << 24) | (opc << 22)
        | (imm12 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDR (floating-point S, unsigned immediate offset). ARM ARM C6.2.177.
// clang: ldr s0, [x1, #4] -> 0xbd400420.
fn arm64_fldr_s(rt: u64, rn: u64, offset: u64) {
    arm64_fldst_base(2, 4, true, rt, rn, offset, "ldr s")
}

// LDR (floating-point D, unsigned immediate offset). ARM ARM C6.2.177.
// clang: ldr d2, [x3, #8] -> 0xfd400462.
fn arm64_fldr_d(rt: u64, rn: u64, offset: u64) {
    arm64_fldst_base(3, 8, true, rt, rn, offset, "ldr d")
}

// STR (floating-point S, unsigned immediate offset). ARM ARM C6.2.349.
// clang: str s5, [x6] -> 0xbd0000c5.
fn arm64_fstr_s(rt: u64, rn: u64, offset: u64) {
    arm64_fldst_base(2, 4, false, rt, rn, offset, "str s")
}

// STR (floating-point D, unsigned immediate offset). ARM ARM C6.2.349.
// clang: str d7, [x8, #16] -> 0xfd000907.
fn arm64_fstr_d(rt: u64, rn: u64, offset: u64) {
    arm64_fldst_base(3, 8, false, rt, rn, offset, "str d")
}

// Internal: scalar FP two-source arithmetic (FADD 0010, FSUB 0011, FMUL 0000,
// FDIV 0001). Registers are V constants; ty 0 = S, 1 = D.
fn arm64_emit_fp2(ty: u64, opcode: u64, rd: u64, rn: u64, rm: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32(0x1e200000 | (ty << 22) | (1 << 21) | (arm64_reg_number(rm) << 16)
        | (opcode << 12) | (2 << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

// FADD (scalar, S/D). ARM ARM C6.2.95.
fn arm64_fadd_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 2, rd, rn, rm, "fadd s")
}

fn arm64_fadd_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 2, rd, rn, rm, "fadd d")
}

// FSUB (scalar, S/D). ARM ARM C6.2.352.
fn arm64_fsub_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 3, rd, rn, rm, "fsub s")
}

fn arm64_fsub_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 3, rd, rn, rm, "fsub d")
}

// FMUL (scalar, S/D). ARM ARM C6.2.326.
fn arm64_fmul_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 0, rd, rn, rm, "fmul s")
}

fn arm64_fmul_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 0, rd, rn, rm, "fmul d")
}

// FDIV (scalar, S/D). ARM ARM C6.2.110.
fn arm64_fdiv_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 1, rd, rn, rm, "fdiv s")
}

fn arm64_fdiv_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 1, rd, rn, rm, "fdiv d")
}

// FMAX/FMIN (scalar; IEEE 754 maximum/minimum NaN propagation) and
// FMAXNM/FMINNM (scalar; maxNum/minNum NaN handling). Same two-source FP
// layout as FADD/FDIV with opcodes (FADD 0010) 0100/0101/0110/0111.
// clang: fmax s0, s1, s2 -> 0x1e224820; fminnm d12, d13, d14 ->
// 0x1e6e79ac.

// FMAX (scalar, S/D).
fn arm64_fmax_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 4, rd, rn, rm, "fmax s")
}

fn arm64_fmax_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 4, rd, rn, rm, "fmax d")
}

// FMIN (scalar, S/D).
fn arm64_fmin_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 5, rd, rn, rm, "fmin s")
}

fn arm64_fmin_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 5, rd, rn, rm, "fmin d")
}

// FMAXNM (scalar, S/D).
fn arm64_fmaxnm_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 6, rd, rn, rm, "fmaxnm s")
}

fn arm64_fmaxnm_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 6, rd, rn, rm, "fmaxnm d")
}

// FMINNM (scalar, S/D).
fn arm64_fminnm_s(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(0, 7, rd, rn, rm, "fminnm s")
}

fn arm64_fminnm_d(rd: u64, rn: u64, rm: u64) {
    arm64_emit_fp2(1, 7, rd, rn, rm, "fminnm d")
}

// Internal: scalar FP one-source (FMOV 000, FABS 001, FNEG 010, FSQRT 011
// at bits 17-15, fixed 10000 at 20-16 and 1 at 14).
fn arm64_emit_fp1(ty: u64, opcode: u64, rd: u64, rn: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32(0x1e200000 | (ty << 22) | (1 << 21) | (opcode << 15) | (1 << 14)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// FABS (scalar, S/D). ARM ARM C6.2.89.
fn arm64_fabs_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 1, rd, rn, "fabs s")
}

fn arm64_fabs_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 1, rd, rn, "fabs d")
}

// FNEG (scalar, S/D). ARM ARM C6.2.250.
fn arm64_fneg_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 2, rd, rn, "fneg s")
}

fn arm64_fneg_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 2, rd, rn, "fneg d")
}

// FSQRT (scalar, S/D). ARM ARM C6.2.346.
fn arm64_fsqrt_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 3, rd, rn, "fsqrt s")
}

fn arm64_fsqrt_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 3, rd, rn, "fsqrt d")
}

// Internal: FCMP against a register (LLVM BaseTwoOperandFPComparison,
// 001000 at 15-10, Rt field = 00000, NZCV set).
fn arm64_emit_fcmp(ty: u64, rm: u64, rn: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32(0x1e200000 | (ty << 22) | (1 << 21) | (arm64_reg_number(rm) << 16)
        | (2 << 12) | (arm64_reg_number(rn) << 5))
}

// FCMP (register form, S/D). ARM ARM C6.2.79.
fn arm64_fcmp_s(rn: u64, rm: u64) {
    arm64_emit_fcmp(0, rm, rn, "fcmp s")
}

fn arm64_fcmp_d(rn: u64, rm: u64) {
    arm64_emit_fcmp(1, rm, rn, "fcmp d")
}

// FCMP (zero form): Rm = 00000 and 01000 at bits 4-0.
// clang: fcmp d0, #0.0 -> 0x1e602008 (r2-verified).
fn arm64_fcmp_z_s(rn: u64) {
    assert(arm64_is_v(rn) == 1, "fcmp s: register must be a V register");
    emit.u32(0x1e200000 | (1 << 21) | (2 << 12) | (arm64_reg_number(rn) << 5) | 8)
}

fn arm64_fcmp_z_d(rn: u64) {
    assert(arm64_is_v(rn) == 1, "fcmp d: register must be a V register");
    emit.u32(0x1e600000 | (1 << 21) | (2 << 12) | (arm64_reg_number(rn) << 5) | 8)
}

// FCMPE (register form): the signal-all-NaN variant of FCMP; LLVM
// FPComparison<1> (InstrInfo.td:5711) sets the bit 4 flag inside
// BaseTwoOperandFPComparison (AArch64InstrFormats.td:6068).
// clang: fcmpe s0, s1 -> 0x1e212010; fcmpe d2, d3 -> 0x1e632050.
fn arm64_emit_fcmp_e(ty: u64, rm: u64, rn: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32(0x1e200000 | (ty << 22) | (1 << 21) | (arm64_reg_number(rm) << 16)
        | (2 << 12) | (arm64_reg_number(rn) << 5) | (1 << 4))
}

fn arm64_fcmpe_s(rn: u64, rm: u64) {
    arm64_emit_fcmp_e(0, rm, rn, "fcmpe s")
}

fn arm64_fcmpe_d(rn: u64, rm: u64) {
    arm64_emit_fcmp_e(1, rm, rn, "fcmpe d")
}

// FCMPE (zero form): Rm = 00000, bit 3 zero flag and bit 4 NaN flag set.
// clang: fcmpe s4, #0.0 -> 0x1e202098; fcmpe d5, #0.0 -> 0x1e6020b8.
fn arm64_fcmpe_z_s(rn: u64) {
    assert(arm64_is_v(rn) == 1, "fcmpe s: register must be a V register");
    emit.u32(0x1e200000 | (1 << 21) | (2 << 12) | (arm64_reg_number(rn) << 5) | 0x18)
}

fn arm64_fcmpe_z_d(rn: u64) {
    assert(arm64_is_v(rn) == 1, "fcmpe d: register must be a V register");
    emit.u32(0x1e600000 | (1 << 21) | (2 << 12) | (arm64_reg_number(rn) << 5) | 0x18)
}

// FMOV (register form, S/D). ARM ARM C6.2.224.
fn arm64_fmov_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 0, rd, rn, "fmov s")
}

fn arm64_fmov_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 0, rd, rn, "fmov d")
}

// --- M5a second half: conditional, immediate, conversion, rounding, and
// extended FP addressing. Fixture words below come from the mechanical
// mkwords.sh pipeline (clang --target=aarch64-linux-gnu -march=armv8.4-a),
// never hand-typed. ------------

// FCSEL (LLVM BaseFPCondSelect, AArch64InstrFormats.td:6174):
//   00011110(31-24) type(23-22) 1(21) Rm(20-16) cond(15-12) 11(11-10)
//   Rn(9-5) Rd(4-0).
fn arm64_emit_fcsel(ty: u64, rd: u64, rn: u64, rm: u64, cond: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    assert(cond <= 13, sym.join(what, ": requires a real condition code (0..13)"));
    emit.u32(0x1e200000 | (ty << 22) | (arm64_reg_number(rm) << 16) | (cond << 12)
        | (3 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// FCSEL (register, S/D). clang: fcsel s9, s10, s11, eq -> 0x1e2b0d49.
fn arm64_fcsel_s(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_fcsel(0, rd, rn, rm, cond, "fcsel s")
}

// clang: fcsel d12, d13, d14, gt -> 0x1e6ecdac.
fn arm64_fcsel_d(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_fcsel(1, rd, rn, rm, cond, "fcsel d")
}

// FCCMP/FCCMPE (LLVM BaseFPCondComparison, AArch64InstrFormats.td:6125):
//   00011110(31-24) type(23-22) 1(21) Rm(20-16) cond(15-12) 01(11-10)
//   Rn(9-5) nan-bit(4) nzcv(3-0). FCCMPE sets the bit 4 nan form.
fn arm64_emit_fccmp(ty: u64, rn: u64, rm: u64, nzcv: u64, cond: u64, snan: u64,
        what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    assert(nzcv <= 15, sym.join(what, ": nzcv out of range"));
    assert(cond <= 13, sym.join(what, ": requires a real condition code (0..13)"));
    emit.u32(0x1e200000 | (ty << 22) | (arm64_reg_number(rm) << 16) | (cond << 12)
        | (1 << 10) | (arm64_reg_number(rn) << 5) | (snan << 4) | nzcv)
}

// FCCMP (S/D). clang: fccmp s15, s16, #5, ne -> 0x1e3015e5.
fn arm64_fccmp_s(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_emit_fccmp(0, rn, rm, nzcv, cond, 0, "fccmp s")
}

// clang: fccmp d17, d18, #10, lt -> 0x1e72b62a.
fn arm64_fccmp_d(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_emit_fccmp(1, rn, rm, nzcv, cond, 0, "fccmp d")
}

// FCCMPE (S/D). clang: fccmpe d19, d20, #15, hs -> 0x1e74267f.
fn arm64_fccmpe_s(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_emit_fccmp(0, rn, rm, nzcv, cond, 1, "fccmpe s")
}

// clang: fccmpe d19, d20, #15, hs -> 0x1e74267f (D form).
fn arm64_fccmpe_d(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_emit_fccmp(1, rn, rm, nzcv, cond, 1, "fccmpe d")
}

// FMOV (immediate, LLVM BaseFPMoveImmediate, AArch64InstrFormats.td:6216):
//   00011110(31-24) type(23-22) 1(21) imm8(20-13) 10000000(12-5) Rd(4-0).
//   imm8 is the raw aBbbbbbb field (sign, 3-bit exponent, 4-bit fraction);
//   imm8 field values are extracted mechanically from clang words.
fn arm64_fmov_imm_s(rd: u64, imm8: u64) {
    assert(arm64_is_v(rd) == 1, "fmov s: register must be a V register");
    assert(imm8 <= 255, "fmov s: imm8 out of range");
    emit.u32(0x1e200000 | (imm8 << 13) | (0x80 << 5) | arm64_reg_number(rd))
}

fn arm64_fmov_imm_d(rd: u64, imm8: u64) {
    assert(arm64_is_v(rd) == 1, "fmov d: register must be a V register");
    assert(imm8 <= 255, "fmov d: imm8 out of range");
    emit.u32(0x1e600000 | (imm8 << 13) | (0x80 << 5) | arm64_reg_number(rd))
}

// FCVT (FP precision conversion, LLVM BaseFPConversion,
// AArch64InstrFormats.td:5775): 00011110(31-24) type(23-22) 10001(21-17)
// opcode(16-15) 10000(14-10) Rn(9-5) Rd(4-0). type is the source size and
// opcode the destination size (00 = S, 01 = D); H forms are out of M5a scope.
fn arm64_emit_fcvt(ty: u64, opcode: u64, rd: u64, rn: u64, what: string) {
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32(0x1e000000 | (ty << 22) | (0x11 << 17) | (opcode << 15) | (1 << 14)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// FCVT Sd, Dn (double to single; LLVM FCVT SDr: type=01, opcode=00).
// clang: fcvt s23, d24 -> 0x1e624317.
fn arm64_fcvt_sd(rd: u64, rn: u64) {
    arm64_emit_fcvt(1, 0, rd, rn, "fcvt s<d")
}

// FCVT Dd, Sn (single to double; LLVM FCVT DSr: type=00, opcode=01).
// clang: fcvt d25, s26 -> 0x1e22c359.
fn arm64_fcvt_ds(rd: u64, rn: u64) {
    arm64_emit_fcvt(0, 1, rd, rn, "fcvt d<s")
}

// SCVTF/UCVTF (integer to FP, unscaled; LLVM BaseIntegerToFPUnscaled,
// AArch64InstrFormats.td:5502; InstrInfo.td:5428/5429 rmode=00, opcode
// 010/011): sf(31) 0011110(30-24) type(23-22) 1(21) rmode(20-19)
// opcode(18-16) 000000(15-10) Rn(9-5) Rd(4-0). sf follows the source GPR
// width (W=0, X=1); the source may not be ZR or SP (LLVM GPR32/GPR64).
fn arm64_emit_itofp(ty: u64, opcode: u64, vd: u64, rn: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(vd) == 1, sym.join(what, ": destination must be a V register"));
    assert(!arm64_reg_is_zr(rn) && !arm64_reg_is_sp(rn),
        sym.join(what, ": source must be a W or X register"));
    const sf: u64 = (rn >> 5) & 1
    emit.u32((sf << 31) | 0x1e000000 | (ty << 22) | (1 << 21) | (opcode << 16)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(vd))
}

// SCVTF (S/D destination, W or X source). clang: scvtf s27, w28 ->
// 0x1e22039b; scvtf d29, x30 -> 0x9e6203dd.
fn arm64_scvtf_s(vd: u64, rn: u64) {
    arm64_emit_itofp(0, 2, vd, rn, "scvtf s")
}

fn arm64_scvtf_d(vd: u64, rn: u64) {
    arm64_emit_itofp(1, 2, vd, rn, "scvtf d")
}

// UCVTF (S/D destination, W or X source). clang: ucvtf s0, w1 -> 0x1e230020;
// ucvtf d2, x3 -> 0x9e630062.
fn arm64_ucvtf_s(vd: u64, rn: u64) {
    arm64_emit_itofp(0, 3, vd, rn, "ucvtf s")
}

fn arm64_ucvtf_d(vd: u64, rn: u64) {
    arm64_emit_itofp(1, 3, vd, rn, "ucvtf d")
}

// FCVTZS/FCVTZU (FP to integer, unscaled; LLVM BaseFPToIntegerUnscaled,
// AArch64InstrFormats.td:5314; InstrInfo.td:5383/5384 rmode=11, opcode
// 000/001): sf(31) 00(30-29) 11110(28-24) type(23-22) 1(21) rmode(20-19)
// opcode(18-16) 000000(15-10) Rn(9-5) Rd(4-0). sf follows the destination
// GPR width; the destination may not be ZR or SP (LLVM GPR32/GPR64).
fn arm64_emit_ftoi(ty: u64, opcode: u64, rd: u64, vn: u64, what: string) {
    assert(ty == 0 || ty == 1, sym.join(what, ": type must be S or D"));
    assert(arm64_is_v(vn) == 1, sym.join(what, ": source must be a V register"));
    assert(!arm64_reg_is_zr(rd) && !arm64_reg_is_sp(rd),
        sym.join(what, ": destination must be a W or X register"));
    const sf: u64 = (rd >> 5) & 1
    emit.u32((sf << 31) | 0x1e000000 | (ty << 22) | (1 << 21) | (3 << 19)
        | (opcode << 16) | (arm64_reg_number(vn) << 5) | arm64_reg_number(rd))
}

// FCVTZS, W destination, S source. clang: fcvtzs w4, s5 -> 0x1e3800a4.
fn arm64_fcvtzs_w_s(rd: u64, vn: u64) {
    assert(!arm64_reg_is64(rd), "fcvtzs w,s requires a W register");
    arm64_emit_ftoi(0, 0, rd, vn, "fcvtzs w,s")
}

// FCVTZS, X destination, S source.
fn arm64_fcvtzs_x_s(rd: u64, vn: u64) {
    assert(arm64_reg_is64(rd), "fcvtzs x,s requires an X register");
    arm64_emit_ftoi(0, 0, rd, vn, "fcvtzs x,s")
}

// FCVTZS, W destination, D source. clang: fcvtzs w4, d5 shares the encoding
// with the S form via the type bit.
fn arm64_fcvtzs_w_d(rd: u64, vn: u64) {
    assert(!arm64_reg_is64(rd), "fcvtzs w,d requires a W register");
    arm64_emit_ftoi(1, 0, rd, vn, "fcvtzs w,d")
}

// FCVTZS, X destination, D source. clang: fcvtzs x6, d7 -> 0x9e7800e6.
fn arm64_fcvtzs_x_d(rd: u64, vn: u64) {
    assert(arm64_reg_is64(rd), "fcvtzs x,d requires an X register");
    arm64_emit_ftoi(1, 0, rd, vn, "fcvtzs x,d")
}

// FCVTZU, W destination, S source. clang: fcvtzu w8, s9 -> 0x1e390128.
fn arm64_fcvtzu_w_s(rd: u64, vn: u64) {
    assert(!arm64_reg_is64(rd), "fcvtzu w,s requires a W register");
    arm64_emit_ftoi(0, 1, rd, vn, "fcvtzu w,s")
}

// FCVTZU, X destination, S source.
fn arm64_fcvtzu_x_s(rd: u64, vn: u64) {
    assert(arm64_reg_is64(rd), "fcvtzu x,s requires an X register");
    arm64_emit_ftoi(0, 1, rd, vn, "fcvtzu x,s")
}

// FCVTZU, W destination, D source.
fn arm64_fcvtzu_w_d(rd: u64, vn: u64) {
    assert(!arm64_reg_is64(rd), "fcvtzu w,d requires a W register");
    arm64_emit_ftoi(1, 1, rd, vn, "fcvtzu w,d")
}

// FCVTZU, X destination, D source. clang: fcvtzu x10, d11 -> 0x9e79016a.
fn arm64_fcvtzu_x_d(rd: u64, vn: u64) {
    assert(arm64_reg_is64(rd), "fcvtzu x,d requires an X register");
    arm64_emit_ftoi(1, 1, rd, vn, "fcvtzu x,d")
}

// FRINTN/P/M/Z/A share the one-source FP layout with FMOV/FABS/FNEG/FSQRT;
// LLVM encodes them with the 6-bit opcode {00, op4} at Inst{20-15}
// (BaseSingleOperandFPData, AArch64InstrFormats.td:5821; InstrInfo.td:5519-
// 5526: FRINTA 1100, FRINTM 1010, FRINTN 1000, FRINTP 1001, FRINTZ 1011).
// clang: frintn s12, s13 -> 0x1e2441ac; frintp d14, d15 -> 0x1e64c1ee.
fn arm64_frintn_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 8, rd, rn, "frintn s")
}

fn arm64_frintn_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 8, rd, rn, "frintn d")
}

fn arm64_frintp_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 9, rd, rn, "frintp s")
}

fn arm64_frintp_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 9, rd, rn, "frintp d")
}

fn arm64_frintm_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 10, rd, rn, "frintm s")
}

fn arm64_frintm_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 10, rd, rn, "frintm d")
}

fn arm64_frintz_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 11, rd, rn, "frintz s")
}

fn arm64_frintz_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 11, rd, rn, "frintz d")
}

fn arm64_frinta_s(rd: u64, rn: u64) {
    arm64_emit_fp1(0, 12, rd, rn, "frinta s")
}

fn arm64_frinta_d(rd: u64, rn: u64) {
    arm64_emit_fp1(1, 12, rd, rn, "frinta d")
}

// FP load/store unscaled immediate (LLVM LoadUnscaled/StoreUnscaled,
// AArch64InstrFormats.td:4518/4529; InstrInfo.td:4172 LDURS, :4175 LDURD,
// :4975 STURS, :4978 STURD): size(31-30) 111(29-27) V=1(26) 00(25-24)
// opc(23-22) imm9(20-12) 00(11-10) Rn(9-5) Rt(4-0). Raw byte offset
// -256..255; base is GPR64sp (X register or SP).
fn arm64_emit_fldur(size: u64, is_load: bool, rt: u64, rn: u64, offset: u64,
        what: string) {
    assert(size == 2 || size == 3, sym.join(what, ": size must be S or D"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(arm64_is_v(rt) == 1, sym.join(what, ": Rt must be a V register"));
    assert(offset < 0x100 || offset >= 0xffffffffffffff00,
        sym.join(what, ": offset out of range -256..255"));
    const imm9: u64 = offset & 0x1ff
    let opc: u64 = 0
    if is_load {
        opc = 1
    }
    emit.u32((size << 30) | (0x7 << 27) | (1 << 26) | (opc << 22) | (imm9 << 12)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDUR (floating-point S). clang: ldur s22, [x23, #-4] -> 0xbc5fc2f6.
fn arm64_fldur_s(rt: u64, rn: u64, offset: u64) {
    arm64_emit_fldur(2, true, rt, rn, offset, "ldur s")
}

// LDUR (floating-point D). clang: ldur d24, [x25, #-8] -> 0xfc5f8338.
fn arm64_fldur_d(rt: u64, rn: u64, offset: u64) {
    arm64_emit_fldur(3, true, rt, rn, offset, "ldur d")
}

// STUR (floating-point S). clang: stur s26, [x27, #255] -> 0xbc0ff37a.
fn arm64_fstur_s(rt: u64, rn: u64, offset: u64) {
    arm64_emit_fldur(2, false, rt, rn, offset, "stur s")
}

// STUR (floating-point D). clang: stur d28, [sp, #-256] -> 0xfc1003fc.
fn arm64_fstur_d(rt: u64, rn: u64, offset: u64) {
    arm64_emit_fldur(3, false, rt, rn, offset, "stur d")
}

// FP load/store register offset (LLVM Load32RO/Store32RO ->
// LoadStore32RO, AArch64InstrFormats.td:4183; InstrInfo.td:3861 LDRS,
// :3862 LDRD, :4700 STRS, :4701 STRD): size(31-30) 111(29-27) V=1(26)
// 00(25-24) opc(23-22) 1(21) Rm(20-16) option(15-13) 10(11-10) Rn(9-5)
// Rt(4-0), with bit 14 fixed 1 and S(12) marking the scaled form. Base is
// GPR64sp (X register or SP, never ZR); UXTW/SXTW require a W index and
// LSL/SXTX an X index, as in the integer forms.
fn arm64_emit_fldst_reg(size: u64, opc: u64, rt: u64, rn: u64, rm: u64,
        option: u64, shifted: bool, what: string) {
    assert(size == 2 || size == 3, sym.join(what, ": size must be S or D"));
    assert(arm64_is_v(rt) == 1, sym.join(what, ": Rt must be a V register"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(what, ": base cannot be ZR"));
    assert(!arm64_reg_is_zr(rm) && !arm64_reg_is_sp(rm),
        sym.join(what, ": index must be a W or X register"));
    assert(option == arm64_ldst_opt_uxtw || option == arm64_ldst_opt_lsl
        || option == arm64_ldst_opt_sxtw || option == arm64_ldst_opt_sxtx,
        sym.join(what, ": option must be UXTW/LSL/SXTW/SXTX"));
    if option == arm64_ldst_opt_lsl || option == arm64_ldst_opt_sxtx {
        assert(arm64_reg_is64(rm), sym.join(what, ": LSL/SXTX index requires an X register"));
    } else {
        assert(!arm64_reg_is64(rm), sym.join(what, ": UXTW/SXTW index requires a W register"));
    }
    let s: u64 = 0
    if shifted {
        s = 1
    }
    emit.u32((size << 30) | (0x7 << 27) | (1 << 26) | (opc << 22) | (1 << 21)
        | (arm64_reg_number(rm) << 16) | (option << 13) | (s << 12) | (2 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDR (floating-point S, register offset). clang: ldr s29, [x30, x0] ->
// 0xbc606bdd.
fn arm64_fldr_s_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    arm64_emit_fldst_reg(2, 1, rt, rn, rm, option, shifted, "ldr s reg")
}

// LDR (floating-point D, register offset). clang: ldr d1, [x2, x3, lsl #3]
// -> 0xfc637841.
fn arm64_fldr_d_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    arm64_emit_fldst_reg(3, 1, rt, rn, rm, option, shifted, "ldr d reg")
}

// STR (floating-point S, register offset). clang: str s4, [x5, w6, uxtw #2]
// -> 0xbc2658a4.
fn arm64_fstr_s_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    arm64_emit_fldst_reg(2, 0, rt, rn, rm, option, shifted, "str s reg")
}

// STR (floating-point D, register offset). clang: str d7, [x8, x9, sxtx]
// -> 0xfc29e907.
fn arm64_fstr_d_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    arm64_emit_fldst_reg(3, 0, rt, rn, rm, option, shifted, "str d reg")
}
