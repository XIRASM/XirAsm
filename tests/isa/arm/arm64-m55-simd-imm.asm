// M5b batch 3: MOVI/MVNI AdvSIMD modified immediates — byte, halfword
// (LSL 0/8), word (LSL 0/8/16/24), word MSL, and the 64-bit replicated form.
//
// Encodings follow LLVM BaseSIMDModifiedImm and its instantiations (see
// include/arm/arm64/simd.inc). Pinned words extracted mechanically from
// clang --target=aarch64-linux-gnu -march=armv8.4-a by mkwords.sh
// (stage-simd-imm.s). The 2D form call passes the raw imm8 field, where
// each bit fills one byte with 0x00/0xff; field 1 = value 0x000000000000ff
// (clang word bits 20-16/9-5 extracted mechanically).
import("arm/arm64.inc")

insn_movi_8b:
arm64_movi_b(arm64_v0, arm64_arr_8b, 0x5a)
insn_movi_16b:
arm64_movi_b(arm64_v2, arm64_arr_16b, 255)
insn_movi_4h:
arm64_movi_h(arm64_v4, arm64_arr_4h, 0x12, false)
insn_movi_8h_lsl8:
arm64_movi_h(arm64_v6, arm64_arr_8h, 0x34, true)
insn_movi_2s:
arm64_movi_s(arm64_v8, arm64_arr_2s, 0x56, 0)
insn_movi_4s_lsl16:
arm64_movi_s(arm64_v10, arm64_arr_4s, 0x78, 2)
insn_movi_4s_lsl24:
arm64_movi_s(arm64_v12, arm64_arr_4s, 0x9a, 3)
insn_movi_2s_msl8:
arm64_movi_s_msl(arm64_v14, arm64_arr_2s, 0xbc, false)
insn_movi_4s_msl16:
arm64_movi_s_msl(arm64_v16, arm64_arr_4s, 0xde, true)
insn_movi_2d:
arm64_movi_d(arm64_v18, 1)
insn_mvni_4h:
arm64_mvni_h(arm64_v20, arm64_arr_4h, 0x11, false)
insn_mvni_8h_lsl8:
arm64_mvni_h(arm64_v22, arm64_arr_8h, 0x22, true)
insn_mvni_2s:
arm64_mvni_s(arm64_v24, arm64_arr_2s, 0x33, 0)
insn_mvni_4s_lsl8:
arm64_mvni_s(arm64_v26, arm64_arr_4s, 0x44, 1)
insn_mvni_2s_msl16:
arm64_mvni_s_msl(arm64_v28, arm64_arr_2s, 0x55, true)

defer {
    assert(load.u32(insn_movi_8b) == 0x0f02e740, "movi v0.8b, #0x5a");
    assert(load.u32(insn_movi_16b) == 0x4f07e7e2, "movi v2.16b, #255");
    assert(load.u32(insn_movi_4h) == 0x0f008644, "movi v4.4h, #0x12");
    assert(load.u32(insn_movi_8h_lsl8) == 0x4f01a686, "movi v6.8h, #0x34, lsl #8");
    assert(load.u32(insn_movi_2s) == 0x0f0206c8, "movi v8.2s, #0x56");
    assert(load.u32(insn_movi_4s_lsl16) == 0x4f03470a, "movi v10.4s, #0x78, lsl #16");
    assert(load.u32(insn_movi_4s_lsl24) == 0x4f04674c, "movi v12.4s, #0x9a, lsl #24");
    assert(load.u32(insn_movi_2s_msl8) == 0x0f05c78e, "movi v14.2s, #0xbc, msl #8");
    assert(load.u32(insn_movi_4s_msl16) == 0x4f06d7d0, "movi v16.4s, #0xde, msl #16");
    assert(load.u32(insn_movi_2d) == 0x6f00e432, "movi v18.2d, #0xff");
    assert(load.u32(insn_mvni_4h) == 0x2f008634, "mvni v20.4h, #0x11");
    assert(load.u32(insn_mvni_8h_lsl8) == 0x6f01a456, "mvni v22.8h, #0x22, lsl #8");
    assert(load.u32(insn_mvni_2s) == 0x2f010678, "mvni v24.2s, #0x33");
    assert(load.u32(insn_mvni_4s_lsl8) == 0x6f02249a, "mvni v26.4s, #0x44, lsl #8");
    assert(load.u32(insn_mvni_2s_msl16) == 0x2f02d6bc, "mvni v28.2s, #0x55, msl #16");
}
