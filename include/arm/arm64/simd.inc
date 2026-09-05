// A64 Advanced SIMD (NEON) vector operations (M5b), one family batch per
// commit. Vector data lives in the same V0-V31 bank as scalar FP
// (arm64_vN constants); the lane arrangement travels as a separate id:
//   arr>>1 = element size (0=B, 1=H, 2=S, 3=D), arr&1 = Q (64/128-bit view).
// Encodings follow the cited LLVM TableGen classes; fixture words are
// extracted mechanically by the mkwords.sh pipeline
// (clang --target=aarch64-linux-gnu -march=armv8.4-a), never hand-typed.

const arm64_arr_8b: u64 = 0
const arm64_arr_16b: u64 = 1
const arm64_arr_4h: u64 = 2
const arm64_arr_8h: u64 = 3
const arm64_arr_2s: u64 = 4
const arm64_arr_4s: u64 = 5
const arm64_arr_1d: u64 = 6
const arm64_arr_2d: u64 = 7

// Element-size ids for families that pass the lane size directly
// (INS/UMOV/SMOV reference single lanes, so the dest Q bit follows the
// register width instead of an arrangement).
const arm64_ts_b: u64 = 0
const arm64_ts_h: u64 = 1
const arm64_ts_s: u64 = 2
const arm64_ts_d: u64 = 3

fn arm64_arr_q(arr: u64) -> u64 {
    return arr & 1;
}

fn arm64_arr_esize(arr: u64) -> u64 {
    return arr >> 1;
}

fn arm64_arr_check(arr: u64, what: string) {
    assert(arr <= 7, sym.join(what, ": invalid arrangement"));
}

