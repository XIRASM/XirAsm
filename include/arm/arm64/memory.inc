// A64 loads, stores, and address computation (M4).
//
// Conventions shared by this file:
//   - the base register Rn is always 64-bit (X register or SP); encoding 31
//     reads SP, never ZR;
//   - the transfer register Rt accepts ZR, never SP;
//   - unsigned-immediate offsets are scaled by the element size;
//   - unscaled (LDUR/STUR) offsets are raw signed 9-bit values passed as
//     two's-complement u64 (-256..255).

// Internal: load/store (unsigned immediate, scaled).
// Layout: size(31-30) 111(29-27) V(26) 01(25-24) opc(23-22) imm12(21-10)
//         Rn(9-5) Rt(4-0).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldr x0, [x0]            -> [00 00 40 f9]
//   ldr x30, [x12, #32760]  -> [9e fd 7f f9]  (imm12 max 4095, scaled 8)
//   ldr w2, [sp]            -> [e2 03 40 b9]
fn arm64_emit_ldst_imm(size: u64, opc: u64, scale: u64, rt: u64, rn: u64, offset: u64) {
    arm64_check_no_sp(rt, "load/store");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "load/store base must be an X register or SP");
    assert(offset % scale == 0, sym.join("load/store offset must be a multiple of the element size (", to_string(scale), ")"));
    const imm12: u64 = offset / scale
    assert(imm12 <= 4095, "load/store offset out of range");
    emit.u32((size << 30) | (0x7 << 27) | (0x1 << 24) | (opc << 22)
        | (imm12 << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt));
}

// LDR (immediate, unsigned offset). ARM ARM C6.2.176. W/X by Rt.
fn arm64_ldr_imm(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        size = 3
        scale = 8
    }
    arm64_emit_ldst_imm(size, 1, scale, rt, rn, offset);
}

// STR (immediate, unsigned offset). ARM ARM C6.2.346.
fn arm64_str_imm(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        size = 3
        scale = 8
    }
    arm64_emit_ldst_imm(size, 0, scale, rt, rn, offset);
}

// LDRB/STRB: size 00, byte scale 1, Rt must be W.
fn arm64_ldrb_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrb requires a W register");
    arm64_emit_ldst_imm(0, 1, 1, rt, rn, offset);
}

fn arm64_strb_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strb requires a W register");
    arm64_emit_ldst_imm(0, 0, 1, rt, rn, offset);
}

// LDRH/STRH: size 01, halfword scale 2, Rt must be W.
fn arm64_ldrh_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrh requires a W register");
    arm64_emit_ldst_imm(1, 1, 2, rt, rn, offset);
}

fn arm64_strh_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strh requires a W register");
    arm64_emit_ldst_imm(1, 0, 2, rt, rn, offset);
}

// LDRSW: size 10 opc 10, sign-extends into an X register. ARM ARM C6.2.187.
fn arm64_ldrsw_imm(rt: u64, rn: u64, offset: u64) {
    assert(arm64_reg_is64(rt), "ldrsw requires an X register");
    arm64_emit_ldst_imm(2, 2, 4, rt, rn, offset);
}

// LDRSB (register width selects opc 10 for X / 11 for W).
fn arm64_ldrsb_imm(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm(0, opc, 1, rt, rn, offset);
}

// LDRSH (register width selects opc 10 for X / 11 for W).
fn arm64_ldrsh_imm(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm(1, opc, 2, rt, rn, offset);
}

// --- Load/store unscaled immediate (LDUR/STUR) -----------------------------------
// Layout: size(31-30) 111(29-27) V(26) 00(25-24) opc(23-22) imm9(20-12)
//         00(11-10) Rn(9-5) Rt(4-0). The 9-bit offset is raw bytes.
// Fixtures: basic-a64-instructions.s
//   ldur xzr, [x12, #255]  -> [9f f1 4f f8]
//   stur w16, [x0, #-256]  -> [10 00 10 b8]
//   ldursw x20, [x15, #-256] -> [f4 01 90 b8]
fn arm64_emit_ldur_imm(size: u64, opc: u64, rt: u64, rn: u64, offset: u64) {
    arm64_check_no_sp(rt, "load/store unscaled");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "load/store base must be an X register or SP");
    assert(offset < 0x100 || offset >= 0xffffffffffffff00,
        "load/store unscaled offset out of range -256..255");
    const imm9: u64 = offset & 0x1ff
    emit.u32((size << 30) | (0x7 << 27) | (opc << 22) | (imm9 << 12)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt));
}

