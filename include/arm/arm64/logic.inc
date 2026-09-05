// A64 logical operations, bitfield moves, and shift aliases.

// --- Logical (shifted register) -------------------------------------------------
// Layout: sf(31) opc(30-29) 01010(28-24) shift(23-22) N(21) Rm(20-16)
//         imm6(15-10) Rn(9-5) Rd(4-0). No SP anywhere; 31 is ZR.
// opc/N: AND=00/0 BIC=00/1 ORR=01/0 ORN=01/1 EOR=10/0 EON=10/1 ANDS=11/0 BICS=11/1
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   bic w2, w7, w9   -> [e2 00 29 0a]
//   orn w2, w5, w29  -> [a2 00 3d 2a]
//   bics w3, w5, w7  -> [a3 00 27 6a]
fn arm64_emit_log_reg(opc: u64, invert: bool, rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_check_no_sp(rd, "logical shifted register");
    arm64_check_no_sp(rn, "logical shifted register");
    arm64_check_no_sp(rm, "logical shifted register");
    arm64_check_same_width(rd, rn, "logical shifted register");
    arm64_check_same_width(rd, rm, "logical shifted register");
    let width: u64 = 32
    if arm64_reg_is64(rd) {
        width = 64
    }
    assert(amount < width, "logical shifted register amount out of range");
    assert(shift <= 3, "logical shifted register shift must be 0..3");
    const sf: u64 = (rd >> 5) & 1
    let n: u64 = 0
    if invert {
        n = 1
    }
    const base: u64 = (sf << 31) | (opc << 29) | (0xa << 24)
    emit.u32(base | (shift << 22) | (n << 21) | (arm64_reg_number(rm) << 16) | (amount << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

fn arm64_and_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(0, false, rd, rn, rm, shift, amount);
}

fn arm64_bic_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(0, true, rd, rn, rm, shift, amount);
}

fn arm64_orr_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(1, false, rd, rn, rm, shift, amount);
}

fn arm64_orn_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(1, true, rd, rn, rm, shift, amount);
}

fn arm64_eor_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(2, false, rd, rn, rm, shift, amount);
}

fn arm64_eon_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(2, true, rd, rn, rm, shift, amount);
}

fn arm64_ands_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(3, false, rd, rn, rm, shift, amount);
}

fn arm64_bics_reg(rd: u64, rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_emit_log_reg(3, true, rd, rn, rm, shift, amount);
}

