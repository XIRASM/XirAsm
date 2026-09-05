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
    assert(arr != arm64_arr_1d, "dup: 1D arrangement not supported");
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
    assert(arr != arm64_arr_1d, "dup: 1D arrangement not supported");
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

// --- SIMD pair load/store (LDP/STP/LDNP/STNP, S/D/Q) --------------------------
// Layout (LLVM BaseLoadStorePairOffset/NoAlloc with V = 1; InstrInfo.td:3830-
// 3832 LDNPS/D/Q and the matching STP/LDP FP defs; same shapes as the integer
// pairs in memory.inc):
//   opc(31-30) 101(29-27) V=1(26) 010(25-23) L(22) imm7(21-15) Rt2(14-10)
//   Rn(9-5) Rt(4-0); no-allocate LDNP/STNP use 000 at 25-23. opc 00/01/10
//   selects S/D/Q; imm7 is signed and scaled by the element size (S 4,
//   D 8, Q 16), range -64..63. Rn is GPR64sp (X register or SP).
//   There is no FP pair pre/post-index writeback form in this batch.
fn arm64_emit_pair_v(opc: u64, scale: u64, is_load: bool, no_alloc: bool,
        vt: u64, vt2: u64, rn: u64, offset: u64, what: string) {
    let na: u64 = 2
    if no_alloc {
        na = 0
    }
    arm64_emit_pair_vf(opc, scale, is_load, na, vt, vt2, rn, offset, what)
}

// Generalized SIMD pair core: na selects the 25-23 field (010 = signed
// offset, 000 = no-allocate, 001 = post-index writeback).
fn arm64_emit_pair_vf(opc: u64, scale: u64, is_load: bool, na: u64,
        vt: u64, vt2: u64, rn: u64, offset: u64, what: string) {
    assert(arm64_is_v(vt) == 1 && arm64_is_v(vt2) == 1,
        sym.join(what, ": registers must be V registers"));
    if is_load {
        assert(arm64_reg_number(vt) != arm64_reg_number(vt2),
            sym.join(what, ": Rt2==Rt is unpredictable for LDP"));
    }
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(offset % scale == 0, sym.join(what, ": offset must be a multiple of the element size (", to_string(scale), ")"));
    let imm7: u64 = 0
    if offset >= 0x8000000000000000 {
        const mag: u64 = (-offset) / scale
        assert(mag <= 64, sym.join(what, ": offset out of range"));
        imm7 = (-mag) & 0x7f
    } else {
        const mag: u64 = offset / scale
        assert(mag < 64, sym.join(what, ": offset out of range"));
        imm7 = mag
    }
    let l: u64 = 0
    if is_load {
        l = 1
    }
    emit.u32((opc << 30) | (0x5 << 27) | (1 << 26) | (na << 23) | (l << 22)
        | ((imm7 & 0x7f) << 15) | (arm64_reg_number(vt2) << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(vt))
}

// Pair post-index forms (immediate only; the offset is the scaled imm7,
// -64..63). clang: ldp s0, s1, [x2], #4 -> 0x2cc08440;
// stp q14, q15, [x16, #-16] style bounds match the offset pair.
fn arm64_ldp_s_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(0, 4, true, 1, vt, vt2, rn, offset, "ldp s post")
}

fn arm64_ldp_d_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(1, 8, true, 1, vt, vt2, rn, offset, "ldp d post")
}

fn arm64_ldp_q_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(2, 16, true, 1, vt, vt2, rn, offset, "ldp q post")
}

fn arm64_stp_s_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(0, 4, false, 1, vt, vt2, rn, offset, "stp s post")
}

fn arm64_stp_d_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(1, 8, false, 1, vt, vt2, rn, offset, "stp d post")
}

fn arm64_stp_q_post(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_vf(2, 16, false, 1, vt, vt2, rn, offset, "stp q post")
}

// LDP (floating-point S pair). clang: ldp s0, s1, [x2] -> 0x2d400440.
fn arm64_ldp_s(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(0, 4, true, false, vt, vt2, rn, offset, "ldp s")
}

// LDP (floating-point D pair). clang: ldp d3, d4, [x5, #8] -> 0x6d4090a3.
fn arm64_ldp_d(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(1, 8, true, false, vt, vt2, rn, offset, "ldp d")
}

// LDP (Q pair, full 128-bit pair load). clang: ldp q6, q7, [sp] ->
// 0xad401fe6.
fn arm64_ldp_q(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(2, 16, true, false, vt, vt2, rn, offset, "ldp q")
}

// STP (floating-point S pair). clang: stp s8, s9, [x10, #252] ->
// 0x2d1fa548.
fn arm64_stp_s(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(0, 4, false, false, vt, vt2, rn, offset, "stp s")
}