// LDUR (W/X by Rt). ARM ARM C6.2.183.
fn arm64_ldur_imm(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldur_imm(size, 1, rt, rn, offset);
}

// STUR (W/X by Rt). ARM ARM C6.2.351.
fn arm64_stur_imm(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldur_imm(size, 0, rt, rn, offset);
}

// LDURB/STURB (W register).
fn arm64_ldurb_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldurb requires a W register");
    arm64_emit_ldur_imm(0, 1, rt, rn, offset);
}

fn arm64_sturb_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "sturb requires a W register");
    arm64_emit_ldur_imm(0, 0, rt, rn, offset);
}

// LDURH/STURH (W register).
fn arm64_ldurh_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldurh requires a W register");
    arm64_emit_ldur_imm(1, 1, rt, rn, offset);
}

fn arm64_sturh_imm(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "sturh requires a W register");
    arm64_emit_ldur_imm(1, 0, rt, rn, offset);
}

// LDURSB (W/X by Rt).
fn arm64_ldursb_imm(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldur_imm(0, opc, rt, rn, offset);
}

// LDURSH (W/X by Rt).
fn arm64_ldursh_imm(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldur_imm(1, opc, rt, rn, offset);
}

// LDURSW (X register).
fn arm64_ldursw_imm(rt: u64, rn: u64, offset: u64) {
    assert(arm64_reg_is64(rt), "ldursw requires an X register");
    arm64_emit_ldur_imm(2, 2, rt, rn, offset);
}

// --- Load/store register pair (signed offset) --------------------------------------
// Layout: opc(31-30) 101(29-27) V(26) 011(25-23) L(22) imm7(21-15) Rt2(14-10)
//         Rn(9-5) Rt(4-0). The imm7 is signed and scaled by the pair element
//         size (W 4, X 8).
// Fixtures: basic-a64-instructions.s
//   ldp x21, x29, [x2, #504] -> [55 f4 5f a9]
//   stp wzr, w9, [sp, #252]  -> [ff a7 1f 29]
//   ldp w2, wzr, [sp, #-256] -> [e2 7f 60 29]
fn arm64_emit_pair(opc: u64, is_load: bool, scale: u64, rt: u64, rt2: u64, rn: u64, offset: u64) {
    arm64_emit_pair_ex(opc, is_load, scale, false, rt, rt2, rn, offset)
}

// Internal: pair with a no-allocate switch (LDNP/STNP set 25-23 = 000
// instead of 011 per LLVM BaseLoadStorePairNoAlloc).
fn arm64_emit_pair_ex(opc: u64, is_load: bool, scale: u64, no_alloc: bool, rt: u64, rt2: u64, rn: u64, offset: u64) {
    arm64_check_no_sp(rt, "load/store pair");
    arm64_check_no_sp(rt2, "load/store pair");
    arm64_check_same_width(rt, rt2, "load/store pair");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "load/store pair base must be an X register or SP");
    // The offset arrives as a two's-complement u64 (negative for backwards
    // pairs); the imm7 is signed, scaled by the pair element size.
    assert(offset % scale == 0, sym.join("load/store pair offset must be a multiple of the element size (", to_string(scale), ")"));
    let imm7: u64 = 0
    if offset >= 0x8000000000000000 {
        const mag: u64 = (-offset) / scale
        assert(mag <= 64, "load/store pair offset out of range");
        imm7 = (-mag) & 0x7f
    } else {
        const mag: u64 = offset / scale
        assert(mag < 64, "load/store pair offset out of range");
        imm7 = mag
    }
    let l: u64 = 0
    if is_load {
        l = 1
    }
    let na: u64 = 2
    if no_alloc {
        na = 0
    }
    // 25-23: 011 = signed-offset pair, 000 = no-allocate pair.
    emit.u32((opc << 30) | (0x5 << 27) | (na << 23) | (l << 22) | ((imm7 & 0x7f) << 15)
        | (arm64_reg_number(rt2) << 10) | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDP (W/X pair by Rt). ARM ARM C6.2.166.
fn arm64_ldp(rt: u64, rt2: u64, rn: u64, offset: u64) {
    let opc: u64 = 0
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        opc = 2
        scale = 8
    }
    arm64_emit_pair(opc, true, scale, rt, rt2, rn, offset);
}

