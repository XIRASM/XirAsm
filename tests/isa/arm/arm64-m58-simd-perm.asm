// M5b batch 6: UZP1/UZP2/ZIP1/ZIP2 vector permutes.
//
// Encodings follow LLVM BaseSIMDZipVector (see include/arm/arm64/simd.inc).
// Pinned words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_uzp1_16b:
arm64_uzp1(arm64_v0, arm64_v1, arm64_v2, arm64_arr_16b)
insn_uzp2_8b:
arm64_uzp2(arm64_v3, arm64_v4, arm64_v5, arm64_arr_8b)
insn_uzp1_4h:
arm64_uzp1(arm64_v6, arm64_v7, arm64_v8, arm64_arr_4h)
insn_uzp2_8h:
arm64_uzp2(arm64_v9, arm64_v10, arm64_v11, arm64_arr_8h)
insn_zip1_2s:
arm64_zip1(arm64_v12, arm64_v13, arm64_v14, arm64_arr_2s)
insn_zip2_4s:
arm64_zip2(arm64_v15, arm64_v16, arm64_v17, arm64_arr_4s)
insn_zip1_2d:
arm64_zip1(arm64_v18, arm64_v19, arm64_v20, arm64_arr_2d)
insn_uzp1_8b:
arm64_uzp1(arm64_v21, arm64_v22, arm64_v23, arm64_arr_8b)
insn_zip2_16b:
arm64_zip2(arm64_v24, arm64_v25, arm64_v26, arm64_arr_16b)
insn_uzp2_2d:
arm64_uzp2(arm64_v27, arm64_v28, arm64_v29, arm64_arr_2d)

defer {
    assert(load.u32(insn_uzp1_16b) == 0x4e021820, "uzp1 v0.16b, v1.16b, v2.16b");
    assert(load.u32(insn_uzp2_8b) == 0x0e055883, "uzp2 v3.8b, v4.8b, v5.8b");
    assert(load.u32(insn_uzp1_4h) == 0x0e4818e6, "uzp1 v6.4h, v7.4h, v8.4h");
    assert(load.u32(insn_uzp2_8h) == 0x4e4b5949, "uzp2 v9.8h, v10.8h, v11.8h");
    assert(load.u32(insn_zip1_2s) == 0x0e8e39ac, "zip1 v12.2s, v13.2s, v14.2s");
    assert(load.u32(insn_zip2_4s) == 0x4e917a0f, "zip2 v15.4s, v16.4s, v17.4s");
    assert(load.u32(insn_zip1_2d) == 0x4ed43a72, "zip1 v18.2d, v19.2d, v20.2d");
    assert(load.u32(insn_uzp1_8b) == 0x0e171ad5, "uzp1 v21.8b, v22.8b, v23.8b");
    assert(load.u32(insn_zip2_16b) == 0x4e1a7b38, "zip2 v24.16b, v25.16b, v26.16b");
    assert(load.u32(insn_uzp2_2d) == 0x4edd5b9b, "uzp2 v27.2d, v28.2d, v29.2d");
}
