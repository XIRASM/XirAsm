// A64 add/subtract: immediate, shifted register, and extended register forms.
// Encoding 31 reads SP on Rn always; Rd is SP for ADD/SUB and ZR for
// ADDS/SUBS (see the checks in arm64/regs.inc).

// --- Add/subtract (immediate) --------------------------------------------------
// Layout: sf(31) op(30) S(29) 100010(28-23) sh(22) imm12(21-10) Rn(9-5) Rd(4-0).
// `shift` is the printed amount, 0 or 12 (the sh bit).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   add w4, w5, #0             -> [a4 00 00 11]
//   add w30, w29, #1, lsl #12  -> [be 07 40 11]
//   sub w4, w20, #546, lsl #12 -> [84 8a 48 51]
fn arm64_emit_addsub_imm(op: u64, setting: bool, rd: u64, rn: u64, imm12: u64, shift: u64) {
    assert(shift == 0 || shift == 12, "add/sub immediate shift must be 0 or 12");
    assert(imm12 < 4096, "add/sub imm12 out of range");
    arm64_check_same_width(rd, rn, "add/sub immediate");
    arm64_check_addsub_rd(rd, setting, "add/sub immediate");
    arm64_check_addsub_rn(rn, "add/sub immediate");
    const sf: u64 = (rd >> 5) & 1
    const shbit: u64 = shift / 12
    let s: u64 = 0
    if setting {
        s = 1
    }
    const base: u64 = (sf << 31) | (op << 30) | (s << 29) | (0x22 << 23)
    emit.u32(base | (shbit << 22) | (imm12 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

fn arm64_add_imm(rd: u64, rn: u64, imm12: u64, shift: u64) {
    arm64_emit_addsub_imm(0, false, rd, rn, imm12, shift);
}

fn arm64_adds_imm(rd: u64, rn: u64, imm12: u64, shift: u64) {
    arm64_emit_addsub_imm(0, true, rd, rn, imm12, shift);
}

fn arm64_sub_imm(rd: u64, rn: u64, imm12: u64, shift: u64) {
    arm64_emit_addsub_imm(1, false, rd, rn, imm12, shift);
}

fn arm64_subs_imm(rd: u64, rn: u64, imm12: u64, shift: u64) {
    arm64_emit_addsub_imm(1, true, rd, rn, imm12, shift);
}

// --- Add/subtract (shifted register) -------------------------------------------
// Layout: sf(31) op(30) S(29) 01011(28-24) shift(23-22) 0(21) Rm(20-16)
//         imm6(15-10) Rn(9-5) Rd(4-0). Rm 31 is ZR; SP only via Rd/Rn.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   add w3, w5, w7             -> [a3 00 07 0b]
//   add w17, w29, w20, lsl #31 -> [b1 7f 14 0b]
//   add w21, w22, w23, lsr #0  -> [d5 02 57 0b]
fn arm64_emit_addsub_reg(op: u64, setting: bool, rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_check_same_width(rd, rn, "add/sub shifted register");
    arm64_check_same_width(rd, rm, "add/sub shifted register");
    arm64_check_addsub_rd(rd, setting, "add/sub shifted register");
    arm64_check_addsub_rn(rn, "add/sub shifted register");
    arm64_check_no_sp(rm, "add/sub shifted register Rm");
    let width: u64 = 32
    if arm64_reg_is64(rd) {
        width = 64
    }
    assert(amount < width, "add/sub shifted register amount out of range");
    assert(shift <= 3, "add/sub shifted register shift must be 0..3");
    const sf: u64 = (rd >> 5) & 1
    let s: u64 = 0
    if setting {
        s = 1
    }
    const base: u64 = (sf << 31) | (op << 30) | (s << 29) | (0xb << 24)
    emit.u32(base | (shift << 22) | (arm64_reg_number(rm) << 16) | (amount << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

fn arm64_add_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_addsub_reg(0, false, rd, rn, rm, shift, amount);
}

fn arm64_adds_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_addsub_reg(0, true, rd, rn, rm, shift, amount);
}

fn arm64_sub_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_addsub_reg(1, false, rd, rn, rm, shift, amount);
}

fn arm64_subs_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_addsub_reg(1, true, rd, rn, rm, shift, amount);
}

// --- Add/subtract (extended register) ------------------------------------------
// Layout: sf(31) op(30) S(29) 01011(28-24) opt(23-22)=00 1(21) Rm(20-16)
//         option(15-13) imm3(12-10) Rn(9-5) Rd(4-0). Rm 31 is ZR.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   add x2, x4, w5, uxtb      -> [82 00 25 8b]
//   cmn x4, w5, uxtb #2 (ADDS xzr) -> [9f 08 25 ab]
//   cmn sp, w19, uxth #4      -> [ff 33 33 ab]
const arm64_uxtb: u64 = 0
const arm64_uxth: u64 = 1
const arm64_uxtw: u64 = 2
const arm64_uxtx: u64 = 3
const arm64_sxtb: u64 = 4
const arm64_sxth: u64 = 5
const arm64_sxtw: u64 = 6
const arm64_sxtx: u64 = 7

fn arm64_emit_addsub_ext(op: u64, setting: bool, rd: u64, rn: u64, rm: u64, option: u64, imm3: u64) {
    assert(option <= 7, "add/sub extended option must be 0..7");
    assert(imm3 <= 4, "add/sub extended imm3 must be 0..4");
    arm64_check_same_width(rd, rn, "add/sub extended register");
    arm64_check_addsub_rd(rd, setting, "add/sub extended register");
    arm64_check_addsub_rn(rn, "add/sub extended register");
    arm64_check_no_sp(rm, "add/sub extended register Rm");
    if option == arm64_uxtx || option == arm64_sxtx {
        assert(arm64_reg_is64(rm), "uxtx/sxtx require an X register");
    } else {
        // uxtb/uxth/uxtw and sxtb/sxth/sxtw all extend from a W source.
        assert(!arm64_reg_is64(rm), "uxtb/uxth/uxtw/sxtb/sxth/sxtw require a W register");
    }
    const sf: u64 = (rd >> 5) & 1
    let s: u64 = 0
    if setting {
        s = 1
    }
    const base: u64 = (sf << 31) | (op << 30) | (s << 29) | (0xb << 24) | (1 << 21)
    emit.u32(base | (arm64_reg_number(rm) << 16) | (option << 13) | (imm3 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

fn arm64_add_ext(rd: u64, rn: u64, rm: u64, option: u64, imm3: u64) {
    arm64_emit_addsub_ext(0, false, rd, rn, rm, option, imm3);
}

fn arm64_adds_ext(rd: u64, rn: u64, rm: u64, option: u64, imm3: u64) {
    arm64_emit_addsub_ext(0, true, rd, rn, rm, option, imm3);
}

fn arm64_sub_ext(rd: u64, rn: u64, rm: u64, option: u64, imm3: u64) {
    arm64_emit_addsub_ext(1, false, rd, rn, rm, option, imm3);
}

fn arm64_subs_ext(rd: u64, rn: u64, rm: u64, option: u64, imm3: u64) {
    arm64_emit_addsub_ext(1, true, rd, rn, rm, option, imm3);
}

// --- Add/subtract with carry ----------------------------------------------------
// Layout: sf(31) op(30) S(29) 1101010(28-22) 0(21) Rm(20-16) 000000(15-10)
//         Rn(9-5) Rd(4-0). op: 0=ADC 1=SBC. No SP; ZR allowed everywhere.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   adc w29, w27, w25 -> [7d 03 19 1a]
//   adc w9, wzr, w10  -> [e9 03 0a 1a]  (Rn 31 is ZR)
fn arm64_emit_carry(op: u64, setting: bool, rd: u64, rn: u64, rm: u64) {
    arm64_check_no_sp(rd, "carry operation");
    arm64_check_no_sp(rn, "carry operation");
    arm64_check_no_sp(rm, "carry operation");
    arm64_check_same_width(rd, rn, "carry operation");
    arm64_check_same_width(rd, rm, "carry operation");
    const sf: u64 = (rd >> 5) & 1
    let s: u64 = 0
    if setting {
        s = 1
    }
    const base: u64 = (sf << 31) | (op << 30) | (s << 29) | (0x1a << 24)
    emit.u32(base | (arm64_reg_number(rm) << 16) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

// ADC, add with carry. ARM ARM C6.2.1.
fn arm64_adc(rd: u64, rn: u64, rm: u64) {
    arm64_emit_carry(0, false, rd, rn, rm);
}

// ADCS, add with carry and set flags. ARM ARM C6.2.3.
fn arm64_adcs(rd: u64, rn: u64, rm: u64) {
    arm64_emit_carry(0, true, rd, rn, rm);
}

// SBC, subtract with carry. ARM ARM C6.2.311.
fn arm64_sbc(rd: u64, rn: u64, rm: u64) {
    arm64_emit_carry(1, false, rd, rn, rm);
}

// SBCS, subtract with carry and set flags. ARM ARM C6.2.312.
fn arm64_sbcs(rd: u64, rn: u64, rm: u64) {
    arm64_emit_carry(1, true, rd, rn, rm);
}

// NGC: alias of SBC Rd, ZR, Rm (ARM ARM C6.2.197). Zero register computed
// arithmetically (wzr = 31, xzr = 31 + 32).
// Fixtures: basic-a64-instructions.s, ngc w9, w10 -> [e9 03 0a 5a].
fn arm64_ngc(rd: u64, rm: u64) {
    arm64_sbc(rd, arm64_wzr + (rd & 32), rm);
}

// NGCS: alias of SBCS Rd, ZR, Rm (ARM ARM C6.2.196).
fn arm64_ngcs(rd: u64, rm: u64) {
    arm64_sbcs(rd, arm64_wzr + (rd & 32), rm);
}

// --- Multiply and divide (M4.7) ----------------------------------------------
// Data-processing 3-source (LLVM BaseMulAccum):
//   sf(31) 0011011(30-24) opc(23-21) Rm(20-16) isSub(15) Ra(14-10) Rn(9-5)
//   Rd(4-0). opc: 000 = MADD/MSUB (isSub), 001 = SMADDL/SMULL (sub = 0) and
//   SMSUBL (sub = 1), 101 = UMADDL/UMULL (sub = 0) and UMSUBL (sub = 1). The
//   widening forms force sf = 1 (LLVM WideMulAccum) with W sources and an X
//   accumulator. SMULH/UMULH
//   (LLVM MulHi): sf 10011011(31-24) opc(23-21) with Ra = 11111;
//   opc 010 = SMULH, 110 = UMULH.
// Division (LLVM BaseDiv over the 2-source layout):
//   sf 0011010110(30-21) Rm(20-16) op2(15-10) Rn Rd; op2 0b000010 = UDIV,
//   0b000011 = SDIV.

fn arm64_emit_mul_accum(sf: u64, opc: u64, is_sub: bool, rd: u64, rn: u64, rm: u64, ra: u64, what: string) {
    let sub: u64 = 0
    if is_sub {
        sub = 1
    }
    emit.u32((sf << 31) | (0x1b << 24) | (opc << 21) | (arm64_reg_number(rm) << 16)
        | (sub << 15) | (arm64_reg_number(ra) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

// MADD (W/X by Rd; all four registers one width). ARM ARM C6.2.202.
fn arm64_madd(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_check_same_width(rd, rn, "madd");
    arm64_check_same_width(rd, rm, "madd");
    arm64_check_same_width(rd, ra, "madd");
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_mul_accum(sf, 0, false, rd, rn, rm, ra, "madd")
}

// MUL — alias of MADD with the accumulator at ZR. ARM ARM C6.2.329.
fn arm64_mul(rd: u64, rn: u64, rm: u64) {
    arm64_check_same_width(rd, rn, "mul");
    arm64_check_same_width(rd, rm, "mul");
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_mul_accum(sf, 0, false, rd, rn, rm, arm64_xzr, "mul")
}

// MSUB (W/X by Rd). ARM ARM C6.2.331.
fn arm64_msub(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_check_same_width(rd, rn, "msub");
    arm64_check_same_width(rd, rm, "msub");
    arm64_check_same_width(rd, ra, "msub");
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_mul_accum(sf, 0, true, rd, rn, rm, ra, "msub")
}

// Internal: widening multiply-accumulate (Wn/Wm sources, Xd/Xa accumulator,
// sf forced to 1 per LLVM WideMulAccum).
fn arm64_emit_wide_mul_accum(opc: u64, is_sub: bool, rd: u64, rn: u64, rm: u64, ra: u64, what: string) {
    assert(arm64_reg_is64(rd), sym.join(what, ": accumulator must be an X register"));
    assert(!arm64_reg_is64(rn), sym.join(what, ": sources must be W registers"));
    assert(!arm64_reg_is64(rm), sym.join(what, ": sources must be W registers"));
    assert(arm64_reg_is64(ra), sym.join(what, ": accumulator must be an X register"));
    let sub: u64 = 0
    if is_sub {
        sub = 1
    }
    emit.u32((1 << 31) | (0x1b << 24) | (opc << 21) | (arm64_reg_number(rm) << 16)
        | (sub << 15) | (arm64_reg_number(ra) << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

// SMADDL. ARM ARM C6.2.311 (opc 001, signed widen, add).
fn arm64_smaddl(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_emit_wide_mul_accum(1, false, rd, rn, rm, ra, "smaddl")
}

// SMSUBL. ARM ARM C6.2.317 (opc 001 like SMADDL, isSub = 1).
fn arm64_smsubl(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_emit_wide_mul_accum(1, true, rd, rn, rm, ra, "smsubl")
}

// SMULL — alias of SMADDL with the accumulator at XZR. ARM ARM C6.2.314.
fn arm64_smull(rd: u64, rn: u64, rm: u64) {
    arm64_emit_wide_mul_accum(1, false, rd, rn, rm, arm64_xzr, "smull")
}

// UMADDL (opc 101, unsigned widen, add). ARM ARM C6.2.381.
fn arm64_umaddl(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_emit_wide_mul_accum(5, false, rd, rn, rm, ra, "umaddl")
}

// UMSUBL (opc 101, unsigned widen, subtract). ARM ARM C6.2.386.
fn arm64_umsubl(rd: u64, rn: u64, rm: u64, ra: u64) {
    arm64_emit_wide_mul_accum(5, true, rd, rn, rm, ra, "umsubl")
}

// UMULL — alias of UMADDL with the accumulator at XZR. ARM ARM C6.2.387.
fn arm64_umull(rd: u64, rn: u64, rm: u64) {
    arm64_emit_wide_mul_accum(5, false, rd, rn, rm, arm64_xzr, "umull")
}

// SMULH (signed high half, X only, opc 010; LLVM MulHi with Ra = 11111).
// ARM ARM C6.2.313.
fn arm64_smulh(rd: u64, rn: u64, rm: u64) {
    assert(arm64_reg_is64(rd) && arm64_reg_is64(rn) && arm64_reg_is64(rm),
        "smulh requires X registers");
    emit.u32((1 << 31) | (0x1b << 24) | (2 << 21) | (arm64_reg_number(rm) << 16)
        | (0x1f << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// UMULH (unsigned high half, opc 110). ARM ARM C6.2.385.
fn arm64_umulh(rd: u64, rn: u64, rm: u64) {
    assert(arm64_reg_is64(rd) && arm64_reg_is64(rn) && arm64_reg_is64(rm),
        "umulh requires X registers");
    emit.u32((1 << 31) | (0x1b << 24) | (6 << 21) | (arm64_reg_number(rm) << 16)
        | (0x1f << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// SDIV/UDIV (W/X by Rd; LLVM BaseDiv, op2 0b000011 / 0b000010).
// ARM ARM C6.2.303 / C6.2.384.
fn arm64_emit_div(is_signed: bool, rd: u64, rn: u64, rm: u64, what: string) {
    arm64_check_same_width(rd, rn, what);
    arm64_check_same_width(rd, rm, what);
    let sf: u64 = (rd >> 5) & 1
    let s: u64 = 0
    if is_signed {
        s = 1
    }
    // op2: 0b000010 (UDIV) with bit10 added for SDIV.
    emit.u32((sf << 31) | (0b0011010110 << 21) | (arm64_reg_number(rm) << 16)
        | (0b000010 << 10) | (s << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

fn arm64_sdiv(rd: u64, rn: u64, rm: u64) {
    arm64_emit_div(true, rd, rn, rm, "sdiv")
}

fn arm64_udiv(rd: u64, rn: u64, rm: u64) {
    arm64_emit_div(false, rd, rn, rm, "udiv")
}

// --- CRC32 (FEAT_CRC32) -------------------------------------------------------
// LLVM BaseCRC32: sf(31) 0011010110(30-21) Rm(20-16) 010(15-13) C(12)
// sz(11-10) Rn(9-5) Rd(4-0). Rd/Rn are W; Rm is W except the X forms
// (sf = 1, sz = 11). C = 1 selects the castagnoli (crc32c) variants.

fn arm64_emit_crc32(sf: u64, sz: u64, c: bool, rd: u64, rn: u64, rm: u64, what: string) {
    assert(arm64_reg_is64(rm) == (sz == 3), sym.join(what, ": Rm width must match the size"));
    assert(!arm64_reg_is64(rd), sym.join(what, ": Rd must be a W register"));
    assert(!arm64_reg_is64(rn), sym.join(what, ": Rn must be a W register"));
    let cc: u64 = 0
    if c {
        cc = 1
    }
    emit.u32((sf << 31) | (0b0011010110 << 21) | (arm64_reg_number(rm) << 16)
        | (0b010 << 13) | (cc << 12) | (sz << 10) | (arm64_reg_number(rn) << 5)
        | arm64_reg_number(rd))
}

// CRC32B (crc32b w0, w1, w2 -> 0x1ac24020).
fn arm64_crc32b(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 0, false, rd, rn, rm, "crc32b")
}

// CRC32H (crc32h w0, w1, w2).
fn arm64_crc32h(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 1, false, rd, rn, rm, "crc32h")
}

// CRC32W (crc32w w0, w1, w2).
fn arm64_crc32w(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 2, false, rd, rn, rm, "crc32w")
}

// CRC32X (crc32x w0, w1, x2 -> 0x9ac24c20).
fn arm64_crc32x(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(1, 3, false, rd, rn, rm, "crc32x")
}

// CRC32CB (crc32cb w0, w1, w2 -> 0x1ac25020).
fn arm64_crc32cb(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 0, true, rd, rn, rm, "crc32cb")
}

// CRC32CH (crc32ch w0, w1, w2).
fn arm64_crc32ch(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 1, true, rd, rn, rm, "crc32ch")
}

// CRC32CW (crc32cw w0, w1, w2).
fn arm64_crc32cw(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(0, 2, true, rd, rn, rm, "crc32cw")
}

// CRC32CX (crc32cx w0, w1, x2).
fn arm64_crc32cx(rd: u64, rn: u64, rm: u64) {
    arm64_emit_crc32(1, 3, true, rd, rn, rm, "crc32cx")
}

// --- Data-processing (1 source) -----------------------------------------------
// LLVM BaseOneOperandData: sf(31) 1(30) S=0(29) 11010110(28-21) opc2=0(20-16)
// opc(15-10) Rn(9-5) Rd(4-0); S is 0b0 for every integer form (per the defs:
// RBIT/REV16/REV32/REV/CLZ/CLS all pass 0b0). opc: 000000 = RBIT, 000001 =
// REV16, 000010 = REV32 (X only) / REV (W), 000011 = REV (X), 000100 = CLZ,
// 000101 = CLS.

fn arm64_emit_dp1(sf: u64, opc: u64, rd: u64, rn: u64, what: string) {
    arm64_check_same_width(rd, rn, what);
    emit.u32((sf << 31) | (1 << 30) | (0b11010110 << 21)
        | (opc << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd))
}

// RBIT (W/X by Rd). ARM ARM C6.2.325.
fn arm64_rbit(rd: u64, rn: u64) {
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_dp1(sf, 0, rd, rn, "rbit")
}

// REV16 (W/X by Rd). ARM ARM C6.2.307.
fn arm64_rev16(rd: u64, rn: u64) {
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_dp1(sf, 1, rd, rn, "rev16")
}

// REV32 (X only; the W analog is REV). ARM ARM C6.2.308.
fn arm64_rev32(rd: u64, rn: u64) {
    assert(arm64_reg_is64(rd) && arm64_reg_is64(rn), "rev32 requires X registers");
    arm64_emit_dp1(1, 2, rd, rn, "rev32")
}

// REV (W/X by Rd; the X form is opc 000011, W is 000010). ARM ARM C6.2.306.
fn arm64_rev(rd: u64, rn: u64) {
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_dp1(sf, 2 + sf, rd, rn, "rev")
}

// CLZ (W/X by Rd). ARM ARM C6.2.66.
fn arm64_clz(rd: u64, rn: u64) {
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_dp1(sf, 4, rd, rn, "clz")
}

// CLS (W/X by Rd). ARM ARM C6.2.65.
fn arm64_cls(rd: u64, rn: u64) {
    let sf: u64 = (rd >> 5) & 1
    arm64_emit_dp1(sf, 5, rd, rn, "cls")
}