// STP (W/X pair by Rt). ARM ARM C6.2.338.
fn arm64_stp(rt: u64, rt2: u64, rn: u64, offset: u64) {
    let opc: u64 = 0
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        opc = 2
        scale = 8
    }
    arm64_emit_pair(opc, false, scale, rt, rt2, rn, offset);
}

// LDPSW: pair of sign-extended 32-bit loads into X registers.
// Fixture: basic-a64-instructions.s, ldpsw x2, wzr, [sp, #-256] -> [e2 7f 60 28].
fn arm64_ldpsw(rt: u64, rt2: u64, rn: u64, offset: u64) {
    assert(arm64_reg_is64(rt) && arm64_reg_is64(rt2), "ldpsw requires X registers");
    arm64_emit_pair(1, true, 4, rt, rt2, rn, offset);
}

// LDNP/STNP: non-temporal no-allocate pair (LLVM LoadPairNoAlloc /
// StorePairNoAlloc, 25-23 = 000). Same imm7 scaling as LDP/STP.
// clang: ldnp w0, w1, [x2] -> 0x28400440
//        ldnp x0, x1, [x2] -> 0xa8400440
fn arm64_ldnp(rt: u64, rt2: u64, rn: u64, offset: u64) {
    let opc: u64 = 0
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        opc = 2
        scale = 8
    }
    arm64_emit_pair_ex(opc, true, scale, true, rt, rt2, rn, offset)
}

fn arm64_stnp(rt: u64, rt2: u64, rn: u64, offset: u64) {
    let opc: u64 = 0
    let scale: u64 = 4
    if arm64_reg_is64(rt) {
        opc = 2
        scale = 8
    }
    arm64_emit_pair_ex(opc, false, scale, true, rt, rt2, rn, offset)
}

// --- PC-relative address computation -------------------------------------------------
// ADR: op(31)=0 immlo(30-29) 10000(28-24) immhi(23-5) Rd(4-0); ADRP: op(31)=1
// and the immediate counts 4 KiB pages. Both span +/-1 MiB (ADR) and +/-4 GiB
// (ADRP) from the instruction itself.
fn arm64_emit_adr(op: u64, rd: u64, name: string, what: string) {
    arm64_check_no_sp(rd, what);
    const field: u64 = here()
    emit.u32((op << 31) | (0x10 << 24) | arm64_reg_number(rd))
    defer {
        const target: u64 = label_addr(name)
        assert((field & 3) == 0, sym.join(what, ": site must be word aligned"));
        // The target needs no alignment: ADR is byte-granular and ADRP only
        // consumes each address's 4 KiB page base.
        let imm21: u64 = 0
        if target >= field {
            const delta: u64 = target - field
            assert(delta < 0x100000, sym.join(what, ": target out of range"));
            imm21 = delta
        } else {
            const delta: u64 = field - target
            assert(delta <= 0x100000, sym.join(what, ": target out of range"));
            imm21 = (-delta) & 0x1fffff
        }
        if op == 1 {
            // ADRP: whole pages; both addresses are page-base relative so the
            // 4 KiB division is exact. The delta is byte distance here.
            const ppc: u64 = field & 0xfffffffffffff000
            const ptg: u64 = target & 0xfffffffffffff000
            let pages: u64 = 0
            if ptg >= ppc {
                pages = (ptg - ppc) / 4096
                assert(pages < 0x100000, sym.join(what, ": target out of range"));
            } else {
                pages = (ppc - ptg) / 4096
                assert(pages <= 0x100000, sym.join(what, ": target out of range"));
                pages = 0x200000 - pages
            }
            imm21 = pages & 0x1fffff
        }
        store.u32(field, (op << 31) | (0x10 << 24) | ((imm21 & 3) << 29)
            | (((imm21 >> 2) & 0x7ffff) << 5) | arm64_reg_number(rd))
    }
}

