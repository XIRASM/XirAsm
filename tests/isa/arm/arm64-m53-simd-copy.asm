// M5b batch 1: AdvSIMD copy space — DUP (general/element), INS
// (general/element), UMOV, SMOV.
//
// Encodings follow the LLVM TableGen classes cited per emitter in
// include/arm/arm64/simd.inc (BaseSIMDInsDup and friends). Every pinned word
// was extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by mkwords.sh (stage-simd-copy.s). clang
// prints the preferred "mov" alias for some INS/UMOV forms; the disassembly
// text in each assert is what clang produced.
import("arm/arm64.inc")

insn_dup_gen_8b:
arm64_dup_gen(arm64_v0, arm64_arr_8b, arm64_w1)
insn_dup_gen_4s:
arm64_dup_gen(arm64_v4, arm64_arr_4s, arm64_w5)
insn_dup_gen_2d:
arm64_dup_gen(arm64_v2, arm64_arr_2d, arm64_x3)
insn_dup_elem_16b:
arm64_dup_elem(arm64_v6, arm64_arr_16b, arm64_v7, 3)
insn_dup_elem_4h:
arm64_dup_elem(arm64_v8, arm64_arr_4h, arm64_v9, 2)
insn_dup_elem_2s:
arm64_dup_elem(arm64_v10, arm64_arr_2s, arm64_v11, 1)
insn_dup_elem_2d:
arm64_dup_elem(arm64_v12, arm64_arr_2d, arm64_v13, 0)
insn_ins_gpr_b:
arm64_ins_gpr(arm64_v14, arm64_ts_b, 5, arm64_w15)
insn_ins_gpr_d:
arm64_ins_gpr(arm64_v16, arm64_ts_d, 1, arm64_x17)
insn_ins_elem_b:
arm64_ins_elem(arm64_v0, arm64_ts_b, 15, arm64_v1, 15)
insn_ins_elem_h:
arm64_ins_elem(arm64_v18, arm64_ts_h, 3, arm64_v19, 6)
insn_ins_elem_s:
arm64_ins_elem(arm64_v20, arm64_ts_s, 1, arm64_v21, 2)
insn_umov_b_w:
arm64_umov(arm64_w22, arm64_ts_b, 4, arm64_v23)
insn_umov_s_w:
arm64_umov(arm64_w24, arm64_ts_s, 3, arm64_v25)
insn_umov_d_x:
arm64_umov(arm64_x26, arm64_ts_d, 1, arm64_v27)
insn_smov_h_w:
arm64_smov(arm64_w28, arm64_ts_h, 5, arm64_v29)
insn_smov_b_x:
arm64_smov(arm64_x30, arm64_ts_b, 15, arm64_v0)

defer {
    assert(load.u32(insn_dup_gen_8b) == 0x0e010c20, "dup v0.8b, w1");
    assert(load.u32(insn_dup_gen_4s) == 0x4e040ca4, "dup v4.4s, w5");
    assert(load.u32(insn_dup_gen_2d) == 0x4e080c62, "dup v2.2d, x3");
    assert(load.u32(insn_dup_elem_16b) == 0x4e0704e6, "dup v6.16b, v7.b[3]");
    assert(load.u32(insn_dup_elem_4h) == 0x0e0a0528, "dup v8.4h, v9.h[2]");
    assert(load.u32(insn_dup_elem_2s) == 0x0e0c056a, "dup v10.2s, v11.s[1]");
    assert(load.u32(insn_dup_elem_2d) == 0x4e0805ac, "dup v12.2d, v13.d[0]");
    assert(load.u32(insn_ins_gpr_b) == 0x4e0b1dee, "mov v14.b[5], w15");
    assert(load.u32(insn_ins_gpr_d) == 0x4e181e30, "mov v16.d[1], x17");
    assert(load.u32(insn_ins_elem_b) == 0x6e1f7c20, "mov v0.b[15], v1.b[15]");
    assert(load.u32(insn_ins_elem_h) == 0x6e0e6672, "mov v18.h[3], v19.h[6]");
    assert(load.u32(insn_ins_elem_s) == 0x6e0c46b4, "mov v20.s[1], v21.s[2]");
    assert(load.u32(insn_umov_b_w) == 0x0e093ef6, "umov w22, v23.b[4]");
    assert(load.u32(insn_umov_s_w) == 0x0e1c3f38, "mov w24, v25.s[3]");
    assert(load.u32(insn_umov_d_x) == 0x4e183f7a, "mov x26, v27.d[1]");
    assert(load.u32(insn_smov_h_w) == 0x0e162fbc, "smov w28, v29.h[5]");
    assert(load.u32(insn_smov_b_x) == 0x4e1f2c1e, "smov x30, v0.b[15]");
}