// STP (floating-point D pair). clang: stp d11, d12, [x13, #-8] ->
// 0x6d3fb1ab.
fn arm64_stp_d(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(1, 8, false, false, vt, vt2, rn, offset, "stp d")
}

// STP (Q pair). clang: stp q14, q15, [x16, #-16] -> 0xad3fbe0e.
fn arm64_stp_q(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(2, 16, false, false, vt, vt2, rn, offset, "stp q")
}

// LDNP (floating-point S pair, no allocate). clang: ldnp s17, s18, [x19]
// -> 0x2c404a71.
fn arm64_ldnp_s(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(0, 4, true, true, vt, vt2, rn, offset, "ldnp s")
}

// LDNP (floating-point D pair, no allocate). clang: ldnp d20, d21,
// [x22, #16] -> 0x6c4156d4.
fn arm64_ldnp_d(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(1, 8, true, true, vt, vt2, rn, offset, "ldnp d")
}

// LDNP (Q pair, no allocate). clang: ldnp q23, q24, [x25, #-16] ->
// 0xac7fe337.
fn arm64_ldnp_q(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(2, 16, true, true, vt, vt2, rn, offset, "ldnp q")
}

// STNP (floating-point S pair, no allocate). clang: stnp s25, s26, [x27]
// -> 0x2c006b79.
fn arm64_stnp_s(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(0, 4, false, true, vt, vt2, rn, offset, "stnp s")
}

// STNP (floating-point D pair, no allocate). clang: stnp d28, d29,
// [x30, #8] -> 0x6c00f7dc.
fn arm64_stnp_d(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(1, 8, false, true, vt, vt2, rn, offset, "stnp d")
}

// STNP (Q pair, no allocate). clang: stnp q0, q1, [x2, #-16] ->
// 0xac3f8440.
fn arm64_stnp_q(vt: u64, vt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_v(2, 16, false, true, vt, vt2, rn, offset, "stnp q")
}

// --- Vector FP arithmetic (three-same FP, tied FMLA/FMLS, one-source misc) ----
// Three-same FP (LLVM SIMDThreeSameVectorFP, AArch64InstrFormats.td:6433, over
// BaseSIMDThreeSameVector :6256): same layout as the integer three-same but
// size = {S, 01|11} (S flag at bit 23, 01 = S lanes, 11 = D lanes) and
// opcode = {0b11, opc} at bits 15-11. Arrangements are 2S/4S/2D only.
// Opcodes (U, S, opc3): FADD (0,0,2), FSUB (0,1,2), FMUL (1,0,3), FDIV
// (1,0,7), FMAX (0,0,6), FMIN (0,1,6), FMAXNM (0,0,0), FMINNM (0,1,0);
// the tied FMLA (0,0,1) / FMLS (0,1,1) share the field layout.
fn arm64_check_arr_fp(arr: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arm64_arr_esize(arr) >= 2 && arr != arm64_arr_1d,
        sym.join(what, ": arrangement must be 2S, 4S or 2D"));
}

fn arm64_arr_fpsz(arr: u64) -> u64 {
    let sz: u64 = 1
    if arm64_arr_esize(arr) == 3 {
        sz = 3
    }
    return sz;
}

fn arm64_emit_fp3same(q: u64, u: u64, s_bit: u64, opc3: u64, arr: u64,
        rd: u64, rn: u64, rm: u64) {
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1 && arm64_is_v(rm) == 1,
        "fp three-same: registers must be V registers");
    const size3: u64 = (s_bit << 2) | arm64_arr_fpsz(arr)
    const opcode5: u64 = (3 << 3) | opc3
    emit.u32((q << 30) | (u << 29) | (0x0e << 24) | (size3 << 21)
        | (arm64_reg_number(rm) << 16) | (opcode5 << 11) | (1 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// FADD (vector). clang: fadd v0.2s, v1.2s, v2.2s -> 0x0e22d420;
// fadd v6.2d, v7.2d, v8.2d -> 0x4e68d4e6.
fn arm64_fadd_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fadd");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 0, 2, arr, vd, vn, vm)
}

// FSUB (vector). clang: fsub v9.4s, v10.4s, v11.4s -> 0x4eabd549.
fn arm64_fsub_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fsub");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 1, 2, arr, vd, vn, vm)
}

// FMUL (vector). clang: fmul v12.2s, v13.2s, v14.2s -> 0x2e2eddac.
fn arm64_fmul_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmul");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 0, 3, arr, vd, vn, vm)
}

// FDIV (vector). clang: fdiv v15.2d, v16.2d, v17.2d -> 0x6e71fe0f.
fn arm64_fdiv_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fdiv");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 0, 7, arr, vd, vn, vm)
}

