// A64 register constants, identity checks, and the register name table.
//
// Register constants pack three facts into one integer:
//   bits 4..0  register number (0..31)
//   bit  5     width (0 = 32-bit W form, 1 = 64-bit X form)
//   bit  6     stack-pointer identity
// Architectural encoding 31 means ZR or SP depending on the instruction, so
// both identities exist as explicit constants:
//   arm64_w0..arm64_w30  32-bit general registers (0..30)
//   arm64_wzr            32-bit zero register        (31)
//   arm64_wsp            32-bit stack pointer        (0x40 | 31)
//   arm64_x0..arm64_x30  64-bit general registers    (0x20 | 0..30)
//   arm64_xzr            64-bit zero register        (0x20 | 31)
//   arm64_sp             64-bit stack pointer        (0x40 | 0x20 | 31)

const arm64_w0: u64 = 0
const arm64_w1: u64 = 1
const arm64_w2: u64 = 2
const arm64_w3: u64 = 3
const arm64_w4: u64 = 4
const arm64_w5: u64 = 5
const arm64_w6: u64 = 6
const arm64_w7: u64 = 7
const arm64_w8: u64 = 8
const arm64_w9: u64 = 9
const arm64_w10: u64 = 10
const arm64_w11: u64 = 11
const arm64_w12: u64 = 12
const arm64_w13: u64 = 13
const arm64_w14: u64 = 14
const arm64_w15: u64 = 15
const arm64_w16: u64 = 16
const arm64_w17: u64 = 17
const arm64_w18: u64 = 18
const arm64_w19: u64 = 19
const arm64_w20: u64 = 20
const arm64_w21: u64 = 21
const arm64_w22: u64 = 22
const arm64_w23: u64 = 23
const arm64_w24: u64 = 24
const arm64_w25: u64 = 25
const arm64_w26: u64 = 26
const arm64_w27: u64 = 27
const arm64_w28: u64 = 28
const arm64_w29: u64 = 29
const arm64_w30: u64 = 30
const arm64_wzr: u64 = 31
const arm64_wsp: u64 = 0x5f

const arm64_x0: u64 = 0x20
const arm64_x1: u64 = 0x21
const arm64_x2: u64 = 0x22
const arm64_x3: u64 = 0x23
const arm64_x4: u64 = 0x24
const arm64_x5: u64 = 0x25
const arm64_x6: u64 = 0x26
const arm64_x7: u64 = 0x27
const arm64_x8: u64 = 0x28
const arm64_x9: u64 = 0x29
const arm64_x10: u64 = 0x2a
const arm64_x11: u64 = 0x2b
const arm64_x12: u64 = 0x2c
const arm64_x13: u64 = 0x2d
const arm64_x14: u64 = 0x2e
const arm64_x15: u64 = 0x2f
const arm64_x16: u64 = 0x30
const arm64_x17: u64 = 0x31
const arm64_x18: u64 = 0x32
const arm64_x19: u64 = 0x33
const arm64_x20: u64 = 0x34
const arm64_x21: u64 = 0x35
const arm64_x22: u64 = 0x36
const arm64_x23: u64 = 0x37
const arm64_x24: u64 = 0x38
const arm64_x25: u64 = 0x39
const arm64_x26: u64 = 0x3a
const arm64_x27: u64 = 0x3b
const arm64_x28: u64 = 0x3c
const arm64_x29: u64 = 0x3d
const arm64_x30: u64 = 0x3e
const arm64_xzr: u64 = 0x3f
const arm64_sp: u64 = 0x7f

fn arm64_reg_number(reg: u64) -> u64 {
    return reg & 31;
}

fn arm64_reg_is64(reg: u64) -> bool {
    return (reg & 32) != 0;
}

fn arm64_reg_is_sp(reg: u64) -> bool {
    return (reg & 64) != 0;
}

fn arm64_reg_is_zr(reg: u64) -> bool {
    return !arm64_reg_is_sp(reg) && arm64_reg_number(reg) == 31;
}

