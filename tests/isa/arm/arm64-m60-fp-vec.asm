// Batch: vector FP arithmetic — three-same FADD/FSUB/FMUL/FDIV/FMAX/FMIN/
// FMAXNM/FMINNM, tied FMLA/FMLS, and one-source FABS/FNEG/FSQRT.
// Arrangements limited to 2S/4S/2D per the encoding.
//
// Encodings follow LLVM SIMDThreeSameVectorFP / SIMDTwoVectorFP (see
// include/arm/arm64/simd.inc). Pinned words extracted mechanically from
// clang --target=aarch64-linux-gnu -march=armv8.4-a object bytes by the
// mkwords.sh pipeline.
import("arm/arm64.inc")

insn_fadd_2s:
arm64_fadd_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_2s)
insn_fadd_4s:
arm64_fadd_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_4s)
insn_fadd_2d:
arm64_fadd_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_2d)
insn_fsub_4s:
arm64_fsub_vec(arm64_v9, arm64_v10, arm64_v11, arm64_arr_4s)
insn_fmul_2s:
arm64_fmul_vec(arm64_v12, arm64_v13, arm64_v14, arm64_arr_2s)
insn_fdiv_2d:
arm64_fdiv_vec(arm64_v15, arm64_v16, arm64_v17, arm64_arr_2d)
insn_fmax_4s:
arm64_fmax_vec(arm64_v18, arm64_v19, arm64_v20, arm64_arr_4s)
insn_fmin_4s:
arm64_fmin_vec(arm64_v21, arm64_v22, arm64_v23, arm64_arr_4s)
insn_fmaxnm_2d:
arm64_fmaxnm_vec(arm64_v24, arm64_v25, arm64_v26, arm64_arr_2d)
insn_fminnm_2s:
arm64_fminnm_vec(arm64_v27, arm64_v28, arm64_v29, arm64_arr_2s)
insn_fmla_4s:
arm64_fmla_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_4s)
insn_fmls_2d:
arm64_fmls_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_2d)
insn_fabs_2s:
arm64_fabs_vec(arm64_v6, arm64_v7, arm64_arr_2s)
insn_fabs_4s:
arm64_fabs_vec(arm64_v8, arm64_v9, arm64_arr_4s)
insn_fabs_2d:
arm64_fabs_vec(arm64_v10, arm64_v11, arm64_arr_2d)
insn_fneg_4s:
arm64_fneg_vec(arm64_v12, arm64_v13, arm64_arr_4s)
insn_fsqrt_2d:
arm64_fsqrt_vec(arm64_v14, arm64_v15, arm64_arr_2d)

defer {
    assert(load.u32(insn_fadd_2s) == 0x0e22d420, "fadd v0.2s, v1.2s, v2.2s");
    assert(load.u32(insn_fadd_4s) == 0x4e25d483, "fadd v3.4s, v4.4s, v5.4s");
    assert(load.u32(insn_fadd_2d) == 0x4e68d4e6, "fadd v6.2d, v7.2d, v8.2d");
    assert(load.u32(insn_fsub_4s) == 0x4eabd549, "fsub v9.4s, v10.4s, v11.4s");
    assert(load.u32(insn_fmul_2s) == 0x2e2eddac, "fmul v12.2s, v13.2s, v14.2s");
    assert(load.u32(insn_fdiv_2d) == 0x6e71fe0f, "fdiv v15.2d, v16.2d, v17.2d");
    assert(load.u32(insn_fmax_4s) == 0x4e34f672, "fmax v18.4s, v19.4s, v20.4s");
    assert(load.u32(insn_fmin_4s) == 0x4eb7f6d5, "fmin v21.4s, v22.4s, v23.4s");
    assert(load.u32(insn_fmaxnm_2d) == 0x4e7ac738, "fmaxnm v24.2d, v25.2d, v26.2d");
    assert(load.u32(insn_fminnm_2s) == 0x0ebdc79b, "fminnm v27.2s, v28.2s, v29.2s");
    assert(load.u32(insn_fmla_4s) == 0x4e22cc20, "fmla v0.4s, v1.4s, v2.4s");
    assert(load.u32(insn_fmls_2d) == 0x4ee5cc83, "fmls v3.2d, v4.2d, v5.2d");
    assert(load.u32(insn_fabs_2s) == 0x0ea0f8e6, "fabs v6.2s, v7.2s");
    assert(load.u32(insn_fabs_4s) == 0x4ea0f928, "fabs v8.4s, v9.4s");
    assert(load.u32(insn_fabs_2d) == 0x4ee0f96a, "fabs v10.2d, v11.2d");
    assert(load.u32(insn_fneg_4s) == 0x6ea0f9ac, "fneg v12.4s, v13.4s");
    assert(load.u32(insn_fsqrt_2d) == 0x6ee1f9ee, "fsqrt v14.2d, v15.2d");
}
