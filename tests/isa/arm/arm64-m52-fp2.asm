// M5a second half: FCSEL/FCCMP(E), FMOV (immediate), FCVT, SCVTF/UCVTF,
// FCVTZS/FCVTZU, FRINT, and the FP unscaled/register-offset addressing forms.
//
// Encodings follow the LLVM TableGen classes cited per emitter in
// include/arm/arm64/fp.inc. Every pinned word was extracted mechanically
// from clang --target=aarch64-linux-gnu -march=armv8.4-a object bytes by
// the mkwords.sh pipeline; none are hand-computed. The FMOV immediate
// calls pass the raw imm8 field value extracted from the clang words
// (bits 20-13: 112 = #1.0, 128 = #-2.0).
import("arm/arm64.inc")

insn_fcsel_s:
arm64_fcsel_s(arm64_v9, arm64_v10, arm64_v11, arm64_cond_eq)
insn_fcsel_d:
arm64_fcsel_d(arm64_v12, arm64_v13, arm64_v14, arm64_cond_gt)
insn_fccmp_s:
arm64_fccmp_s(arm64_v15, arm64_v16, 5, arm64_cond_ne)
insn_fccmp_d:
arm64_fccmp_d(arm64_v17, arm64_v18, 10, arm64_cond_lt)
insn_fccmpe_d:
arm64_fccmpe_d(arm64_v19, arm64_v20, 15, arm64_cond_hs)
insn_fmov_imm_s:
arm64_fmov_imm_s(arm64_v21, 112)
insn_fmov_imm_d:
arm64_fmov_imm_d(arm64_v22, 128)
insn_fcvt_sd:
arm64_fcvt_sd(arm64_v23, arm64_v24)
insn_fcvt_ds:
arm64_fcvt_ds(arm64_v25, arm64_v26)
insn_scvtf_s_w:
arm64_scvtf_s(arm64_v27, arm64_w28)
insn_scvtf_d_x:
arm64_scvtf_d(arm64_v29, arm64_x30)
insn_ucvtf_s_w:
arm64_ucvtf_s(arm64_v0, arm64_w1)
insn_ucvtf_d_x:
arm64_ucvtf_d(arm64_v2, arm64_x3)
insn_fcvtzs_w_s:
arm64_fcvtzs_w_s(arm64_w4, arm64_v5)
insn_fcvtzs_x_d:
arm64_fcvtzs_x_d(arm64_x6, arm64_v7)
insn_fcvtzu_w_s:
arm64_fcvtzu_w_s(arm64_w8, arm64_v9)
insn_fcvtzu_x_d:
arm64_fcvtzu_x_d(arm64_x10, arm64_v11)
insn_frintn_s:
arm64_frintn_s(arm64_v12, arm64_v13)
insn_frintp_d:
arm64_frintp_d(arm64_v14, arm64_v15)
insn_frintm_s:
arm64_frintm_s(arm64_v16, arm64_v17)
insn_frintz_d:
arm64_frintz_d(arm64_v18, arm64_v19)
insn_frinta_s:
arm64_frinta_s(arm64_v20, arm64_v21)
insn_fldur_s:
arm64_fldur_s(arm64_v22, arm64_x23, -4)
insn_fldur_d:
arm64_fldur_d(arm64_v24, arm64_x25, -8)
insn_fstur_s:
arm64_fstur_s(arm64_v26, arm64_x27, 255)
insn_fstur_d:
arm64_fstur_d(arm64_v28, arm64_sp, -256)
insn_fldr_s_reg:
arm64_fldr_s_reg(arm64_v29, arm64_x30, arm64_x0, arm64_ldst_opt_lsl, false)
insn_fldr_d_reg:
arm64_fldr_d_reg(arm64_v1, arm64_x2, arm64_x3, arm64_ldst_opt_lsl, true)
insn_fstr_s_reg:
arm64_fstr_s_reg(arm64_v4, arm64_x5, arm64_w6, arm64_ldst_opt_uxtw, true)
insn_fstr_d_reg:
arm64_fstr_d_reg(arm64_v7, arm64_x8, arm64_x9, arm64_ldst_opt_sxtx, false)

defer {
    assert(load.u32(insn_fcsel_s) == 0x1e2b0d49, "fcsel s9, s10, s11, eq");
    assert(load.u32(insn_fcsel_d) == 0x1e6ecdac, "fcsel d12, d13, d14, gt");
    assert(load.u32(insn_fccmp_s) == 0x1e3015e5, "fccmp s15, s16, #5, ne");
    assert(load.u32(insn_fccmp_d) == 0x1e72b62a, "fccmp d17, d18, #10, lt");
    assert(load.u32(insn_fccmpe_d) == 0x1e74267f, "fccmpe d19, d20, #15, hs");
    assert(load.u32(insn_fmov_imm_s) == 0x1e2e1015, "fmov s21, #1.0");
    assert(load.u32(insn_fmov_imm_d) == 0x1e701016, "fmov d22, #-2.0");
    assert(load.u32(insn_fcvt_sd) == 0x1e624317, "fcvt s23, d24");
    assert(load.u32(insn_fcvt_ds) == 0x1e22c359, "fcvt d25, s26");
    assert(load.u32(insn_scvtf_s_w) == 0x1e22039b, "scvtf s27, w28");
    assert(load.u32(insn_scvtf_d_x) == 0x9e6203dd, "scvtf d29, x30");
    assert(load.u32(insn_ucvtf_s_w) == 0x1e230020, "ucvtf s0, w1");
    assert(load.u32(insn_ucvtf_d_x) == 0x9e630062, "ucvtf d2, x3");
    assert(load.u32(insn_fcvtzs_w_s) == 0x1e3800a4, "fcvtzs w4, s5");
    assert(load.u32(insn_fcvtzs_x_d) == 0x9e7800e6, "fcvtzs x6, d7");
    assert(load.u32(insn_fcvtzu_w_s) == 0x1e390128, "fcvtzu w8, s9");
    assert(load.u32(insn_fcvtzu_x_d) == 0x9e79016a, "fcvtzu x10, d11");
    assert(load.u32(insn_frintn_s) == 0x1e2441ac, "frintn s12, s13");
    assert(load.u32(insn_frintp_d) == 0x1e64c1ee, "frintp d14, d15");
    assert(load.u32(insn_frintm_s) == 0x1e254230, "frintm s16, s17");
    assert(load.u32(insn_frintz_d) == 0x1e65c272, "frintz d18, d19");
    assert(load.u32(insn_frinta_s) == 0x1e2642b4, "frinta s20, s21");
    assert(load.u32(insn_fldur_s) == 0xbc5fc2f6, "ldur s22, [x23, #-4]");
    assert(load.u32(insn_fldur_d) == 0xfc5f8338, "ldur d24, [x25, #-8]");
    assert(load.u32(insn_fstur_s) == 0xbc0ff37a, "stur s26, [x27, #255]");
    assert(load.u32(insn_fstur_d) == 0xfc1003fc, "stur d28, [sp, #-256]");
    assert(load.u32(insn_fldr_s_reg) == 0xbc606bdd, "ldr s29, [x30, x0]");
    assert(load.u32(insn_fldr_d_reg) == 0xfc637841, "ldr d1, [x2, x3, lsl #3]");
    assert(load.u32(insn_fstr_s_reg) == 0xbc2658a4, "str s4, [x5, w6, uxtw #2]");
    assert(load.u32(insn_fstr_d_reg) == 0xfc29e907, "str d7, [x8, x9, sxtx]");
}