// FMAX (vector). clang: fmax v18.4s, v19.4s, v20.4s -> 0x4e34f672.
fn arm64_fmax_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmax");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 0, 6, arr, vd, vn, vm)
}

// FMIN (vector). clang: fmin v21.4s, v22.4s, v23.4s -> 0x4eb7f6d5.
fn arm64_fmin_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmin");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 1, 6, arr, vd, vn, vm)
}

// FMAXNM (vector, IEEE 754 maxNum NaN handling). clang: fmaxnm v24.2d,
// v25.2d, v26.2d -> 0x4e7ac738.
fn arm64_fmaxnm_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmaxnm");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 0, 0, arr, vd, vn, vm)
}

// FMINNM (vector). clang: fminnm v27.2s, v28.2s, v29.2s -> 0x0ebdc79b.
fn arm64_fminnm_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fminnm");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 1, 0, arr, vd, vn, vm)
}

// FMLA (tied fused multiply-accumulate: Vd += Vn * Vm). clang:
// fmla v0.4s, v1.4s, v2.4s -> 0x4e22cc20.
fn arm64_fmla_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmla");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 0, 1, arr, vd, vn, vm)
}

// FMLS (tied fused multiply-subtract: Vd -= Vn * Vm). clang:
// fmls v3.2d, v4.2d, v5.2d -> 0x4ee5cc83.
fn arm64_fmls_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fmls");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 1, 1, arr, vd, vn, vm)
}

// One-source vector ops over BaseSIMDTwoSameVector (AArch64InstrFormats.td
// :6769): 0(31) Q(30) U(29) 01110(28-24) size(23-22) 1(21) 00(20-19)
// opcode(16-12) 10(11-10) Rn(9-5) Rd(4-0). size is the arrangement element
// size (integer ABS/NEG use 00..11; the FP one-ops use 10=S, 11=D).
fn arm64_emit_2misc(q: u64, u: u64, opcode: u64, rd: u64, rn: u64, arr: u64) {
    assert(arm64_is_v(rd) == 1 && arm64_is_v(rn) == 1,
        "two-misc: registers must be V registers");
    emit.u32((q << 30) | (u << 29) | (0x0e << 24)
        | (arm64_arr_esize(arr) << 22) | (1 << 21) | (opcode << 12) | (2 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// FABS (vector). clang: fabs v6.2s, v7.2s -> 0x0ea0f8e6;
// fabs v10.2d, v11.2d -> 0x4ee0f96a.
fn arm64_fabs_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fabs");
    arm64_emit_2misc(arm64_arr_q(arr), 0, 15, vd, vn, arr)
}

// FNEG (vector). clang: fneg v12.4s, v13.4s -> 0x6ea0f9ac.
fn arm64_fneg_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fneg");
    arm64_emit_2misc(arm64_arr_q(arr), 1, 15, vd, vn, arr)
}

// FSQRT (vector). clang: fsqrt v14.2d, v15.2d -> 0x6ee1f9ee.
fn arm64_fsqrt_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fsqrt");
    arm64_emit_2misc(arm64_arr_q(arr), 1, 31, vd, vn, arr)
}

// --- Vector comparisons --------------------------------------------------------
// Integer compares are three-same (LLVM SIMDThreeSameVector): CMEQ (U=1,
// opc 10001), CMTST (U=0, 10001), CMGT (U=0, 00110), CMGE (U=0, 00111),
// CMHI (U=1, 00110), CMHS (U=1, 00111). FP compares are the FP three-same
// (LLVM SIMDThreeSameVectorFPCmp, formats.td:6455): FCMEQ (0,0,4),
// FCMGE (1,0,4), FCMGT (1,1,4), FACGE (1,0,5), FACGT (1,1,5); FCMLE/FCMLT
// exist only as #0 forms (swap operands for the register semantics).
// Integer compares accept all arrangements except 1D, FP compares 2S/4S/2D.

// CMEQ (compare bitwise equal, per lane). clang: cmeq v0.16b, v1.16b,
// v2.16b -> 0x6e228c20.
fn arm64_cmeq_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmeq");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        17, vd, vn, vm)
}

// CMGT (signed greater-than). clang: cmgt v9.8h, v10.8h, v11.8h ->
// 0x4e6b3549.
fn arm64_cmgt_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmgt");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        6, vd, vn, vm)
}

// CMGE (signed greater-than-or-equal). clang: cmge v12.8b, v13.8b, v14.8b
// -> 0x0e2e3dac.
fn arm64_cmge_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmge");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        7, vd, vn, vm)
}

// CMHI (unsigned higher). clang: cmhi v15.4s, v16.4s, v17.4s ->
// 0x6eb1360f.
fn arm64_cmhi_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmhi");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        6, vd, vn, vm)
}