// --- AdvSIMD copy space (DUP / INS / UMOV / SMOV) ---------------------------------
// Shared layout (LLVM BaseSIMDInsDup, AArch64InstrFormats.td:8286):
//   0(31) Q(30) op(29) 01110000(28-21) imm5(20-16) 0(15) imm4(14-11)
//   1(10) Rn(9-5) Rd(4-0). imm5 packs the lane index above a size marker
//   bit; imm4 selects the variant (0001 DUP general, 0000 DUP element,
//   0011 INS general, 0111 UMOV, 0101 SMOV) and carries the INS element
//   source index.
fn arm64_emit_simd_copy(q: u64, op: u64, imm5: u64, imm4: u64, rd: u64, rn: u64) {
    emit.u32((q << 30) | (op << 29) | (0x70 << 21) | (imm5 << 16) | (imm4 << 11)
        | (1 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// DUP (general): replicate a W/X register into every lane of Vd
// (LLVM SIMDDupFromMain, AArch64InstrFormats.td:8302). The lane size comes
// from the arrangement; B/H/S lanes take a W source, D lanes an X source
// (LLVM GPR32/GPR64: no ZR, no SP).
// clang: dup v0.8b, w1 -> 0x0e010c20; dup v2.2d, x3 -> 0x4e080c62;
// dup v4.4s, w5 -> 0x4e040ca4.
fn arm64_dup_gen(vd: u64, arr: u64, rn: u64) {
    arm64_arr_check(arr, "dup");
    assert(arm64_is_v(vd) == 1, "dup: destination must be a V register");
    const esize: u64 = arm64_arr_esize(arr)
    assert(!arm64_reg_is_zr(rn) && !arm64_reg_is_sp(rn),
        "dup: source must be a W or X register");
    if esize == 3 {
        assert(arm64_reg_is64(rn), "dup d: source must be an X register");
    } else {
        assert(!arm64_reg_is64(rn), "dup w: source must be a W register");
    }
    arm64_emit_simd_copy(arm64_arr_q(arr), 0, (1 << esize), 1, vd, rn)
}

// DUP (element): replicate one Vn lane into every lane of Vd
// (LLVM SIMDDupFromElement, AArch64InstrFormats.td:8312, imm4 = 0000). The
// source index range is the full register's lane count for the element size
// (B 16, H 8, S 4, D 2) regardless of the destination arrangement width.
// clang: dup v6.16b, v7.b[3] -> 0x4e0704e6; dup v8.4h, v9.h[2] -> 0x0e0a0528;
// dup v10.2s, v11.s[1] -> 0x0e0c056a; dup v12.2d, v13.d[0] -> 0x4e0805ac.
fn arm64_dup_elem(vd: u64, arr: u64, vn: u64, idx: u64) {
    arm64_arr_check(arr, "dup");
    assert(arm64_is_v(vd) == 1 && arm64_is_v(vn) == 1,
        "dup: registers must be V registers");
    const esize: u64 = arm64_arr_esize(arr)
    assert(idx < (16 >> esize), "dup: element index out of range");
    const imm5: u64 = (idx << (esize + 1)) | (1 << esize)
    arm64_emit_simd_copy(arm64_arr_q(arr), 0, imm5, 0, vd, vn)
}

// INS (general): store a W/X register into one lane of Vd
// (LLVM SIMDInsFromMain, AArch64InstrFormats.td:8488; Q is always 1, imm4 =
// 0011). B/H/S lanes take a W source, D lanes an X source.
// clang: ins v14.b[5], w15 -> 0x4e0b1dee; ins v16.d[1], x17 -> 0x4e181e30.
fn arm64_ins_gpr(vd: u64, esize: u64, idx: u64, rn: u64) {
    assert(esize <= 3, "ins: element size must be B/H/S/D");
    assert(arm64_is_v(vd) == 1, "ins: destination must be a V register");
    assert(idx < (16 >> esize), "ins: element index out of range");
    assert(!arm64_reg_is_zr(rn) && !arm64_reg_is_sp(rn),
        "ins: source must be a W or X register");
    if esize == 3 {
        assert(arm64_reg_is64(rn), "ins d: source must be an X register");
    } else {
        assert(!arm64_reg_is64(rn), "ins w: source must be a W register");
    }
    const imm5: u64 = (idx << (esize + 1)) | (1 << esize)
    arm64_emit_simd_copy(1, 0, imm5, 3, vd, rn)
}

// INS (element): copy one Vn lane into one Vd lane (LLVM SIMDInsFromElement,
// AArch64InstrFormats.td:8500; Q = 1, op = 1). The source index rides the
// imm4 field, aligned to its top bits (imm4 = idx2 << esize).
// clang: ins v0.b[15], v1.b[15] -> 0x6e1f7c20; ins v18.h[3], v19.h[6] ->
// 0x6e0e6672; ins v20.s[1], v21.s[2] -> 0x6e0c46b4.
fn arm64_ins_elem(vd: u64, esize: u64, idx: u64, vn: u64, idx2: u64) {
    assert(esize <= 3, "ins: element size must be B/H/S/D");
    assert(arm64_is_v(vd) == 1 && arm64_is_v(vn) == 1,
        "ins: registers must be V registers");
    assert(idx < (16 >> esize) && idx2 < (16 >> esize),
        "ins: element index out of range");
    const imm5: u64 = (idx << (esize + 1)) | (1 << esize)
    const imm4: u64 = idx2 << esize
    arm64_emit_simd_copy(1, 1, imm5, imm4, vd, vn)
}

// UMOV: extract one lane of Vn into a GPR, zero-extended (LLVM SIMDUMov via
// BaseSIMDMov, AArch64InstrFormats.td:8370/8433, imm4 = 0111). LLVM encodes
// B/H/S extractions with a W destination (Q = 0) and D extraction with an X
// destination (Q = 1); the D form also carries the preferred "mov" alias.
// clang: umov w22, v23.b[4] -> 0x0e093ef6; umov w24, v25.s[3] -> 0x0e1c3f38;
// umov x26, v27.d[1] -> 0x4e183f7a.
fn arm64_umov(rd: u64, esize: u64, idx: u64, vn: u64) {
    assert(esize <= 3, "umov: element size must be B/H/S/D");
    assert(arm64_is_v(vn) == 1, "umov: source must be a V register");
    assert(idx < (16 >> esize), "umov: element index out of range");
    assert(!arm64_reg_is_zr(rd) && !arm64_reg_is_sp(rd),
        "umov: destination must be a W or X register");
    if esize == 3 {
        assert(arm64_reg_is64(rd), "umov d: requires an X register destination");
    } else {
        assert(!arm64_reg_is64(rd), "umov w: requires a W register destination");
    }
    const q: u64 = (rd >> 5) & 1
    const imm5: u64 = (idx << (esize + 1)) | (1 << esize)
    arm64_emit_simd_copy(q, 0, imm5, 7, rd, vn)
}

// SMOV: extract one lane of Vn into a GPR, sign-extended (LLVM SIMDSMov,
// AArch64InstrFormats.td:8367/8381, imm4 = 0101). LLVM encodes B/H with a W
// or X destination (Q follows the register) and S with an X destination
// only; there is no D form.
// clang: smov w28, v29.h[5] -> 0x0e162fbc; smov x30, v0.b[15] -> 0x4e1f2c1e.
fn arm64_smov(rd: u64, esize: u64, idx: u64, vn: u64) {
    assert(esize <= 2, "smov: element size must be B/H/S (no D form)");
    assert(arm64_is_v(vn) == 1, "smov: source must be a V register");
    assert(idx < (16 >> esize), "smov: element index out of range");
    assert(!arm64_reg_is_zr(rd) && !arm64_reg_is_sp(rd),
        "smov: destination must be a W or X register");
    if esize == 2 {
        assert(arm64_reg_is64(rd), "smov s: requires an X register destination");
    }
    const q: u64 = (rd >> 5) & 1
    const imm5: u64 = (idx << (esize + 1)) | (1 << esize)
    arm64_emit_simd_copy(q, 0, imm5, 5, rd, vn)
}

// --- LD1/ST1 (multiple structures, one register, no offset) -------------------
// Layout (LLVM BaseSIMDLdSt, AArch64InstrFormats.td:10939; one-register
// opcode 0b0111 from SIMDLd1Multiple/SIMDSt1Multiple, :11201/:11208):
//   0(31) Q(30) 0011000(29-23) L(22) 000000(21-16) opcode(15-12)
//   size(11-10) Rn(9-5) Vt(4-0). Q and size come from the arrangement
//   (all eight arrangements are valid for the one-register form); Rn is
//   GPR64sp (X register or SP). Two/four-register lists and post-index
//   forms are later batches.
fn arm64_emit_ld1st1(arr: u64, is_load: bool, vt: u64, rn: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arm64_is_v(vt) == 1, sym.join(what, ": register must be a V register"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    let l: u64 = 0
    if is_load {
        l = 1
    }
    emit.u32((arm64_arr_q(arr) << 30) | (24 << 23) | (l << 22) | (7 << 12)
        | (arm64_arr_esize(arr) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(vt))
}

// LD1 (one register, no offset), all arrangements.
// clang: ld1 { v0.8b }, [x1] -> 0x0c407020; ld1 { v14.2d }, [sp] ->
// 0x4c407fee.
fn arm64_ld1(vt: u64, arr: u64, rn: u64) {
    arm64_emit_ld1st1(arr, true, vt, rn, "ld1")
}

// ST1 (one register, no offset), all arrangements.
// clang: st1 { v15.8b }, [x16] -> 0x0c00720f; st1 { v28.2d }, [x29] ->
// 0x4c007fbc.
fn arm64_st1(vt: u64, arr: u64, rn: u64) {
    arm64_emit_ld1st1(arr, false, vt, rn, "st1")
}

// --- MOVI / MVNI (AdvSIMD modified immediate) ----------------------------------
// Layout (LLVM BaseSIMDModifiedImm, AArch64InstrFormats.td:8859):
//   0(31) Q(30) op(29) 0111100000(28-19) imm8hi(18-16) cmode(15-12)
//   0(11) 1(10) imm8lo(9-5) Rd(4-0). The 8-bit imm8 is split across the
//   word: bits 7-5 land at 18-16 and bits 4-0 at 9-5. op = 0 selects MOVI,
//   1 selects MVNI. cmode values verified against the LLVM instantiations
//   (SIMDModifiedImmVectorShift :8952, SIMDModifiedImmMoveMSL :8991,
//   SIMDModifiedImmVectorNoShift :9002, MOVIv2d_ns :8751):
//   byte form cmode 1110; halfword 1000/1010 (LSL 0/8); word shift
//   0000/0010/0100/0110 (LSL 0/8/16/24, shift bits at 14-13); MSL
//   1100/1101; the 64-bit MOVI form sets op = 1 with cmode 1110 and
//   expands each imm8 bit into one 0x00/0xff byte.
fn arm64_emit_modimm(q: u64, op: u64, cmode: u64, imm8: u64, rd: u64) {
    assert(imm8 <= 255, "modimm: imm8 out of range");
    assert(cmode <= 15, "internal: cmode out of range");
    emit.u32((q << 30) | (op << 29) | 0x0f000000 | ((imm8 >> 5) << 16)
        | (cmode << 12) | (1 << 10) | ((imm8 & 0x1f) << 5)
        | arm64_reg_number(rd))
}

// MOVI (byte form): replicate imm8 into every byte lane; arrangement must be
// 8B or 16B.
// clang: movi v0.8b, #0x5a -> 0x0f02e740; movi v2.16b, #255 -> 0x4f07e7e2.
fn arm64_movi_b(vd: u64, arr: u64, imm8: u64) {
    arm64_arr_check(arr, "movi");
    assert(arm64_is_v(vd) == 1, "movi: destination must be a V register");
    assert(arm64_arr_esize(arr) == 0, "movi b: arrangement must be 8B or 16B");
    arm64_emit_modimm(arm64_arr_q(arr), 0, 14, imm8, vd)
}

// MOVI (halfword form): imm8 in each lane, optionally LSL #8; arrangement
// must be 4H or 8H.
// clang: movi v4.4h, #0x12 -> 0x0f008644;
// movi v6.8h, #0x34, lsl #8 -> 0x4f01a686.
fn arm64_movi_h(vd: u64, arr: u64, imm8: u64, shifted: bool) {
    arm64_arr_check(arr, "movi");
    assert(arm64_is_v(vd) == 1, "movi: destination must be a V register");
    assert(arm64_arr_esize(arr) == 1, "movi h: arrangement must be 4H or 8H");
    let cmode: u64 = 8
    if shifted {
        cmode = 10
    }
    arm64_emit_modimm(arm64_arr_q(arr), 0, cmode, imm8, vd)
}

// MOVI (word shift form): imm8 in each lane shifted left by shift*8
// (shift 0..3); arrangement must be 2S or 4S.
// clang: movi v8.2s, #0x56 -> 0x0f0206c8;
// movi v10.4s, #0x78, lsl #16 -> 0x4f03470a;
// movi v12.4s, #0x9a, lsl #24 -> 0x4f04674c.
fn arm64_movi_s(vd: u64, arr: u64, imm8: u64, shift: u64) {
    arm64_arr_check(arr, "movi");
    assert(arm64_is_v(vd) == 1, "movi: destination must be a V register");
    assert(arm64_arr_esize(arr) == 2, "movi s: arrangement must be 2S or 4S");
    assert(shift <= 3, "movi s: shift must be 0/8/16/24");
    arm64_emit_modimm(arm64_arr_q(arr), 0, (shift << 1), imm8, vd)
}

// MOVI (word MSL form): imm8 shifted left then ones-filled from bit 7
// (msl8) or bit 15 (msl16); arrangement must be 2S or 4S.
// clang: movi v14.2s, #0xbc, msl #8 -> 0x0f05c78e;
// movi v16.4s, #0xde, msl #16 -> 0x4f06d7d0.
fn arm64_movi_s_msl(vd: u64, arr: u64, imm8: u64, msl16: bool) {
    arm64_arr_check(arr, "movi");
    assert(arm64_is_v(vd) == 1, "movi: destination must be a V register");
    assert(arm64_arr_esize(arr) == 2, "movi s: arrangement must be 2S or 4S");
    let cmode: u64 = 12
    if msl16 {
        cmode = 13
    }
    arm64_emit_modimm(arm64_arr_q(arr), 0, cmode, imm8, vd)
}

// MOVI (64-bit form, LLVM MOVIv2d_ns: Q = 1, op = 1, cmode 1110). Each bit
// of the imm8 field fills one byte of the register with 0x00/0xff (bit i ->
// byte i), so imm8 = 0 gives the zero vector and imm8 = 255 all ones.
// clang: movi v18.2d, #0xff (value 0x000000000000ff) -> field 0x01, word
// 0x6f00e432.
fn arm64_movi_d(vd: u64, imm8: u64) {
    assert(arm64_is_v(vd) == 1, "movi: destination must be a V register");
    arm64_emit_modimm(1, 1, 14, imm8, vd)
}

// MVNI (halfword form): bitwise NOT of the MOVI halfword immediate.
// clang: mvni v20.4h, #0x11 -> 0x2f008634;
// mvni v22.8h, #0x22, lsl #8 -> 0x6f01a456.
fn arm64_mvni_h(vd: u64, arr: u64, imm8: u64, shifted: bool) {
    arm64_arr_check(arr, "mvni");
    assert(arm64_is_v(vd) == 1, "mvni: destination must be a V register");
    assert(arm64_arr_esize(arr) == 1, "mvni h: arrangement must be 4H or 8H");
    let cmode: u64 = 8
    if shifted {
        cmode = 10
    }
    arm64_emit_modimm(arm64_arr_q(arr), 1, cmode, imm8, vd)
}

// MVNI (word shift form).
// clang: mvni v24.2s, #0x33 -> 0x2f010678;
// mvni v26.4s, #0x44, lsl #8 -> 0x6f02249a.
fn arm64_mvni_s(vd: u64, arr: u64, imm8: u64, shift: u64) {
    arm64_arr_check(arr, "mvni");
    assert(arm64_is_v(vd) == 1, "mvni: destination must be a V register");
    assert(arm64_arr_esize(arr) == 2, "mvni s: arrangement must be 2S or 4S");
    assert(shift <= 3, "mvni s: shift must be 0/8/16/24");
    arm64_emit_modimm(arm64_arr_q(arr), 1, (shift << 1), imm8, vd)
}

// MVNI (word MSL form).
// clang: mvni v28.2s, #0x55, msl #16 -> 0x2f02d6bc.
fn arm64_mvni_s_msl(vd: u64, arr: u64, imm8: u64, msl16: bool) {
    arm64_arr_check(arr, "mvni");
    assert(arm64_is_v(vd) == 1, "mvni: destination must be a V register");
    assert(arm64_arr_esize(arr) == 2, "mvni s: arrangement must be 2S or 4S");
    let cmode: u64 = 12
    if msl16 {
        cmode = 13
    }
    arm64_emit_modimm(arm64_arr_q(arr), 1, cmode, imm8, vd)
}

// --- Vector three-same arithmetic and bitwise logical --------------------------
// Layout (LLVM BaseSIMDThreeSameVector, AArch64InstrFormats.td:6256):
//   0(31) Q(30) U(29) 01110(28-24) size(23-21) Rm(20-16) opcode(15-11)
//   1(10) Rn(9-5) Rd(4-0). Arithmetic three-same encodes size = {esize, 1}
//   (001/011/101/111 for B/H/S/D). The logical family fixes opcode 00011
//   and repurposes the size bits as opcode extension: AND 00, BIC 01,
//   ORR 10, ORN 11 with U = 0, EOR with U = 1 and 00; bitwise ops ignore
//   element size, so only 8B/16B arrangements exist (clang rejects .2D).
//   BSL/BIT/BIF are the tied U = 1 forms (01/10/11), likewise 8B/16B.
fn arm64_emit_3same(q: u64, u: u64, size3: u64, opcode: u64, rd: u64, rn: u64,
        rm: u64) {
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        "three-same: registers must be V registers");
    emit.u32((q << 30) | (u << 29) | (0x0e << 24) | (size3 << 21)
        | (arm64_reg_number(rm) << 16) | (opcode << 11) | (1 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

fn arm64_check_arr_arith(arr: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arr != arm64_arr_1d, sym.join(what, ": 1D arrangement not supported"));
}

fn arm64_check_arr_bhs(arr: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arr <= arm64_arr_4s, sym.join(what, ": D lanes not supported"));
}

fn arm64_check_arr_byte(arr: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arr == arm64_arr_8b || arr == arm64_arr_16b,
        sym.join(what, ": arrangement must be 8B or 16B"));
}

// ADD (vector), element-wise per arrangement; all arrangements except 1D.
// clang: add v0.16b, v1.16b, v2.16b -> 0x4e228420;
// add v9.2d, v10.2d, v11.2d -> 0x4eeb8549.
fn arm64_add_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "add");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        16, vd, vn, vm)
}

// SUB (vector), all arrangements except 1D.
// clang: sub v12.4s, v13.4s, v14.4s -> 0x6eae85ac;
// sub v15.8b, v16.8b, v17.8b -> 0x2e31860f.
fn arm64_sub_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sub");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        16, vd, vn, vm)
}

