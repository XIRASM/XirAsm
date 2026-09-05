// Batch: scalar FP min/max completion (FMAX/FMIN/FMAXNM/FMINNM) and
// integer two-register misc (NOT/CNT/REV16/REV32/REV64).
//
// Encodings follow LLVM TwoOperandFPData / BaseSIMDTwoSameVector (see
// include/arm/arm64/fp.inc and simd.inc). Pinned words extracted
// mechanically from clang --target=aarch64-linux-gnu -march=armv8.4-a
// object bytes by the mkwords.sh pipeline. NOT disassembles as the
// preferred alias "mvn".
import("arm/arm64.inc")

insn_fmax_s:
arm64_fmax_s(arm64_v0, arm64_v1, arm64_v2)
insn_fmax_d:
arm64_fmax_d(arm64_v3, arm64_v4, arm64_v5)
insn_fmin_d:
arm64_fmin_d(arm64_v6, arm64_v7, arm64_v8)
insn_fmaxnm_s:
arm64_fmaxnm_s(arm64_v9, arm64_v10, arm64_v11)
insn_fminnm_d:
arm64_fminnm_d(arm64_v12, arm64_v13, arm64_v14)
insn_not_16b:
arm64_not_vec(arm64_v15, arm64_v16, arm64_arr_16b)
insn_cnt_8b:
arm64_cnt_vec(arm64_v17, arm64_v18, arm64_arr_8b)
insn_rev16_16b:
arm64_rev16_vec(arm64_v19, arm64_v20, arm64_arr_16b)
insn_rev32_8h:
arm64_rev32_vec(arm64_v21, arm64_v22, arm64_arr_8h)
insn_rev64_4s:
arm64_rev64_vec(arm64_v23, arm64_v24, arm64_arr_4s)

defer {
    assert(load.u32(insn_fmax_s) == 0x1e224820, "fmax s0, s1, s2");
    assert(load.u32(insn_fmax_d) == 0x1e654883, "fmax d3, d4, d5");
    assert(load.u32(insn_fmin_d) == 0x1e6858e6, "fmin d6, d7, d8");
    assert(load.u32(insn_fmaxnm_s) == 0x1e2b6949, "fmaxnm s9, s10, s11");
    assert(load.u32(insn_fminnm_d) == 0x1e6e79ac, "fminnm d12, d13, d14");
    assert(load.u32(insn_not_16b) == 0x6e205a0f, "mvn v15.16b, v16.16b");
    assert(load.u32(insn_cnt_8b) == 0x0e205a51, "cnt v17.8b, v18.8b");
    assert(load.u32(insn_rev16_16b) == 0x4e201a93, "rev16 v19.16b, v20.16b");
    assert(load.u32(insn_rev32_8h) == 0x6e600ad5, "rev32 v21.8h, v22.8h");
    assert(load.u32(insn_rev64_4s) == 0x4ea00b17, "rev64 v23.4s, v24.4s");
}
