// M5b batch 5: vector shift by immediate — SHL/SSHR/USHR and the widening
// SSHLL/SSHLL2/USHLL/USHLL2 forms.
//
// Encodings follow LLVM BaseSIMDVectorShift (see include/arm/arm64/simd.inc).
// Pinned words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_shl_8b:
arm64_shl(arm64_v0, arm64_v1, 3, arm64_arr_8b)
insn_shl_16b:
arm64_shl(arm64_v2, arm64_v3, 7, arm64_arr_16b)
insn_shl_4h:
arm64_shl(arm64_v4, arm64_v5, 9, arm64_arr_4h)
insn_shl_2s:
arm64_shl(arm64_v6, arm64_v7, 17, arm64_arr_2s)
insn_shl_2d:
arm64_shl(arm64_v8, arm64_v9, 33, arm64_arr_2d)
insn_sshr_4h:
arm64_sshr(arm64_v10, arm64_v11, 4, arm64_arr_4h)
insn_sshr_8b:
arm64_sshr(arm64_v12, arm64_v13, 8, arm64_arr_8b)
insn_ushr_4s:
arm64_ushr(arm64_v14, arm64_v15, 12, arm64_arr_4s)
insn_ushr_2d:
arm64_ushr(arm64_v16, arm64_v17, 64, arm64_arr_2d)
insn_ushr_16b:
arm64_ushr(arm64_v18, arm64_v19, 2, arm64_arr_16b)
insn_sshll_8h_from8b:
arm64_sshll(arm64_v20, arm64_v21, 1, arm64_arr_8b)
insn_sshll2_8h_from16b:
arm64_sshll2(arm64_v22, arm64_v23, 3, arm64_arr_16b)
insn_ushll_4s_from4h:
arm64_ushll(arm64_v24, arm64_v25, 5, arm64_arr_4h)
insn_ushll2_4s_from8h:
arm64_ushll2(arm64_v26, arm64_v27, 7, arm64_arr_8h)
insn_ushll_2d_from2s:
arm64_ushll(arm64_v28, arm64_v29, 7, arm64_arr_2s)

defer {
    assert(load.u32(insn_shl_8b) == 0x0f0b5420, "shl v0.8b, v1.8b, #3");
    assert(load.u32(insn_shl_16b) == 0x4f0f5462, "shl v2.16b, v3.16b, #7");
    assert(load.u32(insn_shl_4h) == 0x0f1954a4, "shl v4.4h, v5.4h, #9");
    assert(load.u32(insn_shl_2s) == 0x0f3154e6, "shl v6.2s, v7.2s, #17");
    assert(load.u32(insn_shl_2d) == 0x4f615528, "shl v8.2d, v9.2d, #33");
    assert(load.u32(insn_sshr_4h) == 0x0f1c056a, "sshr v10.4h, v11.4h, #4");
    assert(load.u32(insn_sshr_8b) == 0x0f0805ac, "sshr v12.8b, v13.8b, #8");
    assert(load.u32(insn_ushr_4s) == 0x6f3405ee, "ushr v14.4s, v15.4s, #12");
    assert(load.u32(insn_ushr_2d) == 0x6f400630, "ushr v16.2d, v17.2d, #64");
    assert(load.u32(insn_ushr_16b) == 0x6f0e0672, "ushr v18.16b, v19.16b, #2");
    assert(load.u32(insn_sshll_8h_from8b) == 0x0f09a6b4, "sshll v20.8h, v21.8b, #1");
    assert(load.u32(insn_sshll2_8h_from16b) == 0x4f0ba6f6, "sshll2 v22.8h, v23.16b, #3");
    assert(load.u32(insn_ushll_4s_from4h) == 0x2f15a738, "ushll v24.4s, v25.4h, #5");
    assert(load.u32(insn_ushll2_4s_from8h) == 0x6f17a77a, "ushll2 v26.4s, v27.8h, #7");
    assert(load.u32(insn_ushll_2d_from2s) == 0x2f27a7bc, "ushll v28.2d, v29.2s, #7");
}
