// A64 carry operations and conditional compare/select families (M3).
//
// Part 1 pins procedural encodings against LLVM MC fixtures from
// llvm/test/MC/AArch64/basic-a64-instructions.s. Part 2 proves the arm64_asm
// text adapter dispatches the new families identically to the direct emitter
// calls (sugar output must equal direct output word for word).
import("arm/arm64-macros.inc");

insn_adc_w:
arm64_adc(arm64_w29, arm64_w27, arm64_w25)

insn_adcs_x:
arm64_adcs(arm64_x0, arm64_x1, arm64_x2)

insn_sbc_w:
arm64_sbc(arm64_w0, arm64_w1, arm64_w2)

insn_sbcs_x:
arm64_sbcs(arm64_x0, arm64_x1, arm64_x2)

insn_ngc_w:
arm64_ngc(arm64_w9, arm64_w10)

insn_ngcs_x:
arm64_ngcs(arm64_x9, arm64_x10)

insn_ccmp_imm_w:
arm64_ccmp_imm(arm64_w1, 31, 0, arm64_cond_eq)

insn_ccmp_reg_w:
arm64_ccmp_reg(arm64_w1, arm64_wzr, 0, arm64_cond_eq)

insn_ccmp_imm_x:
arm64_ccmp_imm(arm64_x9, 31, 0, arm64_cond_le)

insn_ccmp_reg_zr:
arm64_ccmp_reg(arm64_wzr, arm64_w15, 13, arm64_cond_hs)

insn_ccmn_imm_x:
arm64_ccmn_imm(arm64_x0, 1, 2, arm64_cond_eq)

insn_ccmn_reg_x:
arm64_ccmn_reg(arm64_x3, arm64_x4, 5, arm64_cond_ne)

insn_csel_w:
arm64_csel(arm64_w1, arm64_w0, arm64_w19, arm64_cond_ne)

insn_csel_x:
arm64_csel(arm64_x19, arm64_x23, arm64_x29, arm64_cond_lt)

insn_csinc_w:
arm64_csinc(arm64_w1, arm64_w0, arm64_w19, arm64_cond_ne)

insn_csinv_w:
arm64_csinv(arm64_w1, arm64_w0, arm64_w19, arm64_cond_ne)

insn_csneg_w:
arm64_csneg(arm64_w0, arm64_w1, arm64_w2, arm64_cond_mi)

insn_cset_w:
arm64_cset(arm64_w3, arm64_cond_eq)

insn_csetm_x:
arm64_csetm(arm64_x30, arm64_cond_ge)

insn_cinc_w:
arm64_cinc(arm64_w3, arm64_w5, arm64_cond_gt)

insn_cinv_w:
arm64_cinv(arm64_w0, arm64_w1, arm64_cond_ne)

insn_tst_reg_w:
arm64_tst_reg(arm64_w3, arm64_w7, 0, 31)

insn_tst_reg_x:
arm64_tst_reg(arm64_x2, arm64_x20, 2, 0)

insn_tst_imm_x:
arm64_tst_imm(arm64_x0, 0xff)

// --- Sugar dispatch for the M3 families -------------------------------------
dir_adc:
arm64_adc(arm64_w29, arm64_w27, arm64_w25)
sug_adc:
adc w29, w27, w25

dir_ngc:
arm64_ngc(arm64_x9, arm64_x10)
sug_ngc:
ngc x9, x10

dir_cset:
arm64_cset(arm64_x0, arm64_cond_lt)
sug_cset:
cset x0, lt

dir_csel:
arm64_csel(arm64_x1, arm64_x2, arm64_x3, arm64_cond_eq)
sug_csel:
csel x1, x2, x3, eq

dir_ccmp_imm:
arm64_ccmp_imm(arm64_x4, 12, 3, arm64_cond_ne)
sug_ccmp_imm:
ccmp x4, 12, 3, ne

dir_ccmp_reg:
arm64_ccmp_reg(arm64_x4, arm64_x5, 3, arm64_cond_ne)
sug_ccmp_reg:
ccmp x4, x5, 3, ne

dir_tst:
arm64_tst_reg(arm64_x6, arm64_x7, 0, 0)
sug_tst:
tst x6, x7

defer {
    assert(load.u32(insn_adc_w) == 0x1a19037d, "adc w29, w27, w25");
    assert(load.u32(insn_adcs_x) == 0xba020020, "adcs x0, x1, x2");
    assert(load.u32(insn_sbc_w) == 0x5a020020, "sbc w0, w1, w2");
    assert(load.u32(insn_sbcs_x) == 0xfa020020, "sbcs x0, x1, x2");
    assert(load.u32(insn_ngc_w) == 0x5a0a03e9, "ngc w9, w10");
    assert(load.u32(insn_ngcs_x) == 0xfa0a03e9, "ngcs x9, x10");
    assert(load.u32(insn_ccmp_imm_w) == 0x7a5f0820, "ccmp w1, #31, #0, eq");
    assert(load.u32(insn_ccmp_reg_w) == 0x7a5f0020, "ccmp w1, wzr, #0, eq");
    assert(load.u32(insn_ccmp_imm_x) == 0xfa5fd920, "ccmp x9, #31, #0, le");
    assert(load.u32(insn_ccmp_reg_zr) == 0x7a4f23ed, "ccmp wzr, w15, #13, hs");
    assert(load.u32(insn_ccmn_imm_x) == 0xba410802, "ccmn x0, #1, #2, eq");
    assert(load.u32(insn_ccmn_reg_x) == 0xba441065, "ccmn x3, x4, #5, ne");
    assert(load.u32(insn_csel_w) == 0x1a931001, "csel w1, w0, w19, ne");
    assert(load.u32(insn_csel_x) == 0x9a9db2f3, "csel x19, x23, x29, lt");
    assert(load.u32(insn_csinc_w) == 0x1a931401, "csinc w1, w0, w19, ne");
    assert(load.u32(insn_csinv_w) == 0x5a931001, "csinv w1, w0, w19, ne");
    assert(load.u32(insn_csneg_w) == 0x5a824420, "csneg w0, w1, w2, mi");
    assert(load.u32(insn_cset_w) == 0x1a9f17e3, "cset w3, eq");
    assert(load.u32(insn_csetm_x) == 0xda9fb3fe, "csetm x30, ge");
    assert(load.u32(insn_cinc_w) == 0x1a85d4a3, "cinc w3, w5, gt");
    assert(load.u32(insn_cinv_w) == 0x5a810020, "cinv w0, w1, ne");
    assert(load.u32(insn_tst_reg_w) == 0x6a077c7f, "tst w3, w7, lsl #31");
    assert(load.u32(insn_tst_reg_x) == 0xea94005f, "tst x2, x20, asr #0");
    assert(load.u32(insn_tst_imm_x) == 0xf2401c1f, "tst x0, 0xff");

    assert(load.u32(sug_adc) == load.u32(dir_adc), "sugar adc == direct");
    assert(load.u32(sug_ngc) == load.u32(dir_ngc), "sugar ngc == direct");
    assert(load.u32(sug_cset) == load.u32(dir_cset), "sugar cset == direct");
    assert(load.u32(sug_csel) == load.u32(dir_csel), "sugar csel == direct");
    assert(load.u32(sug_ccmp_imm) == load.u32(dir_ccmp_imm), "sugar ccmp imm == direct");
    assert(load.u32(sug_ccmp_reg) == load.u32(dir_ccmp_reg), "sugar ccmp reg == direct");
    assert(load.u32(sug_tst) == load.u32(dir_tst), "sugar tst == direct");
}
