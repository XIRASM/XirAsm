// Batch: pairwise adds (ADDP/FADDP), min/max (SMAX/SMIN/UMAX/UMIN), and
// tied shift-insert (SLI/SRI).
//
// Encodings follow LLVM SIMDThreeSameVector / SIMDThreeSameVectorFP /
// the tied shift-immediate classes (see include/arm/arm64/simd.inc).
// Pinned words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_addp_16b:
arm64_addp_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_16b)
insn_addp_2d:
arm64_addp_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_2d)
insn_faddp_4s:
arm64_faddp_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_4s)
insn_faddp_2d:
arm64_faddp_vec(arm64_v9, arm64_v10, arm64_v11, arm64_arr_2d)
insn_smax_8h:
arm64_smax_vec(arm64_v12, arm64_v13, arm64_v14, arm64_arr_8h)
insn_smin_4s:
arm64_smin_vec(arm64_v15, arm64_v16, arm64_v17, arm64_arr_4s)
insn_umax_16b:
arm64_umax_vec(arm64_v18, arm64_v19, arm64_v20, arm64_arr_16b)
insn_umin_8b:
arm64_umin_vec(arm64_v21, arm64_v22, arm64_v23, arm64_arr_8b)
insn_sli_8b:
arm64_sli(arm64_v24, arm64_v25, 3, arm64_arr_8b)
insn_sri_4s:
arm64_sri(arm64_v26, arm64_v27, 12, arm64_arr_4s)

defer {
    assert(load.u32(insn_addp_16b) == 0x4e22bc20, "addp v0.16b, v1.16b, v2.16b");
    assert(load.u32(insn_addp_2d) == 0x4ee5bc83, "addp v3.2d, v4.2d, v5.2d");
    assert(load.u32(insn_faddp_4s) == 0x6e28d4e6, "faddp v6.4s, v7.4s, v8.4s");
    assert(load.u32(insn_faddp_2d) == 0x6e6bd549, "faddp v9.2d, v10.2d, v11.2d");
    assert(load.u32(insn_smax_8h) == 0x4e6e65ac, "smax v12.8h, v13.8h, v14.8h");
    assert(load.u32(insn_smin_4s) == 0x4eb16e0f, "smin v15.4s, v16.4s, v17.4s");
    assert(load.u32(insn_umax_16b) == 0x6e346672, "umax v18.16b, v19.16b, v20.16b");
    assert(load.u32(insn_umin_8b) == 0x2e376ed5, "umin v21.8b, v22.8b, v23.8b");
    assert(load.u32(insn_sli_8b) == 0x2f0b5738, "sli v24.8b, v25.8b, #3");
    assert(load.u32(insn_sri_4s) == 0x6f34477a, "sri v26.4s, v27.4s, #12");
}