// CMHS (unsigned higher-or-same). clang: cmhs v18.2d, v19.2d, v20.2d ->
// 0x6ef43e72.
fn arm64_cmhs_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmhs");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        7, vd, vn, vm)
}

// CMTST (bitwise test: destination lanes are all-ones where operands AND
// to nonzero). clang: cmtst v21.16b, v22.16b, v23.16b -> 0x4e378ed5.
fn arm64_cmtst_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "cmtst");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        17, vd, vn, vm)
}

// FCMEQ (FP equal, per lane). clang: fcmeq v24.4s, v25.4s, v26.4s ->
// 0x4e3ae738.
fn arm64_fcmeq_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fcmeq");
    arm64_emit_fp3same(arm64_arr_q(arr), 0, 0, 4, arr, vd, vn, vm)
}

// FCMGE (FP greater-than-or-equal). clang: fcmge v27.2d, v28.2d, v29.2d ->
// 0x6e7de79b.
fn arm64_fcmge_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fcmge");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 0, 4, arr, vd, vn, vm)
}

// FCMGT (FP greater-than). clang: fcmgt v0.4s, v1.4s, v2.4s ->
// 0x6ea2e420.
fn arm64_fcmgt_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "fcmgt");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 1, 4, arr, vd, vn, vm)
}

// FACGE (FP absolute greater-than-or-equal). clang: facge v3.2s, v4.2s,
// v5.2s -> 0x2e25ec83.
fn arm64_facge_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "facge");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 0, 5, arr, vd, vn, vm)
}

// FACGT (FP absolute greater-than). clang: facgt v6.2d, v7.2d, v8.2d ->
// 0x6ee8ece6.
fn arm64_facgt_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "facgt");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 1, 5, arr, vd, vn, vm)
}

// ABS (integer absolute value, per lane). clang: abs v9.16b, v10.16b ->
// 0x4e20b949.
fn arm64_abs_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_arith(arr, "abs");
    arm64_emit_2misc(arm64_arr_q(arr), 0, 11, vd, vn, arr)
}

// NEG (integer negate, per lane). clang: neg v13.8h, v14.8h ->
// 0x6e60b9cd.
fn arm64_neg_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_arith(arr, "neg");
    arm64_emit_2misc(arm64_arr_q(arr), 1, 11, vd, vn, arr)
}

// --- Saturating arithmetic (three-same) ----------------------------------------
// Same three-same layout (BaseSIMDThreeSameVector); opcodes (U, opc):
// SQADD (0,1), UQADD (1,1), SQSUB (0,5), UQSUB (1,5), SQSHL (0,9),
// UQSHL (1,9) — all arrangements except 1D; SQDMULH (0,22) and
// SQRDMULH (1,22) are H/S only (LLVM SIMDThreeSameVectorHS).

// SQADD (signed saturating add). clang: sqadd v0.16b, v1.16b, v2.16b ->
// 0x4e220c20; sqadd v6.2d, v7.2d, v8.2d -> 0x4ee80ce6.
fn arm64_sqadd_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sqadd");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        1, vd, vn, vm)
}

// UQADD (unsigned saturating add). clang: uqadd v9.4s, v10.4s, v11.4s ->
// 0x6eab0d49.
fn arm64_uqadd_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "uqadd");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        1, vd, vn, vm)
}

// SQSUB (signed saturating subtract). clang: sqsub v12.8b, v13.8b, v14.8b
// -> 0x0e2e2dac.
fn arm64_sqsub_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sqsub");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        5, vd, vn, vm)
}

// UQSUB (unsigned saturating subtract). clang: uqsub v15.4h, v16.4h,
// v17.4h -> 0x2e712e0f.
fn arm64_uqsub_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "uqsub");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        5, vd, vn, vm)
}

// SQSHL (signed saturating shift left, register form). clang:
// sqshl v18.8h, v19.8h, v20.8h -> 0x4e744e72.
fn arm64_sqshl_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sqshl");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        9, vd, vn, vm)
}

// UQSHL (unsigned saturating shift left, register form). clang:
// uqshl v21.2s, v22.2s, v23.2s -> 0x2eb74ed5.
fn arm64_uqshl_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "uqshl");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        9, vd, vn, vm)
}

// SQDMULH (signed saturating doubling multiply high, H/S lanes). clang:
// sqdmulh v24.4s, v25.4s, v26.4s -> 0x4ebab738.
fn arm64_sqdmulh_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "sqdmulh");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        22, vd, vn, vm)
}

// SQRDMULH (signed saturating rounding doubling multiply high, H/S lanes).
// clang: sqrdmulh v27.8h, v28.8h, v29.8h -> 0x6e7db79b.
fn arm64_sqrdmulh_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "sqrdmulh");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        22, vd, vn, vm)
}

