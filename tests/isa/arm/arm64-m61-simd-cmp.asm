// Batch: vector comparisons — integer CMEQ/CMGT/CMGE/CMHI/CMHS/CMTST,
// FP FCMEQ/FCMGE/FCMGT/FACGE/FACGT, and ABS/NEG two-register misc.
//
// Encodings follow LLVM SIMDThreeSameVector / SIMDThreeSameVectorFPCmp /
// BaseSIMDTwoSameVector (see include/arm/arm64/simd.inc). Pinned words
// extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_cmeq_16b:
arm64_cmeq_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_16b)
insn_cmeq_4s:
arm64_cmeq_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_4s)
insn_cmeq_2d:
arm64_cmeq_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_2d)
insn_cmgt_8h:
arm64_cmgt_vec(arm64_v9, arm64_v10, arm64_v11, arm64_arr_8h)
insn_cmge_8b:
arm64_cmge_vec(arm64_v12, arm64_v13, arm64_v14, arm64_arr_8b)
insn_cmhi_4s:
arm64_cmhi_vec(arm64_v15, arm64_v16, arm64_v17, arm64_arr_4s)
insn_cmhs_2d:
arm64_cmhs_vec(arm64_v18, arm64_v19, arm64_v20, arm64_arr_2d)
insn_cmtst_16b:
arm64_cmtst_vec(arm64_v21, arm64_v22, arm64_v23, arm64_arr_16b)
insn_fcmeq_4s:
arm64_fcmeq_vec(arm64_v24, arm64_v25, arm64_v26, arm64_arr_4s)
insn_fcmge_2d:
arm64_fcmge_vec(arm64_v27, arm64_v28, arm64_v29, arm64_arr_2d)
insn_fcmgt_4s:
arm64_fcmgt_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_4s)
insn_facge_2s:
arm64_facge_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_2s)
insn_facgt_2d:
arm64_facgt_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_2d)
insn_abs_16b:
arm64_abs_vec(arm64_v9, arm64_v10, arm64_arr_16b)
insn_abs_2d:
arm64_abs_vec(arm64_v11, arm64_v12, arm64_arr_2d)
insn_neg_8h:
arm64_neg_vec(arm64_v13, arm64_v14, arm64_arr_8h)

defer {
    assert(load.u32(insn_cmeq_16b) == 0x6e228c20, "cmeq v0.16b, v1.16b, v2.16b");
    assert(load.u32(insn_cmeq_4s) == 0x6ea58c83, "cmeq v3.4s, v4.4s, v5.4s");
    assert(load.u32(insn_cmeq_2d) == 0x6ee88ce6, "cmeq v6.2d, v7.2d, v8.2d");
    assert(load.u32(insn_cmgt_8h) == 0x4e6b3549, "cmgt v9.8h, v10.8h, v11.8h");
    assert(load.u32(insn_cmge_8b) == 0x0e2e3dac, "cmge v12.8b, v13.8b, v14.8b");
    assert(load.u32(insn_cmhi_4s) == 0x6eb1360f, "cmhi v15.4s, v16.4s, v17.4s");
    assert(load.u32(insn_cmhs_2d) == 0x6ef43e72, "cmhs v18.2d, v19.2d, v20.2d");
    assert(load.u32(insn_cmtst_16b) == 0x4e378ed5, "cmtst v21.16b, v22.16b, v23.16b");
    assert(load.u32(insn_fcmeq_4s) == 0x4e3ae738, "fcmeq v24.4s, v25.4s, v26.4s");
    assert(load.u32(insn_fcmge_2d) == 0x6e7de79b, "fcmge v27.2d, v28.2d, v29.2d");
    assert(load.u32(insn_fcmgt_4s) == 0x6ea2e420, "fcmgt v0.4s, v1.4s, v2.4s");
    assert(load.u32(insn_facge_2s) == 0x2e25ec83, "facge v3.2s, v4.2s, v5.2s");
    assert(load.u32(insn_facgt_2d) == 0x6ee8ece6, "facgt v6.2d, v7.2d, v8.2d");
    assert(load.u32(insn_abs_16b) == 0x4e20b949, "abs v9.16b, v10.16b");
    assert(load.u32(insn_abs_2d) == 0x4ee0b98b, "abs v11.2d, v12.2d");
    assert(load.u32(insn_neg_8h) == 0x6e60b9cd, "neg v13.8h, v14.8h");
}
