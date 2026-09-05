// A64 control flow: NOP, RET, condition codes, and all PC-relative branches.

// NOP, hint 0. ARM ARM C6.2.170.
// Fixture: llvm/test/MC/AArch64/arm64-system-encoding.s, encoding [1f 20 03 d5].
fn arm64_nop() {
    emit.u32(0xd503201f);
}

// RET with the default return register x30. ARM ARM C6.2.329.
// Fixture: llvm/test/MC/AArch64/arm64-branch-encoding.s, encoding [c0 03 5f d6].
fn arm64_ret() {
    emit.u32(0xd65f03c0);
}

// --- Condition codes (B.cond) -------------------------------------------------
// ARM ARM C6.2.24 Conditional branch. Conditions 14 (AL) and 15 (NV) are not
// encodable as B.cond; use arm64_b for an unconditional branch.

const arm64_cond_eq: u64 = 0
const arm64_cond_ne: u64 = 1
const arm64_cond_cs: u64 = 2
const arm64_cond_cc: u64 = 3
const arm64_cond_mi: u64 = 4
const arm64_cond_pl: u64 = 5
const arm64_cond_vs: u64 = 6
const arm64_cond_vc: u64 = 7
const arm64_cond_hi: u64 = 8
const arm64_cond_ls: u64 = 9
const arm64_cond_ge: u64 = 10
const arm64_cond_lt: u64 = 11
const arm64_cond_gt: u64 = 12
const arm64_cond_le: u64 = 13
// HS/LO are the alternate spellings of CS/CC (unsigned higher-or-same / lower).
const arm64_cond_hs: u64 = 2
const arm64_cond_lo: u64 = 3

// --- PC-relative branches ------------------------------------------------------
//
// A64 PC-relative immediates count words from the branch instruction itself
// (ARM ARM C6.3.2). The emitters below write an opcode-preserving placeholder
// (immediate field zero), then register one deferred patch that resolves the
// label by name and merges the signed displacement into the low `bits` bits at
// `field_lsb`. The placeholder is required because forward labels cannot be
// read during ordinary source evaluation.
//
// Fixtures (displacement formulas; offsets depend on test layout):
//   llvm/test/MC/AArch64/basic-a64-instructions.s
//     cbz w5, #0    -> [05 00 00 34]   (base 0x34000000 | Rt)
//     cbnz x3, #-4  -> [e3 ff ff b5]   (signed imm19, backward)
//     tbz w5, #0    -> low byte 0x36   (base 0x36000000 | Rt)
//     tbnz x5, #45  -> low byte 0xb7   (b5 = 1, op = 1)
//   llvm/test/MC/AArch64/arm64-branch-encoding.s
//     b L1  -> [A,A,A,0b000101AA] / bl L1 -> [A,A,A,0b100101AA]

// Internal: placeholder + deferred patch for one PC-relative field.
// `base` carries the fixed bits with the immediate field zeroed; `field_lsb`
// is the immediate field's least-significant bit position (0 for imm26,
// 5 for imm19/imm14).
fn arm64_emit_pcrel_word(base: u64, bits: u64, field_lsb: u64, name: string, what: string) {
    const field: u64 = here()
    emit.u32(base)
    defer {
        const target: u64 = label_addr(name)
        assert((field & 3) == 0, sym.join(what, ": branch site must be word aligned"));
        assert((target & 3) == 0, sym.join(what, ": branch target must be word aligned"));
        let imm: u64 = 0
        if target >= field {
            const delta: u64 = (target - field) / 4
            assert(delta < (1 << (bits - 1)), sym.join(what, ": forward branch out of range"));
            imm = delta
        } else {
            const delta: u64 = (field - target) / 4
            assert(delta <= (1 << (bits - 1)), sym.join(what, ": backward branch out of range"));
            imm = (-delta) & ((1 << bits) - 1)
        }
        store.u32(field, base | (imm << field_lsb))
    }
}

// B, unconditional branch. ARM ARM C6.2.88.
fn arm64_b(name: string) {
    arm64_emit_pcrel_word(0x14000000, 26, 0, name, "b");
}

// BL, branch with link. ARM ARM C6.2.85.
fn arm64_bl(name: string) {
    arm64_emit_pcrel_word(0x94000000, 26, 0, name, "bl");
}

// CBZ, compare and branch on zero. ARM ARM C6.2.55. Accepts ZR, not SP.
fn arm64_cbz(reg: u64, name: string) {
    assert(!arm64_reg_is_sp(reg), "cbz register cannot be SP");
    const sf: u64 = (reg >> 5) & 1
    arm64_emit_pcrel_word((sf << 31) | 0x34000000 | arm64_reg_number(reg), 19, 5, name, "cbz");
}

// CBNZ, compare and branch on nonzero. ARM ARM C6.2.54. Accepts ZR, not SP.
fn arm64_cbnz(reg: u64, name: string) {
    assert(!arm64_reg_is_sp(reg), "cbnz register cannot be SP");
    const sf: u64 = (reg >> 5) & 1
    arm64_emit_pcrel_word((sf << 31) | 0x35000000 | arm64_reg_number(reg), 19, 5, name, "cbnz");
}

// B.cond, conditional branch. ARM ARM C6.2.24.
fn arm64_b_cond(cond: u64, name: string) {
    assert(cond <= 13, "b.cond requires a real condition code (0..13)");
    arm64_emit_pcrel_word(0x54000000 | cond, 19, 5, name, "b.cond");
}

// TBZ, test bit and branch on zero. ARM ARM C6.2.364.
fn arm64_tbz(reg: u64, bit: u64, name: string) {
    arm64_emit_test_bit_branch("tbz", 0, reg, bit, name);
}

// TBNZ, test bit and branch on nonzero. ARM ARM C6.2.363.
fn arm64_tbnz(reg: u64, bit: u64, name: string) {
    arm64_emit_test_bit_branch("tbnz", 1, reg, bit, name);
}

// Internal: shared body of TBZ/TBNZ.
// Layout: b5(31) 011011(30-26) op(24) b40(23-19) imm14(18-5) Rt(4-0).
fn arm64_emit_test_bit_branch(what: string, op: u64, reg: u64, bit: u64, name: string) {
    assert(!arm64_reg_is_sp(reg), sym.join(what, " register cannot be SP"));
    assert(arm64_reg_is64(reg) || bit < 32, sym.join(what, " on a W register requires bit < 32"));
    assert(bit < 64, sym.join(what, " requires bit < 64"));
    const b5: u64 = (bit >> 5) & 1
    const b40: u64 = bit & 31
    const base: u64 = (b5 << 31) | 0x36000000 | (op << 24) | (b40 << 19) | arm64_reg_number(reg)
    arm64_emit_pcrel_word(base, 14, 5, name, what);
}

// BR, branch to register. ARM ARM C6.2.89. Rn must not be 31.
fn arm64_br(reg: u64) {
    assert(!arm64_reg_is_sp(reg), "br register cannot be SP");
    assert(arm64_reg_number(reg) != 31, "br register cannot be ZR");
    emit.u32(0xd61f0000 | (arm64_reg_number(reg) << 5));
}

// BLR, branch with link to register. ARM ARM C6.2.84. Rn must not be 31.
fn arm64_blr(reg: u64) {
    assert(!arm64_reg_is_sp(reg), "blr register cannot be SP");
    assert(arm64_reg_number(reg) != 31, "blr register cannot be ZR");
    emit.u32(0xd63f0000 | (arm64_reg_number(reg) << 5));
}
