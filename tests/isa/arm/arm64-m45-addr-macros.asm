// A64 addressing completion (M4.5): register offset, pre/post-index, and
// PC-relative literal loads.
//
// Part 1 pins the encodings byte-for-byte against LLVM's integrated
// assembler (clang --target=aarch64 assembled the identical GNU-syntax
// sequence; the bytes matched 7/7 in the closeout harness and are pinned
// here). Part 2 proves the arm64_asm text adapter dispatches the new forms
// identically to the direct emitters.
import("arm/arm64-macros.inc")

// Decode a literal-load word's imm19 (bits 23-5, word-scaled, signed) and
// resolve the target address: site + imm19 * 4.
fn resolve_lit(word: u64, site: u64) -> u64 {
    const imm19: u64 = (word >> 5) & 0x7ffff
    if (imm19 & 0x40000) == 0 {
        return site + imm19 * 4;
    }
    return site - (0x80000 - imm19) * 4;
}

insn_ldr_reg:
arm64_ldr_reg(arm64_x0, arm64_x1, arm64_x2, false)

insn_ldr_reg_lsl:
arm64_ldr_reg(arm64_x0, arm64_x1, arm64_x2, true)

insn_ldrsw_reg:
arm64_ldrsw_reg(arm64_x0, arm64_x1, arm64_w2, arm64_ldst_opt_sxtw, false)

insn_ldr_post:
arm64_ldr_post(arm64_x19, arm64_x1, 8)

insn_ldr_pre:
arm64_ldr_pre(arm64_x0, arm64_x1, -8)

insn_ldrb_post:
arm64_ldrb_post(arm64_w0, arm64_x1, 1)

insn_ldr_lit:
arm64_ldr_lit(arm64_x0, "lit")
lit:
emit.u8(1)
align(4)

// --- Sugar dispatch for the M4.5 forms ----------------------------------------
dir_ldr_reg:
arm64_ldr_reg(arm64_x0, arm64_x1, arm64_x2, false)
sug_ldr_reg:
ldr x0, [x1, x2]

dir_ldr_post:
arm64_ldr_post(arm64_x19, arm64_x1, 8)
sug_ldr_post:
ldr x19, [x1], 8

dir_ldr_pre:
arm64_ldr_pre(arm64_x0, arm64_x1, -8)
sug_ldr_pre:
ldr x0, [x1, -8]!

dir_ldur_neg:
arm64_ldur_imm(arm64_x0, arm64_x1, -8)
sug_ldur_neg:
ldur x0, [x1, -8]

dir_ldr_lit:
arm64_ldr_lit(arm64_x0, "lit")
sug_ldr_lit:
ldr x0, lit

// M4.5 review fixes: bare X index on a sign-extending register-offset load is
// LSL #0 (clang: ldrsw x0, [x1, x2] -> 0xb8a26820); a bare W index is
// rejected by LLVM ("expected 'uxtw' or 'sxtw' ...") and by our sugar.
dir_ldrsw_lsl:
arm64_ldrsw_reg(arm64_x0, arm64_x1, arm64_x2, arm64_ldst_opt_lsl, false)
sug_ldrsw_lsl:
ldrsw x0, [x1, x2]

// ADR targets are byte-granular (clang: adr x9, tgt+1 encodes the odd
// address; only the instruction site must be word aligned).
adr_unaligned_site:
arm64_adr(arm64_x9, "adr_odd")
emit.u32(0)
emit.u8(7)
adr_odd:

// Instruction stream resumes word-aligned; the odd byte above is data.
align(4)

// Literal sugar dispatches by target width: opc=01 (X) via arm64_ldr_lit,
// opc=00 (W) via arm64_ldrw_lit. clang: ldr w0, lit_near at +4 -> 0x18000020.
ldrw_lit_fwd:
arm64_ldrw_lit(arm64_w0, "lit_near")
lit_near:
arm64_nop()
dir_ldrw_lit:
arm64_ldrw_lit(arm64_w0, "lit")
sug_ldrw_lit:
ldr w0, lit