// --- Pairwise adds, min/max, shift-insert --------------------------------------
// ADDP (LLVM SIMDThreeSameVector, U=0 opc 10111): all arrangements except
// 1D. FADDP (SIMDThreeSameVectorFP, U=1 S=0 opc 010): 2S/4S/2D.
// SMAX/SMIN/UMAX/UMIN (SIMDThreeSameVectorBHS, opc 01100/01101 with U for
// signed/unsigned): B/H/S lanes only. SLI/SRI (tied shift-insert, LLVM
// SIMDVectorLShiftBHSDTied / RShiftBHSDTied): the shift-immediate layout
// with U=1 and opcodes 01010 / 01000; SLI encodes immhb = T + shift
// (0..T-1), SRI encodes immhb = 2T - shift (1..T).

// ADDP (pairwise add). clang: addp v0.16b, v1.16b, v2.16b -> 0x4e22bc20;
// addp v3.2d, v4.2d, v5.2d -> 0x4ee5bc83.
fn arm64_addp_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_arith(arr, "addp");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        23, vd, vn, vm)
}

// FADDP (pairwise FP add). clang: faddp v6.4s, v7.4s, v8.4s ->
// 0x6e28d4e6; faddp v9.2d, v10.2d, v11.2d -> 0x6e6bd549.
fn arm64_faddp_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_fp(arr, "faddp");
    arm64_emit_fp3same(arm64_arr_q(arr), 1, 0, 2, arr, vd, vn, vm)
}

// SMAX (signed max, H/S/B lanes... H/S/B only, no D). clang:
// smax v12.8h, v13.8h, v14.8h -> 0x4e6e65ac.
fn arm64_smax_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "smax");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        12, vd, vn, vm)
}

// SMIN (signed min). clang: smin v15.4s, v16.4s, v17.4s -> 0x4eb16e0f.
fn arm64_smin_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "smin");
    arm64_emit_3same(arm64_arr_q(arr), 0, ((arm64_arr_esize(arr) << 1) | 1),
        13, vd, vn, vm)
}

// UMAX (unsigned max). clang: umax v18.16b, v19.16b, v20.16b ->
// 0x6e346672.
fn arm64_umax_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "umax");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        12, vd, vn, vm)
}

// UMIN (unsigned min). clang: umin v21.8b, v22.8b, v23.8b ->
// 0x2e376ed5.
fn arm64_umin_vec(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "umin");
    arm64_emit_3same(arm64_arr_q(arr), 1, ((arm64_arr_esize(arr) << 1) | 1),
        13, vd, vn, vm)
}

// SLI (tied shift left and insert; Vd keeps bits above the shift).
// clang: sli v24.8b, v25.8b, #3 -> 0x2f0b5738.
fn arm64_sli(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sli");
    const t: u64 = 8 << arm64_arr_esize(arr)
    assert(shift <= (t - 1), sym.join("sli: shift amount out of range 0..", to_string(t - 1)));
    arm64_emit_shift_imm(arm64_arr_q(arr), 1, 10, t + shift, vd, vn, "sli")
}

// SRI (tied shift right and insert; Vd keeps bits below the shift).
// clang: sri v26.4s, v27.4s, #12 -> 0x6f34477a.
fn arm64_sri(vd: u64, vn: u64, shift: u64, arr: u64) {
    arm64_check_arr_arith(arr, "sri");
    const t: u64 = 8 << arm64_arr_esize(arr)
    assert(shift >= 1 && shift <= t, sym.join("sri: shift amount out of range 1..", to_string(t)));
    arm64_emit_shift_imm(arm64_arr_q(arr), 1, 8, (2 * t) - shift, vd, vn, "sri")
}

// --- Integer two-register misc (REV64/REV32/REV16, NOT, CNT) -------------------
// Same two-misc layout (BaseSIMDTwoSameVector) with U/opcode per LLVM:
// NOT (U=1, opc 00101, clang prints the preferred alias "mvn"), CNT (U=0,
// 00101), REV16 (U=0, 00001) are B-lane only (8B/16B); REV32 (U=1, 00000)
// reaches H; REV64 (U=0, 00000) reaches S. NOTE: REV32/REV64 take NO D
// lanes and are U=1/U=0 respectively — do not confuse with RBIT/REV which
// are scalar-only.

// NOT (vector bitwise NOT; the assembler prints the alias "mvn").
// clang: not v15.16b, v16.16b -> 0x6e205a0f (disassembles as mvn).
fn arm64_not_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_byte(arr, "not");
    arm64_emit_2misc(arm64_arr_q(arr), 1, 5, vd, vn, arr)
}

// CNT (per-byte population count). clang: cnt v17.8b, v18.8b ->
// 0x0e205a51.
fn arm64_cnt_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_byte(arr, "cnt");
    arm64_emit_2misc(arm64_arr_q(arr), 0, 5, vd, vn, arr)
}

