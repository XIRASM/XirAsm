// A64 move-wide immediate group (MOVZ/MOVK/MOVN) and the MOV register alias.

// Internal: shared body of the move-wide group.
// Layout: sf(31) opc(30-29) 100101(28-23) hw(22-21) imm16(20-5) Rd(4-0).
// opc: MOVN=00 MOVZ=10 MOVK=11. Rd 31 is ZR, never SP.
fn arm64_emit_move_wide(opc: u64, reg: u64, imm16: u64, shift: u64) {
    assert(!arm64_reg_is_sp(reg), "move-wide destination cannot be SP");
    assert(shift == 0 || shift == 16 || shift == 32 || shift == 48,
        "move-wide shift must be 0, 16, 32, or 48");
    const imm: u64 = arm64_fit(imm16, 16, "move-wide imm16")
    const sf: u64 = (reg >> 5) & 1
    const base: u64 = (sf << 31) | (opc << 29) | (0x25 << 23)
    const fields: u64 = ((shift / 16) << 21) | (imm << 5) | arm64_reg_number(reg)
    emit.u32(base | fields);
}

// MOVZ writes `imm16 << shift` and zeroes the rest. ARM ARM C6.2.193.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   movz w2, #0, lsl #16      -> [02 00 a0 52]
//   movk xzr, #4321, lsl #48  -> [3f 1c e2 f2]
//   movk x1, #1, lsl #16      -> [21 00 a0 f2]
fn arm64_movz(reg: u64, imm16: u64, shift: u64) {
    arm64_emit_move_wide(2, reg, imm16, shift);
}

// MOVK writes `imm16 << shift` and keeps the other bits. ARM ARM C6.2.190.
fn arm64_movk(reg: u64, imm16: u64, shift: u64) {
    arm64_emit_move_wide(3, reg, imm16, shift);
}

// MOVN writes the bitwise inverse of `imm16 << shift`. ARM ARM C6.2.191.
fn arm64_movn(reg: u64, imm16: u64, shift: u64) {
    arm64_emit_move_wide(0, reg, imm16, shift);
}

// MOV (register): alias of ORR Rd, ZR, Rm (ARM ARM C6.2.178). No SP.
// For a move that writes SP use arm64_add_imm(arm64_sp, rm, 0, 0).
// The zero register is computed arithmetically (wzr = 31, xzr = 31 + 32):
// branchless on purpose — see the frontend notes in the planning log.
fn arm64_mov_reg(rd: u64, rm: u64) {
    arm64_check_same_width(rd, rm, "mov register");
    arm64_orr_reg(rd, arm64_wzr + (rd & 32), rm, 0, 0);
}

// Internal: value of the 16-bit half `idx` (0..3) of a 64-bit constant.
fn arm64_mov_half(v: u64, idx: u64) -> u64 {
    return (v >> (idx * 16)) & 0xffff;
}

// Internal: number of nonzero 16-bit halves.
fn arm64_mov_nonzero_halves(v: u64) -> u64 {
    let c: u64 = 0
    let i: u64 = 0
    while i < 4 {
        if arm64_mov_half(v, i) != 0 {
            c = c + 1
        }
        i = i + 1
    }
    return c;
}

// Internal: number of 16-bit halves that differ from 0xffff.
fn arm64_mov_ones_mismatch_halves(v: u64) -> u64 {
    let c: u64 = 0
    let i: u64 = 0
    while i < 4 {
        if arm64_mov_half(v, i) != 0xffff {
            c = c + 1
        }
        i = i + 1
    }
    return c;
}

// Internal: shift (0/16/32/48) of the lowest nonzero half.
fn arm64_mov_lowest_nonzero_shift(v: u64) -> u64 {
    let i: u64 = 0
    while i < 4 {
        if arm64_mov_half(v, i) != 0 {
            return i * 16;
        }
        i = i + 1
    }
    return 0;
}

// Internal: shift of the lowest half that differs from 0xffff.
fn arm64_mov_ones_mismatch_shift(v: u64) -> u64 {
    let i: u64 = 0
    while i < 4 {
        if arm64_mov_half(v, i) != 0xffff {
            return i * 16;
        }
        i = i + 1
    }
    return 0;
}

// MOV (immediate): synthesizes MOVZ/MOVN (+MOVK) for a 64-bit (X) or 32-bit
// (W) constant. Priority: single MOVZ (one nonzero half), single MOVN (one
// half differs from all-ones), otherwise MOVZ of the lowest nonzero half plus
// MOVK for every other nonzero half. Correct in all cases; the emitted
// sequence is short but not always the architecturally minimal one.
fn arm64_mov_imm(rd: u64, value: u64) {
    let v: u64 = value
    if !arm64_reg_is64(rd) {
        assert(value <= 0xffffffff, "mov immediate for a W register must fit 32 bits");
        v = value & 0xffffffff
    }
    if v == 0 {
        arm64_movz(rd, 0, 0);
    } else if v == 0xffffffffffffffff {
        arm64_movn(rd, 0, 0);
    } else if arm64_mov_nonzero_halves(v) == 1 {
        const s: u64 = arm64_mov_lowest_nonzero_shift(v)
        arm64_movz(rd, arm64_mov_half(v, s / 16), s);
    } else if arm64_mov_ones_mismatch_halves(v) == 1 {
        const s: u64 = arm64_mov_ones_mismatch_shift(v)
        arm64_movn(rd, ((~v) >> s) & 0xffff, s);
    } else {
        const s: u64 = arm64_mov_lowest_nonzero_shift(v)
        arm64_movz(rd, arm64_mov_half(v, s / 16), s);
        let i: u64 = s / 16
        while i < 4 {
            const h: u64 = arm64_mov_half(v, i)
            if h != 0 && i * 16 != s {
                arm64_movk(rd, h, i * 16);
            }
            i = i + 1
        }
    }
}