// PRFM register-offset (M4.5 deferred): size 11 opc 10, prfop in the Rt slot.
// clang: prfm pldl1keep, [x0, x1] -> 0xf8a16800
//        prfm pldl2strm, [x1, w2, sxtw] -> 0xf8a2c823
insn_prfm_reg:
arm64_prfm_reg(arm64_x0, arm64_prfm_pldl1keep, arm64_x1, arm64_ldst_opt_lsl, false)
insn_prfm_reg_sxtw:
arm64_prfm_reg(arm64_x1, arm64_prfm_pldl2strm, arm64_w2, arm64_ldst_opt_sxtw, false)

defer {
    assert(load.u32(insn_ldr_reg) == 0xf8626820, "ldr x0, [x1, x2]");
    assert(load.u32(insn_ldr_reg_lsl) == 0xf8627820, "ldr x0, [x1, x2, lsl #3]");
    assert(load.u32(insn_ldrsw_reg) == 0xb8a2c820, "ldrsw x0, [x1, w2, sxtw]");
    assert(load.u32(insn_ldr_post) == 0xf8408433, "ldr x19, [x1], #8");
    assert(load.u32(insn_ldr_pre) == 0xf85f8c20, "ldr x0, [x1, #-8]!");
    assert(load.u32(insn_ldrb_post) == 0x38401420, "ldrb w0, [x1], #1");
    assert(load.u32(insn_ldr_lit) == 0x58000020, "ldr x0, lit (+4 words)");

    assert(load.u32(sug_ldr_reg) == load.u32(dir_ldr_reg), "sugar ldr reg == direct");
    assert(load.u32(sug_ldr_post) == load.u32(dir_ldr_post), "sugar ldr post == direct");
    assert(load.u32(sug_ldr_pre) == load.u32(dir_ldr_pre), "sugar ldr pre == direct");
    assert(load.u32(sug_ldur_neg) == load.u32(dir_ldur_neg), "sugar ldur == direct");
    assert(load.u32(dir_ldrsw_lsl) == 0xb8a26820, "ldrsw x0, [x1, x2] (LSL #0)");
    assert(load.u32(sug_ldrsw_lsl) == load.u32(dir_ldrsw_lsl), "sugar ldrsw bare X == direct");
    // ADR decode: target = site + immhi:immlo (immlo bits 30-29, immhi 23-5).
    const adr_w: u64 = load.u32(adr_unaligned_site)
    const adr_imm: u64 = (((adr_w >> 5) & 0x7ffff) << 2) | ((adr_w >> 29) & 3)
    assert((adr_unaligned_site + adr_imm) == adr_odd, "adr reaches byte-granular target");
    assert(load.u32(ldrw_lit_fwd) == 0x18000020, "ldr w0, lit (+4 words, opc=00)");
    // Different sites encode different imm19 for the same target (pitfall 6):
    // compare decoded targets, not words. Both resolve to lit (28).
    assert(resolve_lit(load.u32(dir_ldrw_lit), dir_ldrw_lit) == lit, "direct ldr w literal -> lit");
    assert(resolve_lit(load.u32(sug_ldrw_lit), sug_ldrw_lit) == lit, "sugar ldr w literal -> lit");
    assert(load.u32(insn_prfm_reg) == 0xf8a16800, "prfm pldl1keep, [x0, x1]");
    assert(load.u32(insn_prfm_reg_sxtw) == 0xf8a2c823, "prfm pldl2strm, [x1, w2, sxtw]");
    // Different sites encode different words for the same target, so compare
    // decoded targets rather than words (FI-2: the load must observe the
    // finalized image; the frontend now forwards output_image into value
    // functions called from defers).
    const dir_t: u64 = resolve_lit(load.u32(dir_ldr_lit), dir_ldr_lit)
    const sug_t: u64 = resolve_lit(load.u32(sug_ldr_lit), sug_ldr_lit)
    assert(dir_t == lit, "direct literal resolves to lit");
    assert(sug_t == lit, "sugar literal resolves to lit");
}