// REV16 (reverse bytes in each 16-bit halfword). clang: rev16 v19.16b,
// v20.16b -> 0x4e201a93.
fn arm64_rev16_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_byte(arr, "rev16");
    arm64_emit_2misc(arm64_arr_q(arr), 0, 1, vd, vn, arr)
}

// REV32 (reverse 16-bit halfwords in each 32-bit word; B/H arrangements).
// clang: rev32 v21.8h, v22.8h -> 0x6e600ad5.
fn arm64_rev32_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "rev32");
    assert(arm64_arr_esize(arr) <= 1,
        sym.join("rev32: arrangement must be 8B, 16B, 4H or 8H"));
    arm64_emit_2misc(arm64_arr_q(arr), 1, 0, vd, vn, arr)
}

// REV64 (reverse 32-bit words in the 64-bit doubleword; B/H/S arrangements).
// clang: rev64 v23.4s, v24.4s -> 0x4ea00b17.
fn arm64_rev64_vec(vd: u64, vn: u64, arr: u64) {
    arm64_check_arr_bhs(arr, "rev64");
    arm64_emit_2misc(arm64_arr_q(arr), 0, 0, vd, vn, arr)
}

// --- EXT, TRN1/TRN2, LD1R, multi-register LD1/ST1 ------------------------------
// EXT (LLVM BaseSIMDBitwiseExtract, AArch64InstrFormats.td:7681):
//   0(31) Q(30) 101110000(29-21) Rm(20-16) 0(15) imm4(14-11) 0(10)
//   Rn(9-5) Rd(4-0). Concatenates Vn:Vm and extracts from byte index imm4;
//   .8B restricts imm4[3] to zero (index 0..7), .16B allows 0..15.
fn arm64_ext(vd: u64, vn: u64, vm: u64, idx: u64, arr: u64) {
    arm64_arr_check(arr, "ext");
    assert(arr == arm64_arr_8b || arr == arm64_arr_16b,
        "ext: arrangement must be 8B or 16B");
    assert(arm64_is_v(vd) == 1 && arm64_is_v(vn) == 1 && arm64_is_v(vm) == 1,
        "ext: registers must be V registers");
    if arr == arm64_arr_8b {
        assert(idx <= 7, "ext 8b: index must be 0..7");
    } else {
        assert(idx <= 15, "ext 16b: index must be 0..15");
    }
    emit.u32((arm64_arr_q(arr) << 30) | 0x2e000000
        | (arm64_reg_number(vm) << 16) | (idx << 11)
        | (arm64_reg_number(vn) << 5) | arm64_reg_number(vd))
}

// TRN1 (transpose, first halves; LLVM SIMDZipVector opc 010).
// clang: trn1 v6.16b, v7.16b, v8.16b -> 0x4e0828e6.
fn arm64_trn1(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(2, vd, vn, vm, arr, "trn1")
}

// TRN2 (transpose, second halves; opc 110). clang: trn2 v9.4h, v10.4h,
// v11.4h -> 0x0e4b6949.
fn arm64_trn2(vd: u64, vn: u64, vm: u64, arr: u64) {
    arm64_emit_permute(6, vd, vn, vm, arr, "trn2")
}

// LD1R (load one structure and replicate to all lanes; LLVM BaseSIMDLdR,
// AArch64InstrFormats.td:11275): 0(31) Q(30) 001101(29-24) 0(23) L=1(22)
// R=0(21) 00000(20-16) opcode=110(15-13) S=0(12) size(11-10) Rn(9-5)
// Vt(4-0). All eight arrangements.
// clang: ld1r { v12.8b }, [x13] -> 0x0d40c1ac; ld1r { v16.2d }, [x17] ->
// 0x4d40ce30.
fn arm64_ld1r(vt: u64, arr: u64, rn: u64) {
    arm64_arr_check(arr, "ld1r");
    assert(arm64_is_v(vt) == 1, "ld1r: register must be a V register");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "ld1r: base must be an X register or SP");
    emit.u32((arm64_arr_q(arr) << 30) | 0x0d000000 | (1 << 22) | (6 << 13)
        | (arm64_arr_esize(arr) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(vt))
}

