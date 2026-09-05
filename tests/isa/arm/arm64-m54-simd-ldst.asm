// M5b batch 2: LD1/ST1 (multiple structures, one register, no offset) for
// all eight arrangements, including an SP base.
//
// Encodings follow LLVM BaseSIMDLdSt (see include/arm/arm64/simd.inc).
// Pinned words extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a by mkwords.sh (stage-simd-ldst.s).
import("arm/arm64.inc")

insn_ld1_8b:
arm64_ld1(arm64_v0, arm64_arr_8b, arm64_x1)
insn_ld1_16b:
arm64_ld1(arm64_v2, arm64_arr_16b, arm64_x3)
insn_ld1_4h:
arm64_ld1(arm64_v4, arm64_arr_4h, arm64_x5)
insn_ld1_8h:
arm64_ld1(arm64_v6, arm64_arr_8h, arm64_x7)
insn_ld1_2s:
arm64_ld1(arm64_v8, arm64_arr_2s, arm64_x9)
insn_ld1_4s:
arm64_ld1(arm64_v10, arm64_arr_4s, arm64_x11)
insn_ld1_1d:
arm64_ld1(arm64_v12, arm64_arr_1d, arm64_x13)
insn_ld1_2d:
arm64_ld1(arm64_v14, arm64_arr_2d, arm64_sp)
insn_st1_8b:
arm64_st1(arm64_v15, arm64_arr_8b, arm64_x16)
insn_st1_16b:
arm64_st1(arm64_v16, arm64_arr_16b, arm64_x17)
insn_st1_4h:
arm64_st1(arm64_v18, arm64_arr_4h, arm64_x19)
insn_st1_8h:
arm64_st1(arm64_v20, arm64_arr_8h, arm64_x21)
insn_st1_2s:
arm64_st1(arm64_v22, arm64_arr_2s, arm64_x23)
insn_st1_4s:
arm64_st1(arm64_v24, arm64_arr_4s, arm64_x25)
insn_st1_1d:
arm64_st1(arm64_v26, arm64_arr_1d, arm64_x27)
insn_st1_2d:
arm64_st1(arm64_v28, arm64_arr_2d, arm64_x29)

defer {
    assert(load.u32(insn_ld1_8b) == 0x0c407020, "ld1 { v0.8b }, [x1]");
    assert(load.u32(insn_ld1_16b) == 0x4c407062, "ld1 { v2.16b }, [x3]");
    assert(load.u32(insn_ld1_4h) == 0x0c4074a4, "ld1 { v4.4h }, [x5]");
    assert(load.u32(insn_ld1_8h) == 0x4c4074e6, "ld1 { v6.8h }, [x7]");
    assert(load.u32(insn_ld1_2s) == 0x0c407928, "ld1 { v8.2s }, [x9]");
    assert(load.u32(insn_ld1_4s) == 0x4c40796a, "ld1 { v10.4s }, [x11]");
    assert(load.u32(insn_ld1_1d) == 0x0c407dac, "ld1 { v12.1d }, [x13]");
    assert(load.u32(insn_ld1_2d) == 0x4c407fee, "ld1 { v14.2d }, [sp]");
    assert(load.u32(insn_st1_8b) == 0x0c00720f, "st1 { v15.8b }, [x16]");
    assert(load.u32(insn_st1_16b) == 0x4c007230, "st1 { v16.16b }, [x17]");
    assert(load.u32(insn_st1_4h) == 0x0c007672, "st1 { v18.4h }, [x19]");
    assert(load.u32(insn_st1_8h) == 0x4c0076b4, "st1 { v20.8h }, [x21]");
    assert(load.u32(insn_st1_2s) == 0x0c007af6, "st1 { v22.2s }, [x23]");
    assert(load.u32(insn_st1_4s) == 0x4c007b38, "st1 { v24.4s }, [x25]");
    assert(load.u32(insn_st1_1d) == 0x0c007f7a, "st1 { v26.1d }, [x27]");
    assert(load.u32(insn_st1_2d) == 0x4c007fbc, "st1 { v28.2d }, [x29]");
}