// MUL (vector), B/H/S lanes only (no D forms in the encoding).
// clang: mul v18.8b, v19.8b, v20.8b -> 0x0e349e72;
// mul v21.4s, v22.4s, v23.4s -> 0x4eb79ed5.
fn arm64_mul_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "mul");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        19, vd, vn, vm)
}

// AND (vector), 8B/16B only.
// clang: and v24.16b, v25.16b, v26.16b -> 0x4e3a1f38.
fn arm64_and_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "and");
    arm64_emit_3same(arm64_arr_q(arr), 0, 1, 3, vd, vn, vm)
}

// BIC (vector, bitwise clear), 8B/16B only.
// clang: bic v4.16b, v5.16b, v6.16b -> 0x4e661ca4.
fn arm64_bic_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "bic");
    arm64_emit_3same(arm64_arr_q(arr), 0, 3, 3, vd, vn, vm)
}

// ORR (vector), 8B/16B only.
// clang: orr v27.8b, v28.8b, v29.8b -> 0x0ebd1f9b.
fn arm64_orr_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "orr");
    arm64_emit_3same(arm64_arr_q(arr), 0, 5, 3, vd, vn, vm)
}

// ORN (vector), 8B/16B only.
// clang: orn v7.8b, v8.8b, v9.8b -> 0x0ee91d07.
fn arm64_orn_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "orn");
    arm64_emit_3same(arm64_arr_q(arr), 0, 7, 3, vd, vn, vm)
}