// Internal: multi-register LD1/ST1 (LLVM SIMDLd1Multiple/SIMDSt1Multiple,
// AArch64InstrFormats.td:11201/11208): same layout as the one-register form
// with opcodes Two=1010, Three=0110, Four=0010. Hardware reads the
// sequential registers Rt+1..Rt+3 (mod 32); the wrappers assert the caller
// named them sequentially for clear diagnostics. All eight arrangements.
fn arm64_emit_ld1st1_n(opc: u64, is_load: bool, vt: u64, rn: u64, arr: u64,
        what: string) {
    arm64_arr_check(arr, what);
    assert(arm64_is_v(vt) == 1, sym.join(what, ": register must be a V register"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    let l: u64 = 0
    if is_load {
        l = 1
    }
    emit.u32((arm64_arr_q(arr) << 30) | (24 << 23) | (l << 22) | (opc << 12)
        | (arm64_arr_esize(arr) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(vt))
}

fn arm64_check_seq(a: u64, b: u64, what: string) {
    assert(arm64_reg_number(b) == ((arm64_reg_number(a) + 1) % 32),
        sym.join(what, ": registers must be sequential (mod 32)"));
}

// LD1 (two-register list). clang: ld1 { v18.8b, v19.8b }, [x20] ->
// 0x0c40a292.
fn arm64_ld1_2(vt: u64, vt2: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "ld1 x2");
    arm64_emit_ld1st1_n(10, true, vt, rn, arr, "ld1 x2")
}

// LD1 (three-register list; wraps mod 32). clang: ld1 { v30.1d, v31.1d,
// v0.1d }, [x1] -> 0x0c406c3e.
fn arm64_ld1_3(vt: u64, vt2: u64, vt3: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "ld1 x3");
    arm64_check_seq(vt2, vt3, "ld1 x3");
    arm64_emit_ld1st1_n(6, true, vt, rn, arr, "ld1 x3")
}

// LD1 (four-register list). clang: ld1 { v21.16b, v22.16b, v23.16b,
// v24.16b }, [x25] -> 0x4c402335.
fn arm64_ld1_4(vt: u64, vt2: u64, vt3: u64, vt4: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "ld1 x4");
    arm64_check_seq(vt2, vt3, "ld1 x4");
    arm64_check_seq(vt3, vt4, "ld1 x4");
    arm64_emit_ld1st1_n(2, true, vt, rn, arr, "ld1 x4")
}

// ST1 (two-register list). clang: st1 { v1.2s, v2.2s }, [x3] ->
// 0x0c00a861.
fn arm64_st1_2(vt: u64, vt2: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "st1 x2");
    arm64_emit_ld1st1_n(10, false, vt, rn, arr, "st1 x2")
}

// ST1 (three-register list). clang: st1 { v26.4h, v27.4h, v28.4h }, [x29]
// -> 0x0c0067ba.
fn arm64_st1_3(vt: u64, vt2: u64, vt3: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "st1 x3");
    arm64_check_seq(vt2, vt3, "st1 x3");
    arm64_emit_ld1st1_n(6, false, vt, rn, arr, "st1 x3")
}

// ST1 (four-register list).
fn arm64_st1_4(vt: u64, vt2: u64, vt3: u64, vt4: u64, arr: u64, rn: u64) {
    arm64_check_seq(vt, vt2, "st1 x4");
    arm64_check_seq(vt2, vt3, "st1 x4");
    arm64_check_seq(vt3, vt4, "st1 x4");
    arm64_emit_ld1st1_n(2, false, vt, rn, arr, "st1 x4")
}

// --- SIMD post-index writeback ------------------------------------------------
// Pair post-index (LLVM BaseLoadStorePairPostIdx, AArch64InstrFormats.td
// :4831): bits 25-23 = 001 and a 7-bit scaled offset at 21-15; immediate
// form only (pairs have no register-offset writeback).
// clang: ldp s0, s1, [x2], #4 -> 0x2cc08440; ldp q3, q4, [x5], #32 ->
// 0xacc110a3; stp d6, d7, [x8], #-8 -> 0x6cbf9d06; stp s9, s10, [x11],
// #-256 -> 0x2ca02969.

// LD1R / LD1 / ST1 post-index (LLVM BaseSIMDLdRPost :11287 and the POST
// variants of BaseSIMDLdSt at :10955): bit 23 set, the increment in Xm at
// bits 20-16. Xm is an X register, or XZR which encodes the implicit
// #transfer-size immediate (list bytes for LD1/ST1, element size for LD1R).
// clang: ld1r { v12.8b }, [x13], x14 -> 0x0dcec1ac; ld1r { v15.4s },
// [x16], #4 -> 0x4ddfca0f; ld1 { v17.16b, v18.16b }, [x19], x20 ->
// 0x4cd4a271; st1 { v21.4h-v23.4h }, [x24], #24 -> 0x0c9f6715;
// ld1 { v25.8b }, [x26], #8 -> 0x0cdf7359.
fn arm64_check_post_xm(xm: u64, what: string) {
    assert(arm64_reg_is64(xm) && !arm64_reg_is_sp(xm),
        sym.join(what, ": increment must be an X register or xzr (#size)"));
}

