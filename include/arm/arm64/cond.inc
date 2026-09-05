// A64 conditional compare (CCMP/CCMN) and conditional select
// (CSEL/CSINC/CSINV/CSNEG) families, plus their alias helpers.

fn arm64_cond_invert(cond: u64) -> u64 {
    // Flips eq<->ne, cs<->cc, mi<->pl, vs<->vc, hi<->ls, ge<->lt, gt<->le
    // (ARM ARM C6.2.86 ConditionHolds: the invert of a 4-bit cond is cond^1
    // for the fourteen encodable conditions).
    assert(cond <= 13, "condition code must be 0..13");
    return cond ^ 1;
}

// --- Conditional compare ---------------------------------------------------------
// Layout: sf(31) op(30) 111010010(29-21) Rm/imm5(20-16) cond(15-12) form(11-10)
//         Rn(9-5) nzcv(3-0). op: 0=CCMN 1=CCMP; form: 00=register 10=immediate.
// Bases derived from MC fixtures:
//   ccmp w1, #31, #0, eq -> [20 08 5f 7a]   (immediate form)
//   ccmp w1, wzr, #0, eq -> [20 00 5f 7a]   (register form, Rm 31 = ZR)
fn arm64_emit_ccmp(op: u64, is_imm: bool, rn: u64, operand: u64, nzcv: u64, cond: u64) {
    arm64_check_no_sp(rn, "conditional compare");
    assert(operand <= 31, "conditional compare imm5/register number out of range");
    assert(nzcv <= 15, "conditional compare nzcv out of range");
    assert(cond <= 13, "conditional compare requires a real condition code (0..13)");
    const sf: u64 = (rn >> 5) & 1
    let form: u64 = 0
    if is_imm {
        form = 2
    }
    emit.u32((sf << 31) | (op << 30) | (0x1d2 << 21) | (operand << 16) | (cond << 12)
        | (form << 10) | (arm64_reg_number(rn) << 5) | nzcv);
}

// CCMP (register). ARM ARM C6.2.51. Rm/Rn accept ZR, not SP.
fn arm64_ccmp_reg(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_check_no_sp(rm, "conditional compare");
    arm64_check_same_width(rn, rm, "conditional compare");
    arm64_emit_ccmp(1, false, rn, arm64_reg_number(rm), nzcv, cond);
}

// CCMP (immediate). ARM ARM C6.2.50.
fn arm64_ccmp_imm(rn: u64, imm5: u64, nzcv: u64, cond: u64) {
    arm64_emit_ccmp(1, true, rn, imm5, nzcv, cond);
}

// CCMN (register). ARM ARM C6.2.47.
fn arm64_ccmn_reg(rn: u64, rm: u64, nzcv: u64, cond: u64) {
    arm64_check_no_sp(rm, "conditional compare");
    arm64_check_same_width(rn, rm, "conditional compare");
    arm64_emit_ccmp(0, false, rn, arm64_reg_number(rm), nzcv, cond);
}

// CCMN (immediate). ARM ARM C6.2.46.
fn arm64_ccmn_imm(rn: u64, imm5: u64, nzcv: u64, cond: u64) {
    arm64_emit_ccmp(0, true, rn, imm5, nzcv, cond);
}

// --- Conditional select ------------------------------------------------------------
// Layout: sf(31) 0(30) op1(29) 110100(28-23) 1(22) 0(21) Rm(20-16) cond(15-12)
//         op2(11-10) Rn(9-5) Rd(4-0). op1/op2: 0/0=CSEL 0/1=CSINC 1/0=CSINV
//         1/1=CSNEG. No SP; ZR allowed everywhere.
// Fixtures: basic-a64-instructions.s
//   csel  w1, w0, w19, ne -> [01 10 93 1a]
//   csinc w1, w0, w19, ne -> [01 14 93 1a]  (op2 = 01)
//   csinv w1, w0, w19, ne -> [01 10 93 5a]  (op1 = 1)
fn arm64_emit_csel(op1: u64, op2: u64, rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_check_no_sp(rd, "conditional select");
    arm64_check_no_sp(rn, "conditional select");
    arm64_check_no_sp(rm, "conditional select");
    arm64_check_same_width(rd, rn, "conditional select");
    arm64_check_same_width(rd, rm, "conditional select");
    assert(op1 <= 1 && op2 <= 1, "internal: conditional select op bits");
    assert(cond <= 13, "conditional select requires a real condition code (0..13)");
    const sf: u64 = (rd >> 5) & 1
    emit.u32((sf << 31) | (op1 << 30) | (0x1a << 24) | (0x800000) | (op2 << 10)
        | (arm64_reg_number(rm) << 16) | (cond << 12) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rd));
}

// CSEL. ARM ARM C6.2.82.
fn arm64_csel(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_csel(0, 0, rd, rn, rm, cond);
}

// CSINC. ARM ARM C6.2.81.
fn arm64_csinc(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_csel(0, 1, rd, rn, rm, cond);
}

// CSINV. ARM ARM C6.2.80.
fn arm64_csinv(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_csel(1, 0, rd, rn, rm, cond);
}

// CSNEG. ARM ARM C6.2.83.
fn arm64_csneg(rd: u64, rn: u64, rm: u64, cond: u64) {
    arm64_emit_csel(1, 1, rd, rn, rm, cond);
}

// --- Aliases of the conditional select group ----------------------------------------

// CSET: alias of CSINC Rd, ZR, ZR, invert(cond) (ARM ARM C6.2.78).
// Fixtures: basic-a64-instructions.s, cset w3, eq -> [e3 17 9f 1a].
fn arm64_cset(rd: u64, cond: u64) {
    const zr: u64 = arm64_wzr + (rd & 32)
    arm64_csinc(rd, zr, zr, arm64_cond_invert(cond));
}

// CSETM: alias of CSINV Rd, ZR, ZR, invert(cond) (ARM ARM C6.2.79).
// Fixtures: basic-a64-instructions.s, csetm w20, ne -> [f4 03 9f 5a].
fn arm64_csetm(rd: u64, cond: u64) {
    const zr: u64 = arm64_wzr + (rd & 32)
    arm64_csinv(rd, zr, zr, arm64_cond_invert(cond));
}

// CINC: alias of CSINC Rd, Rn, Rn, invert(cond) (ARM ARM C6.2.44).
// Fixtures: basic-a64-instructions.s, cinc w3, w5, gt -> [a3 d4 85 1a].
fn arm64_cinc(rd: u64, rn: u64, cond: u64) {
    arm64_csinc(rd, rn, rn, arm64_cond_invert(cond));
}

// CINV: alias of CSINV Rd, Rn, Rn, invert(cond) (ARM ARM C6.2.43).
fn arm64_cinv(rd: u64, rn: u64, cond: u64) {
    arm64_csinv(rd, rn, rn, arm64_cond_invert(cond));
}

// CNEG: alias of CSNEG Rd, Rn, Rn, invert(cond) (ARM ARM C6.2.56).
fn arm64_cneg(rd: u64, rn: u64, cond: u64) {
    arm64_csneg(rd, rn, rn, arm64_cond_invert(cond));
}
