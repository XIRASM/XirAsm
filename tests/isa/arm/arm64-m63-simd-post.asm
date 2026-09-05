// Batch: SIMD post-index writeback — pair LDP/STP (immediate form) and
// LD1R / LD1 / ST1 post-index (register form; xzr encodes the implicit
// #transfer-size immediate).
//
// Encodings follow LLVM BaseLoadStorePairPostIdx / BaseSIMDLdRPost / the
// POST variants of BaseSIMDLdSt (see include/arm/arm64/simd.inc). Pinned
// words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_ldp_s_post:
arm64_ldp_s_post(arm64_v0, arm64_v1, arm64_x2, 4)
insn_ldp_q_post:
arm64_ldp_q_post(arm64_v3, arm64_v4, arm64_x5, 32)
insn_stp_d_post:
arm64_stp_d_post(arm64_v6, arm64_v7, arm64_x8, -8)
insn_stp_s_post:
arm64_stp_s_post(arm64_v9, arm64_v10, arm64_x11, -256)
insn_ld1r_post_8b:
arm64_ld1r_post(arm64_v12, arm64_arr_8b, arm64_x13, arm64_x14)
insn_ld1r_post_imm:
arm64_ld1r_post(arm64_v15, arm64_arr_4s, arm64_x16, arm64_xzr)
insn_ld1_2_post:
arm64_ld1_2_post(arm64_v17, arm64_v18, arm64_arr_16b, arm64_x19, arm64_x20)
insn_st1_3_post:
arm64_st1_3_post(arm64_v21, arm64_v22, arm64_v23, arm64_arr_4h, arm64_x24, arm64_xzr)
insn_ld1_post_8b:
arm64_ld1_post(arm64_v25, arm64_arr_8b, arm64_x26, arm64_xzr)
insn_st1_post_2s:
arm64_st1_post(arm64_v27, arm64_arr_2s, arm64_x28, arm64_x29)

defer {
    assert(load.u32(insn_ldp_s_post) == 0x2cc08440, "ldp s0, s1, [x2], #4");
    assert(load.u32(insn_ldp_q_post) == 0xacc110a3, "ldp q3, q4, [x5], #32");
    assert(load.u32(insn_stp_d_post) == 0x6cbf9d06, "stp d6, d7, [x8], #-8");
    assert(load.u32(insn_stp_s_post) == 0x2ca02969, "stp s9, s10, [x11], #-256");
    assert(load.u32(insn_ld1r_post_8b) == 0x0dcec1ac, "ld1r { v12.8b }, [x13], x14");
    assert(load.u32(insn_ld1r_post_imm) == 0x4ddfca0f, "ld1r { v15.4s }, [x16], #4");
    assert(load.u32(insn_ld1_2_post) == 0x4cd4a271, "ld1 { v17.16b, v18.16b }, [x19], x20");
    assert(load.u32(insn_st1_3_post) == 0x0c9f6715, "st1 { v21.4h, v22.4h, v23.4h }, [x24], #24");
    assert(load.u32(insn_ld1_post_8b) == 0x0cdf7359, "ld1 { v25.8b }, [x26], #8");
    assert(load.u32(insn_st1_post_2s) == 0x0c9d7b9b, "st1 { v27.2s }, [x28], x29");
}