fn arm64_emit_ld1st1_post(opc: u64, is_load: bool, vt: u64, rn: u64, xm: u64,
        arr: u64, what: string) {
    arm64_arr_check(arr, what);
    assert(arm64_is_v(vt) == 1, sym.join(what, ": register must be a V register"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    arm64_check_post_xm(xm, what);
    let l: u64 = 0
    if is_load {
        l = 1
    }
    emit.u32((arm64_arr_q(arr) << 30) | 0x0c000000 | (1 << 23) | (l << 22)
        | (arm64_reg_number(xm) << 16) | (opc << 12)
        | (arm64_arr_esize(arr) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(vt))
}

// LD1 (one register, post-index). clang: ld1 { v25.8b }, [x26], #8 ->
// 0x0cdf7359 (xm = xzr encodes the implicit #8).
fn arm64_ld1_post(vt: u64, arr: u64, rn: u64, xm: u64) {
    arm64_emit_ld1st1_post(7, true, vt, rn, xm, arr, "ld1 post")
}

// ST1 (one register, post-index).
fn arm64_st1_post(vt: u64, arr: u64, rn: u64, xm: u64) {
    arm64_emit_ld1st1_post(7, false, vt, rn, xm, arr, "st1 post")
}

// LD1 (two-register list, post-index). clang: ld1 { v17.16b, v18.16b },
// [x19], x20 -> 0x4cd4a271.
fn arm64_ld1_2_post(vt: u64, vt2: u64, arr: u64, rn: u64, xm: u64) {
    arm64_check_seq(vt, vt2, "ld1 x2 post");
    arm64_emit_ld1st1_post(10, true, vt, rn, xm, arr, "ld1 x2 post")
}

// LD1 (three-register list, post-index).
fn arm64_ld1_3_post(vt: u64, vt2: u64, vt3: u64, arr: u64, rn: u64, xm: u64) {
    arm64_check_seq(vt, vt2, "ld1 x3 post");
    arm64_check_seq(vt2, vt3, "ld1 x3 post");
    arm64_emit_ld1st1_post(6, true, vt, rn, xm, arr, "ld1 x3 post")
}

// LD1 (four-register list, post-index).
fn arm64_ld1_4_post(vt: u64, vt2: u64, vt3: u64, vt4: u64, arr: u64, rn: u64,
        xm: u64) {
    arm64_check_seq(vt, vt2, "ld1 x4 post");
    arm64_check_seq(vt2, vt3, "ld1 x4 post");
    arm64_check_seq(vt3, vt4, "ld1 x4 post");
    arm64_emit_ld1st1_post(2, true, vt, rn, xm, arr, "ld1 x4 post")
}

// ST1 (two-register list, post-index).
fn arm64_st1_2_post(vt: u64, vt2: u64, arr: u64, rn: u64, xm: u64) {
    arm64_check_seq(vt, vt2, "st1 x2 post");
    arm64_emit_ld1st1_post(10, false, vt, rn, xm, arr, "st1 x2 post")
}

// ST1 (three-register list, post-index). clang: st1 { v21.4h, v22.4h,
// v23.4h }, [x24], #24 -> 0x0c9f6715 (xm = xzr encodes #24).
fn arm64_st1_3_post(vt: u64, vt2: u64, vt3: u64, arr: u64, rn: u64, xm: u64) {
    arm64_check_seq(vt, vt2, "st1 x3 post");
    arm64_check_seq(vt2, vt3, "st1 x3 post");
    arm64_emit_ld1st1_post(6, false, vt, rn, xm, arr, "st1 x3 post")
}

// ST1 (four-register list, post-index).
fn arm64_st1_4_post(vt: u64, vt2: u64, vt3: u64, vt4: u64, arr: u64, rn: u64,
        xm: u64) {
    arm64_check_seq(vt, vt2, "st1 x4 post");
    arm64_check_seq(vt2, vt3, "st1 x4 post");
    arm64_check_seq(vt3, vt4, "st1 x4 post");
    arm64_emit_ld1st1_post(2, false, vt, rn, xm, arr, "st1 x4 post")
}

// LD1R (replicate load, post-index). clang: ld1r { v12.8b }, [x13], x14
// -> 0x0dcec1ac; ld1r { v15.4s }, [x16], #4 -> 0x4ddfca0f.
fn arm64_ld1r_post(vt: u64, arr: u64, rn: u64, xm: u64) {
    arm64_arr_check(arr, "ld1r post");
    assert(arm64_is_v(vt) == 1, "ld1r post: register must be a V register");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "ld1r post: base must be an X register or SP");
    arm64_check_post_xm(xm, "ld1r post");
    emit.u32((arm64_arr_q(arr) << 30) | 0x0d000000 | (1 << 23) | (1 << 22)
        | (6 << 13) | (arm64_arr_esize(arr) << 10)
        | (arm64_reg_number(xm) << 16) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(vt))
}
