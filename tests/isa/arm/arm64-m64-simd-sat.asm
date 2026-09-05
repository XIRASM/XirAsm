// Batch: saturating arithmetic — SQADD/UQADD/SQSUB/UQSUB/SQSHL/UQSHL
// (register form) and SQDMULH/SQRDMULH (H/S lanes).
//
// Encodings follow LLVM SIMDThreeSameVector / SIMDThreeSameVectorHS (see
// include/arm/arm64/simd.inc). Pinned words extracted mechanically from
// clang --target=aarch64-linux-gnu -march=armv8.4-a object bytes by the
// mkwords.sh pipeline.
import("arm/arm64.inc")

insn_sqadd_16b:
arm64_sqadd_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_16b)
insn_sqadd_8h:
arm64_sqadd_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_8h)
insn_sqadd_2d:
arm64_sqadd_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_2d)
insn_uqadd_4s:
arm64_uqadd_vec(arm64_v9, arm64_v10, arm64_v11, arm64_arr_4s)
insn_sqsub_8b:
arm64_sqsub_vec(arm64_v12, arm64_v13, arm64_v14, arm64_arr_8b)
insn_uqsub_4h:
arm64_uqsub_vec(arm64_v15, arm64_v16, arm64_v17, arm64_arr_4h)
insn_sqshl_8h:
arm64_sqshl_vec(arm64_v18, arm64_v19, arm64_v20, arm64_arr_8h)
insn_uqshl_2s:
arm64_uqshl_vec(arm64_v21, arm64_v22, arm64_v23, arm64_arr_2s)
insn_sqdmulh_4s:
arm64_sqdmulh_vec(arm64_v24, arm64_v25, arm64_v26, arm64_arr_4s)
insn_sqrdmulh_8h:
arm64_sqrdmulh_vec(arm64_v27, arm64_v28, arm64_v29, arm64_arr_8h)

defer {
    assert(load.u32(insn_sqadd_16b) == 0x4e220c20, "sqadd v0.16b, v1.16b, v2.16b");
    assert(load.u32(insn_sqadd_8h) == 0x4e650c83, "sqadd v3.8h, v4.8h, v5.8h");
    assert(load.u32(insn_sqadd_2d) == 0x4ee80ce6, "sqadd v6.2d, v7.2d, v8.2d");
    assert(load.u32(insn_uqadd_4s) == 0x6eab0d49, "uqadd v9.4s, v10.4s, v11.4s");
    assert(load.u32(insn_sqsub_8b) == 0x0e2e2dac, "sqsub v12.8b, v13.8b, v14.8b");
    assert(load.u32(insn_uqsub_4h) == 0x2e712e0f, "uqsub v15.4h, v16.4h, v17.4h");
    assert(load.u32(insn_sqshl_8h) == 0x4e744e72, "sqshl v18.8h, v19.8h, v20.8h");
    assert(load.u32(insn_uqshl_2s) == 0x2eb74ed5, "uqshl v21.2s, v22.2s, v23.2s");
    assert(load.u32(insn_sqdmulh_4s) == 0x4ebab738, "sqdmulh v24.4s, v25.4s, v26.4s");
    assert(load.u32(insn_sqrdmulh_8h) == 0x6e7db79b, "sqrdmulh v27.8h, v28.8h, v29.8h");
}