// EOR (vector), 8B/16B only.
// clang: eor v30.8b, v31.8b, v0.8b -> 0x2e201ffe;
// eor v1.16b, v2.16b, v3.16b -> 0x6e231c41.
fn arm64_eor_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "eor");
    arm64_emit_3same(arm64_arr_q(arr), 1, 1, 3, vd, vn, vm)
}

// BSL (tied select: Vd = Vd&Vn | ~Vd&Vm), 8B/16B only.
// clang: bsl v10.16b, v11.16b, v12.16b -> 0x6e6c1d6a.
fn arm64_bsl_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "bsl");
    arm64_emit_3same(arm64_arr_q(arr), 1, 3, 3, vd, vn, vm)
}

// BIT (tied select keyed on Vn), 8B/16B only.
// clang: bit v13.8b, v14.8b, v15.8b -> 0x2eaf1dcd.
fn arm64_bit_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "bit");
    arm64_emit_3same(arm64_arr_q(arr), 1, 5, 3, vd, vn, vm)
}

// BIF (tied select keyed on ~Vn), 8B/16B only.
// clang: bif v16.16b, v17.16b, v18.16b -> 0x6ef21e30.
fn arm64_bif_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_byte(arr, "bif");
    arm64_emit_3same(arm64_arr_q(arr), 1, 7, 3, vd, vn, vm)
}

