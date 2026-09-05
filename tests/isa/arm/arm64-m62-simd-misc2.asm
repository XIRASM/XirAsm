// Batch: EXT, TRN1/TRN2, LD1R, and multi-register LD1/ST1 (x2/x3/x4,
// including a mod-32 register wrap).
//
// Encodings follow LLVM BaseSIMDBitwiseExtract / SIMDZipVector /
// BaseSIMDLdR / SIMDLd1Multiple (see include/arm/arm64/simd.inc). Pinned
// words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_ext_8b:
arm64_ext(arm64_v0, arm64_v1, arm64_v2, 3, arm64_arr_8b)
insn_ext_16b:
arm64_ext(arm64_v3, arm64_v4, arm64_v5, 12, arm64_arr_16b)
insn_trn1_16b:
arm64_trn1(arm64_v6, arm64_v7, arm64_v8, arm64_arr_16b)
insn_trn2_4h:
arm64_trn2(arm64_v9, arm64_v10, arm64_v11, arm64_arr_4h)
insn_ld1r_8b:
arm64_ld1r(arm64_v12, arm64_arr_8b, arm64_x13)
insn_ld1r_4s:
arm64_ld1r(arm64_v14, arm64_arr_4s, arm64_x15)
insn_ld1r_2d:
arm64_ld1r(arm64_v16, arm64_arr_2d, arm64_x17)
insn_ld1_2_8b:
arm64_ld1_2(arm64_v18, arm64_v19, arm64_arr_8b, arm64_x20)
insn_ld1_4_16b:
arm64_ld1_4(arm64_v21, arm64_v22, arm64_v23, arm64_v24, arm64_arr_16b, arm64_x25)
insn_st1_3_4h:
arm64_st1_3(arm64_v26, arm64_v27, arm64_v28, arm64_arr_4h, arm64_x29)
insn_ld1_3_1d:
arm64_ld1_3(arm64_v30, arm64_v31, arm64_v0, arm64_arr_1d, arm64_x1)
insn_st1_2_2s:
arm64_st1_2(arm64_v1, arm64_v2, arm64_arr_2s, arm64_x3)

defer {
    assert(load.u32(insn_ext_8b) == 0x2e021820, "ext v0.8b, v1.8b, v2.8b, #3");
    assert(load.u32(insn_ext_16b) == 0x6e056083, "ext v3.16b, v4.16b, v5.16b, #12");
    assert(load.u32(insn_trn1_16b) == 0x4e0828e6, "trn1 v6.16b, v7.16b, v8.16b");
    assert(load.u32(insn_trn2_4h) == 0x0e4b6949, "trn2 v9.4h, v10.4h, v11.4h");
    assert(load.u32(insn_ld1r_8b) == 0x0d40c1ac, "ld1r { v12.8b }, [x13]");
    assert(load.u32(insn_ld1r_4s) == 0x4d40c9ee, "ld1r { v14.4s }, [x15]");
    assert(load.u32(insn_ld1r_2d) == 0x4d40ce30, "ld1r { v16.2d }, [x17]");
    assert(load.u32(insn_ld1_2_8b) == 0x0c40a292, "ld1 { v18.8b, v19.8b }, [x20]");
    assert(load.u32(insn_ld1_4_16b) == 0x4c402335, "ld1 { v21.16b-v24.16b }, [x25]");
    assert(load.u32(insn_st1_3_4h) == 0x0c0067ba, "st1 { v26.4h-v28.4h }, [x29]");
    assert(load.u32(insn_ld1_3_1d) == 0x0c406c3e, "ld1 { v30.1d, v31.1d, v0.1d }, [x1]");
    assert(load.u32(insn_st1_2_2s) == 0x0c00a861, "st1 { v1.2s, v2.2s }, [x3]");
}