// --- Logical (immediate) --------------------------------------------------------
// Layout: sf(31) opc(30-29) 100100(28-23) N(22) immr(21-16) imms(15-10)
//         Rn(9-5) Rd(4-0). opc: AND=00 ORR=01 EOR=10 ANDS=11.
// The bitmask is encoded by arm64_logical_imm (arm64/bits.inc).
fn arm64_emit_log_imm_packed(opc: u64, rd: u64, rn: u64, packed_bits: u64) {
    arm64_check_no_sp(rd, "logical immediate");
    arm64_check_no_sp(rn, "logical immediate");
    const sf: u64 = (rd >> 5) & 1
    const n: u64 = (packed_bits >> 12) & 1
    const immr: u64 = (packed_bits >> 6) & 0x3f
    const imms: u64 = packed_bits & 0x3f
    const base: u64 = (sf << 31) | (opc << 29) | (0x24 << 23)
    emit.u32(base | (n << 22) | (immr << 16) | (imms << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

fn arm64_and_imm(rd: u64, rn: u64, value: u64) {
    const enc: u64 = arm64_logical_imm(value, arm64_reg_is64(rd))
    arm64_emit_log_imm_packed(0, rd, rn, enc);
}

fn arm64_orr_imm(rd: u64, rn: u64, value: u64) {
    const enc: u64 = arm64_logical_imm(value, arm64_reg_is64(rd))
    arm64_emit_log_imm_packed(1, rd, rn, enc);
}

fn arm64_eor_imm(rd: u64, rn: u64, value: u64) {
    const enc: u64 = arm64_logical_imm(value, arm64_reg_is64(rd))
    arm64_emit_log_imm_packed(2, rd, rn, enc);
}

fn arm64_ands_imm(rd: u64, rn: u64, value: u64) {
    const enc: u64 = arm64_logical_imm(value, arm64_reg_is64(rd))
    arm64_emit_log_imm_packed(3, rd, rn, enc);
}

// BIC (immediate) is the ARM alias of AND (immediate) with the complemented
// bitmask (ARM ARM C6.2.36).
fn arm64_bic_imm(rd: u64, rn: u64, value: u64) {
    let width_mask: u64 = 0xffffffff
    if arm64_reg_is64(rd) {
        width_mask = 0xffffffffffffffff
    }
    const enc: u64 = arm64_logical_imm((~value) & width_mask, arm64_reg_is64(rd))
    arm64_emit_log_imm_packed(0, rd, rn, enc);
}

// --- Bitfield and shift aliases --------------------------------------------------
// Layout: sf(31) opc(30-29) 100110(28-23) N(22) immr(21-16) imms(15-10)
//         Rn(9-5) Rd(4-0). opc: SBFM=00 BFM=01 UBFM=10; N must equal sf.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   asr x3, x4, #63  -> [83 fc 7f 93]  (SBFM, immr 63, imms 63)
//   asr w3, w2, #0   -> [43 7c 00 13]
fn arm64_emit_bitfield(opc: u64, rd: u64, rn: u64, immr: u64, imms: u64) {
    arm64_check_no_sp(rd, "bitfield");
    arm64_check_no_sp(rn, "bitfield");
    arm64_check_same_width(rd, rn, "bitfield");
    const sf: u64 = (rd >> 5) & 1
    let width: u64 = 32
    if sf == 1 {
        width = 64
    }
    assert(immr < width, "bitfield immr out of range");
    assert(imms < width, "bitfield imms out of range");
    emit.u32((sf << 31) | (opc << 29) | (0x26 << 23) | (sf << 22) | (immr << 16)
        | (imms << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

// SBFM, signed bitfield move. ARM ARM C6.2.313.
fn arm64_sbfm(rd: u64, rn: u64, immr: u64, imms: u64) {
    arm64_emit_bitfield(0, rd, rn, immr, imms);
}

// BFM, bitfield move. ARM ARM C6.2.63.
fn arm64_bfm(rd: u64, rn: u64, immr: u64, imms: u64) {
    arm64_emit_bitfield(1, rd, rn, immr, imms);
}

// UBFM, unsigned bitfield move. ARM ARM C6.2.360.
fn arm64_ubfm(rd: u64, rn: u64, immr: u64, imms: u64) {
    arm64_emit_bitfield(2, rd, rn, immr, imms);
}

// LSL (immediate): alias of UBFM (ARM ARM C6.2.172).
fn arm64_lsl(rd: u64, rn: u64, amount: u64) {
    let width: u64 = 32
    if arm64_reg_is64(rd) {
        width = 64
    }
    assert(amount < width, "lsl amount out of range");
    arm64_ubfm(rd, rn, (width - amount) % width, width - 1 - amount);
}

// LSR (immediate): alias of UBFM (ARM ARM C6.2.175).
fn arm64_lsr(rd: u64, rn: u64, amount: u64) {
    let width: u64 = 32
    if arm64_reg_is64(rd) {
        width = 64
    }
    assert(amount < width, "lsr amount out of range");
    arm64_ubfm(rd, rn, amount, width - 1);
}

// ASR (immediate): alias of SBFM (ARM ARM C6.2.29).
fn arm64_asr(rd: u64, rn: u64, amount: u64) {
    let width: u64 = 32
    if arm64_reg_is64(rd) {
        width = 64
    }
    assert(amount < width, "asr amount out of range");
    arm64_sbfm(rd, rn, amount, width - 1);
}

// ROR (immediate): alias of EXTR with Rm = Rn (ARM ARM C6.2.309).
// Layout: sf(31) 00(30-29) 100111(28-23) N(22) 0(21) Rm(20-16) imms(15-10)
//         Rn(9-5) Rd(4-0).
// Fixtures: basic-a64-instructions.s
//   extr w3, w5, w7, #0     -> [a3 00 87 13]
//   extr w11, w13, w17, #31 -> [ab 7d 91 13]
fn arm64_ror(rd: u64, rn: u64, amount: u64) {
    arm64_check_no_sp(rd, "ror");
    arm64_check_no_sp(rn, "ror");
    arm64_check_same_width(rd, rn, "ror");
    const sf: u64 = (rd >> 5) & 1
    let width: u64 = 32
    if sf == 1 {
        width = 64
    }
    assert(amount < width, "ror amount out of range");
    emit.u32((sf << 31) | (0x27 << 23) | (sf << 22) | (arm64_reg_number(rn) << 16)
        | (amount << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

// TST (shifted register): alias of ANDS ZR, Rn, Rm (ARM ARM C6.2.357).
// Fixtures: basic-a64-instructions.s
//   tst w3, w7, lsl #31 -> [7f 7c 07 6a]
//   tst x2, x20, asr #0 -> [5f 00 94 ea]
fn arm64_tst_reg(rn: u64, rm: u64, shift: u64, amount: u64) {
    arm64_ands_reg(arm64_wzr + (rn & 32), rn, rm, shift, amount);
}

// TST (immediate): alias of ANDS ZR, Rn, #bitmask (ARM ARM C6.2.356).
fn arm64_tst_imm(rn: u64, value: u64) {
    arm64_ands_imm(arm64_wzr + (rn & 32), rn, value);
}