fn arm64_check_no_sp(reg: u64, what: string) {
    assert(!arm64_reg_is_sp(reg), sym.join(what, ": register cannot be SP"));
}

fn arm64_check_same_width(a: u64, b: u64, what: string) {
    assert(((a >> 5) & 1) == ((b >> 5) & 1), sym.join(what, ": mixed W/X registers"));
}

// In add/subtract, encoding 31 reads SP on Rn always; Rd is SP for ADD/SUB,
// ZR for ADDS/SUBS (CMP/CMN) (ARM ARM C6.2.4).
fn arm64_check_addsub_rd(reg: u64, setting: bool, what: string) {
    if setting {
        assert(!arm64_reg_is_sp(reg), sym.join(what, ": destination cannot be SP"));
    } else {
        assert(!arm64_reg_is_zr(reg), sym.join(what, ": destination cannot be ZR (writes SP)"));
    }
}

fn arm64_check_addsub_rn(reg: u64, what: string) {
    assert(!arm64_reg_is_zr(reg), sym.join(what, ": Rn cannot be ZR (reads SP)"));
}

// Register name table for the arm64_asm text adapter. Built once at import;
// sym.join renders the loop index as decimal text ("x0".."x30", "w0".."w30").
let arm64_reg_table: map = map.new()
for arm64_reg_i in range(0, 31) {
    map.set_mut(arm64_reg_table, sym.join("x", arm64_reg_i), 0x20 + arm64_reg_i);
    map.set_mut(arm64_reg_table, sym.join("w", arm64_reg_i), arm64_reg_i);
}
map.set_mut(arm64_reg_table, "xzr", arm64_xzr);
map.set_mut(arm64_reg_table, "wzr", arm64_wzr);
map.set_mut(arm64_reg_table, "sp", arm64_sp);
map.set_mut(arm64_reg_table, "wsp", arm64_wsp);

fn arm64_parse_reg(name: string) -> u64 {
    assert(map.has(arm64_reg_table, name), sym.join("arm64_asm: unknown register ", name));
    return map.get(arm64_reg_table, name);
}

// --- FP/SIMD vector registers (M5a) -------------------------------------------
// V0-V31 share the 5-bit register number with the general registers but form
// their own register class (ARM ARM B1.3.1). Bit 7 tags a V register so the
// FP emitters can route checks differently from GPRs; the scalar S/D forms
// address the low 32/64 bits of the V register.

const arm64_v0: u64 = 0x80
const arm64_v1: u64 = 0x81
const arm64_v2: u64 = 0x82
const arm64_v3: u64 = 0x83
const arm64_v4: u64 = 0x84
const arm64_v5: u64 = 0x85
const arm64_v6: u64 = 0x86
const arm64_v7: u64 = 0x87
const arm64_v8: u64 = 0x88
const arm64_v9: u64 = 0x89
const arm64_v10: u64 = 0x8a
const arm64_v11: u64 = 0x8b
const arm64_v12: u64 = 0x8c
const arm64_v13: u64 = 0x8d
const arm64_v14: u64 = 0x8e
const arm64_v15: u64 = 0x8f
const arm64_v16: u64 = 0x90
const arm64_v17: u64 = 0x91
const arm64_v18: u64 = 0x92
const arm64_v19: u64 = 0x93
const arm64_v20: u64 = 0x94
const arm64_v21: u64 = 0x95
const arm64_v22: u64 = 0x96
const arm64_v23: u64 = 0x97
const arm64_v24: u64 = 0x98
const arm64_v25: u64 = 0x99
const arm64_v26: u64 = 0x9a
const arm64_v27: u64 = 0x9b
const arm64_v28: u64 = 0x9c
const arm64_v29: u64 = 0x9d
const arm64_v30: u64 = 0x9e
const arm64_v31: u64 = 0x9f

fn arm64_is_v(reg: u64) -> u64 {
    return (reg >> 7) & 1;
}