// ADR: address of a label within +/-1 MiB. ARM ARM C6.2.28.
fn arm64_adr(rd: u64, name: string) {
    arm64_emit_adr(0, rd, name, "adr");
}

// ADRP: page address of a label within +/-4 GiB. ARM ARM C6.2.27.
fn arm64_adrp(rd: u64, name: string) {
    arm64_emit_adr(1, rd, name, "adrp");
}

// --- Prefetch (PRFM, immediate) -------------------------------------------------------
// Layout as load/store unsigned immediate with opc 10, size 11; the Rt field
// carries the 5-bit prefetch operation.
// Fixture: basic-a64-instructions.s, prfm pldl1strm, nowhere -> Rt bits 00001.
const arm64_prfm_pldl1keep: u64 = 0
const arm64_prfm_pldl1strm: u64 = 1
const arm64_prfm_pldl2keep: u64 = 2
const arm64_prfm_pldl2strm: u64 = 3
const arm64_prfm_pldl3keep: u64 = 4
const arm64_prfm_pldl3strm: u64 = 5
const arm64_prfm_plil1keep: u64 = 8
const arm64_prfm_plil2keep: u64 = 10
const arm64_prfm_plil3keep: u64 = 12
const arm64_prfm_pstl1keep: u64 = 16
const arm64_prfm_pstl1strm: u64 = 17

fn arm64_prfm_imm(rn: u64, prfop: u64, offset: u64) {
    assert(prfop <= 31, "prfm operation out of range");
    arm64_emit_ldst_imm(3, 2, 8, prfop, rn, offset);
}

// PRFM (register offset). ARM ARM C6.2.341; LLVM PrefetchRO (size 11, opc 10,
// the 5-bit prfop rides in the Rt field). The index follows the register-offset
// option rules (LSL/SXTX need an X index, UXTW/SXTW a W index).
// clang vectors: prfm pldl1keep, [x0, x1] -> 0xf8a16800
//                prfm pldl2strm, [x1, w2, sxtw] -> 0xf8a2c823
fn arm64_prfm_reg(rn: u64, prfop: u64, rm: u64, option: u64, shifted: bool) {
    assert(prfop <= 31, "prfm operation out of range");
    arm64_emit_ldst_reg(3, 2, prfop, rn, rm, option, shifted);
}

// --- Load/store register offset (M4.5) ---------------------------------------------
// Layout: size(31-30) 111(29-27) V(26) 00(25-24) opc(23-22) 1(21) Rm(20-16)
//         option(15-13) S(12) 10(11-10) Rn(9-5) Rt(4-0).
// option: 010=UXTW 011=LSL 110=SXTW 111=SXTX; S=1 shifts the index by the
// element size. LSL/SXTX require an X index; UXTW/SXTW require a W index.
// No SP anywhere; ZR allowed for Rm/Rt.
const arm64_ldst_opt_uxtw: u64 = 2
const arm64_ldst_opt_lsl: u64 = 3
const arm64_ldst_opt_sxtw: u64 = 6
const arm64_ldst_opt_sxtx: u64 = 7

fn arm64_emit_ldst_reg(size: u64, opc: u64, rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    arm64_check_no_sp(rt, "register offset");
    arm64_check_no_sp(rm, "register offset");
    assert(!arm64_reg_is_zr(rn), "register-offset base cannot be ZR (reads SP)");
    assert(option == arm64_ldst_opt_uxtw || option == arm64_ldst_opt_lsl
        || option == arm64_ldst_opt_sxtw || option == arm64_ldst_opt_sxtx,
        "register-offset option must be UXTW/LSL/SXTW/SXTX");
    if option == arm64_ldst_opt_lsl || option == arm64_ldst_opt_sxtx {
        assert(arm64_reg_is64(rm), "LSL/SXTX index requires an X register");
    } else {
        assert(!arm64_reg_is64(rm), "UXTW/SXTW index requires a W register");
    }
    const sf: u64 = (rt >> 5) & 1
    let s: u64 = 0
    if shifted {
        s = 1
    }
    emit.u32((size << 30) | (0x7 << 27) | (opc << 22) | (1 << 21)
        | (arm64_reg_number(rm) << 16) | (option << 13) | (s << 12) | (2 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt));
}