// --- Vector shift by immediate ------------------------------------------------
// Layout (LLVM BaseSIMDVectorShift, AArch64InstrFormats.td:10399):
//   0(31) Q(30) U(29) 011110(28-23) immhb(22-16) opcode(15-11) 1(10)
//   Rn(9-5) Rd(4-0). Left shifts encode immhb = T + shift; right shifts
//   encode immhb = 2T - shift, with T the element size in bits (verified
//   round trip via clang). Opcodes: SHL 01010 (U = 0), SSHR/USHR 00000
//   (U = 0/1), SSHLL/USHLL 10100 (U = 0/1). SHL takes 0..T-1, right
//   shifts 1..T (clang-enforced). Long forms widen every source lane to
//   double width with the same lane count, and the high-half variants are
//   the separate SSHLL2/USHLL2 mnemonics (Q = 1, source 128-bit
//   arrangement); their shift range is 0..T_src-1.
fn arm64_emit_shift_imm(q: u64, u: u64, opc: u64, immhb: u64, rd: u64, rn: u64,
        what: string) {
    assert(immhb >= 1 && immhb <= 127, sym.join(what, ": shift amount out of range"));
    emit.u32((q << 30) | (u << 29) | 0x0f000000 | (immhb << 16) | (opc << 11)
        | (1 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// SHL (vector), shift 0..T-1. clang: shl v0.8b, v1.8b, #3 -> 0x0f0b5420;
// shl v8.2d, v9.2d, #33 -> 0x4f615528.
fn arm64_shl(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_check_arr_arith(arr, "shl");
    const t: u64 = 8 << arm64_arr_esize(arr)
    assert(shift <= (t - 1), sym.join("shl: shift amount out of range 0..", to_string(t - 1)));
    arm64_emit_shift_imm(arm64_arr_q(arr), 0, 10, t + shift, vd, vn, "shl")
}

// SSHR (arithmetic right), shift 1..T. clang: sshr v10.4h, v11.4h, #4 ->
// 0x0f1c056a; sshr v12.8b, v13.8b, #8 -> 0x0f0805ac.
fn arm64_sshr(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sshr");
    const t: u64 = 8 << arm64_arr_esize(arr)
    assert(shift >= 1 && shift <= t, sym.join("sshr: shift amount out of range 1..", to_string(t)));
    arm64_emit_shift_imm(arm64_arr_q(arr), 0, 0, (2 * t) - shift, vd, vn, "sshr")
}

// USHR (logical right), shift 1..T. clang: ushr v14.4s, v15.4s, #12 ->
// 0x6f3405ee; ushr v16.2d, v17.2d, #64 -> 0x6f400630.
fn arm64_ushr(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_check_arr_arith(arr, "ushr");
    const t: u64 = 8 << arm64_arr_esize(arr)
    assert(shift >= 1 && shift <= t, sym.join("ushr: shift amount out of range 1..", to_string(t)));
    arm64_emit_shift_imm(arm64_arr_q(arr), 1, 0, (2 * t) - shift, vd, vn, "ushr")
}

// Internal: long shifts. The arrangement is the SOURCE view; dest is the
// same lane count at double element width. `high` selects SSHLL2/USHLL2
// (Q = 1, 128-bit source arrangement).
fn arm64_emit_shift_long(vd: u64, vn: u64, shift: u64, arr: u64, u: u64,
        high: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arm64_is_v(vd) == 1 && arm64_is_v(vn) == 1,
        sym.join(what, ": registers must be V registers"));
    const esize: u64 = arm64_arr_esize(arr)
    assert(esize <= 2, sym.join(what, ": source lanes must be B/H/S"));
    assert(arm64_arr_q(arr) == high,
        sym.join(what, ": source arrangement half must match the variant"));
    const t: u64 = 8 << esize
    assert(shift <= (t - 1), sym.join(what, ": shift amount out of range 0..T-1"));
    arm64_emit_shift_imm(high, u, 20, t + shift, vd, vn, what)
}

// SSHLL (low half). clang: sshll v20.8h, v21.8b, #1 -> 0x0f09a6b4.
fn arm64_sshll(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_emit_shift_long(vd, vn, shift, arr, 0, 0, "sshll")
}

// SSHLL2 (high half). clang: sshll2 v22.8h, v23.16b, #3 -> 0x4f0ba6f6.
fn arm64_sshll2(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_emit_shift_long(vd, vn, shift, arr, 0, 1, "sshll2")
}

// USHLL (low half). clang: ushll v24.4s, v25.4h, #5 -> 0x2f15a738;
// ushll v28.2d, v29.2s, #7 -> 0x2f27a7bc.
fn arm64_ushll(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_emit_shift_long(vd, vn, shift, arr, 1, 0, "ushll")
}

// USHLL2 (high half). clang: ushll2 v26.4s, v27.8h, #7 -> 0x6f17a77a.
fn arm64_ushll2(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_emit_shift_long(vd, vn, shift, arr, 1, 1, "ushll2")
}

// --- Vector permutes (UZP1/UZP2/ZIP1/ZIP2) -------------------------------------
// Layout (LLVM BaseSIMDZipVector, AArch64InstrFormats.td:7716):
//   0(31) Q(30) 001110(29-24) size(23-22) 0(21) Rm(20-16) 0(15)
//   opcode(14-12) 10(11-10) Rn(9-5) Rd(4-0). Opcodes: UZP1 001,
//   UZP2 101, ZIP1 011, ZIP2 111 (TRN 010/110 left to a later batch).
//   There is no 1D arrangement (clang rejects it).
fn arm64_emit_permute(opc: u64, rd: u64, rn: u64, rm: u64, arr: u64,
        what: string) {
    arm64_arr_check(arr, what);
    assert(arr != arm64_arr_1d, sym.join(what, ": 1D arrangement not supported"));
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        sym.join(what, ": registers must be V registers"));
    emit.u32((arm64_arr_q(arr) << 30) | (0x0e << 24)
        | (arm64_arr_esize(arr) << 22) | (arm64_reg_number(rm) << 16)
        | (opc << 12) | (2 << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

// UZP1 (unzip even lanes). clang: uzp1 v0.16b, v1.16b, v2.16b ->
// 0x4e021820; uzp1 v6.4h, v7.4h, v8.4h -> 0x0e4818e6.
fn arm64_uzp1(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(1, vd, vn, vm, arr, "uzp1")
}

// UZP2 (unzip odd lanes). clang: uzp2 v3.8b, v4.8b, v5.8b -> 0x0e055883;
// uzp2 v27.2d, v28.2d, v29.2d -> 0x4edd5b9b.
fn arm64_uzp2(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(5, vd, vn, vm, arr, "uzp2")
}

// ZIP1 (zip, first halves). clang: zip1 v12.2s, v13.2s, v14.2s ->
// 0x0e8e39ac; zip1 v18.2d, v19.2d, v20.2d -> 0x4ed43a72.
fn arm64_zip1(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(3, vd, vn, vm, arr, "zip1")
}

// ZIP2 (zip, second halves). clang: zip2 v15.4s, v16.4s, v17.4s ->
// 0x4e917a0f; zip2 v24.16b, v25.16b, v26.16b -> 0x4e1a7b38.
fn arm64_zip2(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(7, vd, vn, vm, arr, "zip2")
}