// LDR (register offset): [Xn, Xm] / [Xn, Xm, LSL #size].
// Fixtures: basic-a64-instructions.s, ldr x0, [x0] reg-form (byte-verified
// against clang --target=aarch64 in the M4.5 closeout).
fn arm64_ldr_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_reg(size, 1, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

// STR (register offset). ARM ARM C6.2.344.
fn arm64_str_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_reg(size, 0, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

fn arm64_ldrb_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    assert(!arm64_reg_is64(rt), "ldrb requires a W register");
    arm64_emit_ldst_reg(0, 1, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

fn arm64_strb_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    assert(!arm64_reg_is64(rt), "strb requires a W register");
    arm64_emit_ldst_reg(0, 0, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

fn arm64_ldrh_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    assert(!arm64_reg_is64(rt), "ldrh requires a W register");
    arm64_emit_ldst_reg(1, 1, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

fn arm64_strh_reg(rt: u64, rn: u64, rm: u64, shifted: bool) {
    assert(!arm64_reg_is64(rt), "strh requires a W register");
    arm64_emit_ldst_reg(1, 0, rt, rn, rm, arm64_ldst_opt_lsl, shifted);
}

// LDRSW with W index (SXTW/UXTW) or X index (LSL).
fn arm64_ldrsw_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    assert(arm64_reg_is64(rt), "ldrsw requires an X register");
    arm64_emit_ldst_reg(2, 2, rt, rn, rm, option, shifted);
}

// LDRSB: register width selects opc 10 (X) / 11 (W).
fn arm64_ldrsb_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_reg(0, opc, rt, rn, rm, option, shifted);
}

// LDRSH: register width selects opc 10 (X) / 11 (W).
fn arm64_ldrsh_reg(rt: u64, rn: u64, rm: u64, option: u64, shifted: bool) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_reg(1, opc, rt, rn, rm, option, shifted);
}

// --- Pre/post-index (writeback forms) ------------------------------------------------
// Layout: size(31-30) 111(29-27) V(26) 00(25-24) opc(23-22) 0(21) imm9(20-12)
//         form(11-10) Rn(9-5) Rt(4-0). form: 01=post-index, 11=pre-index.
// The base register is written back architecturally; Rn 31 reads SP, so ZR is
// not encodable here. The offset is a raw signed 9-bit byte value.
fn arm64_emit_ldst_imm9(opc: u64, size: u64, form: u64, rt: u64, rn: u64, offset: u64) {
    arm64_check_no_sp(rt, "pre/post-index");
    assert(!arm64_reg_is_zr(rn), "pre/post-index base cannot be ZR (reads SP)");
    assert(offset < 0x100 || offset >= 0xffffffffffffff00,
        "pre/post-index offset out of range -256..255");
    const imm9: u64 = offset & 0x1ff
    emit.u32((size << 30) | (0x7 << 27) | (opc << 22) | (imm9 << 12) | (form << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt));
}

fn arm64_ldr_post(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_imm9(1, size, 1, rt, rn, offset);
}

fn arm64_ldr_pre(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_imm9(1, size, 3, rt, rn, offset);
}

fn arm64_str_post(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_imm9(0, size, 1, rt, rn, offset);
}

fn arm64_str_pre(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_imm9(0, size, 3, rt, rn, offset);
}

fn arm64_ldrb_post(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrb requires a W register");
    arm64_emit_ldst_imm9(1, 0, 1, rt, rn, offset);
}

fn arm64_ldrb_pre(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrb requires a W register");
    arm64_emit_ldst_imm9(1, 0, 3, rt, rn, offset);
}

fn arm64_strb_post(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strb requires a W register");
    arm64_emit_ldst_imm9(0, 0, 1, rt, rn, offset);
}

fn arm64_strb_pre(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strb requires a W register");
    arm64_emit_ldst_imm9(0, 0, 3, rt, rn, offset);
}

fn arm64_ldrh_post(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrh requires a W register");
    arm64_emit_ldst_imm9(1, 1, 1, rt, rn, offset);
}

fn arm64_ldrh_pre(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldrh requires a W register");
    arm64_emit_ldst_imm9(1, 1, 3, rt, rn, offset);
}

fn arm64_strh_post(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strh requires a W register");
    arm64_emit_ldst_imm9(0, 1, 1, rt, rn, offset);
}

fn arm64_strh_pre(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "strh requires a W register");
    arm64_emit_ldst_imm9(0, 1, 3, rt, rn, offset);
}

fn arm64_ldrsw_post(rt: u64, rn: u64, offset: u64) {
    assert(arm64_reg_is64(rt), "ldrsw requires an X register");
    arm64_emit_ldst_imm9(2, 2, 1, rt, rn, offset);
}

fn arm64_ldrsw_pre(rt: u64, rn: u64, offset: u64) {
    assert(arm64_reg_is64(rt), "ldrsw requires an X register");
    arm64_emit_ldst_imm9(2, 2, 3, rt, rn, offset);
}

fn arm64_ldrsb_post(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm9(opc, 0, 1, rt, rn, offset);
}

fn arm64_ldrsb_pre(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm9(opc, 0, 3, rt, rn, offset);
}

fn arm64_ldrsh_post(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm9(opc, 1, 1, rt, rn, offset);
}

fn arm64_ldrsh_pre(rt: u64, rn: u64, offset: u64) {
    let opc: u64 = 2
    if !arm64_reg_is64(rt) {
        opc = 3
    }
    arm64_emit_ldst_imm9(opc, 1, 3, rt, rn, offset);
}

// --- PC-relative literal loads ---------------------------------------------------------
// Layout: opc(31-30) 011(29-27) V(26) 00(25-24) imm19(23-5) Rt(4-0). The
// immediate is a signed word offset (±1 MiB) from the load instruction.
// opc: 00=LDR W 01=LDR X 10=LDRSW 11=PRFM.
fn arm64_emit_ldr_lit(opc: u64, rt: u64, name: string, what: string) {
    arm64_check_no_sp(rt, what);
    const field: u64 = here()
    emit.u32((opc << 30) | (0x3 << 27) | arm64_reg_number(rt))
    defer {
        const target: u64 = label_addr(name)
        assert((target & 3) == 0, sym.join(what, ": literal must be word aligned"));
        assert((field & 3) == 0, sym.join(what, ": site must be word aligned"));
        let imm19: u64 = 0
        if target >= field {
            const delta: u64 = target - field
            assert(delta < 0x100000, sym.join(what, ": literal out of range"));
            imm19 = delta / 4
        } else {
            const delta: u64 = field - target
            assert(delta <= 0x100000, sym.join(what, ": literal out of range"));
            imm19 = (-delta) / 4 & 0x7ffff
        }
        store.u32(field, (opc << 30) | (0x3 << 27) | ((imm19 & 0x7ffff) << 5)
            | arm64_reg_number(rt))
    }
}

// LDR (literal, X). ARM ARM C6.2.175. The W form is arm64_ldrw_lit.
fn arm64_ldr_lit(rt: u64, name: string) {
    assert(arm64_reg_is64(rt), "ldr literal requires an X register");
    arm64_emit_ldr_lit(1, rt, name, "ldr literal");
}

// LDR (literal, W).
fn arm64_ldrw_lit(rt: u64, name: string) {
    assert(!arm64_reg_is64(rt), "ldr literal W form requires a W register");
    arm64_emit_ldr_lit(0, rt, name, "ldr literal");
}

// LDRSW (literal). ARM ARM C6.2.188.
fn arm64_ldrsw_lit(rt: u64, name: string) {
    assert(arm64_reg_is64(rt), "ldrsw literal requires an X register");
    arm64_emit_ldr_lit(2, rt, name, "ldrsw literal");
}
