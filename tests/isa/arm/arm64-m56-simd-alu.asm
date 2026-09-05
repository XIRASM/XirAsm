// M5b batch 5: vector three-same ADD/SUB/MUL and bitwise logical ops
// (AND/BIC/ORR/ORN/EOR, tied BSL/BIT/BIF).
//
// Encodings follow LLVM BaseSIMDThreeSameVector and the logical variants
// (see include/arm/arm64/simd.inc). Pinned words extracted mechanically
// from clang --target=aarch64-linux-gnu -march=armv8.4-a object bytes by
// the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_add_16b:
arm64_add_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_16b)
insn_add_8h:
arm64_add_vec(arm64_v3, arm64_v4, arm64_v5, arm64_arr_8h)
insn_add_2s:
arm64_add_vec(arm64_v6, arm64_v7, arm64_v8, arm64_arr_2s)
insn_add_2d:
arm64_add_vec(arm64_v9, arm64_v10, arm64_v11, arm64_arr_2d)
insn_sub_4s:
arm64_sub_vec(arm64_v12, arm64_v13, arm64_v14, arm64_arr_4s)
insn_sub_8b:
arm64_sub_vec(arm64_v15, arm64_v16, arm64_v17, arm64_arr_8b)
insn_mul_8b:
arm64_mul_vec(arm64_v18, arm64_v19, arm64_v20, arm64_arr_8b)
insn_mul_4s:
arm64_mul_vec(arm64_v21, arm64_v22, arm64_v23, arm64_arr_4s)
insn_and_16b:
arm64_and_vec(arm64_v24, arm64_v25, arm64_v26, arm64_arr_16b)
insn_orr_8b:
arm64_orr_vec(arm64_v27, arm64_v28, arm64_v29, arm64_arr_8b)
insn_eor_8b:
arm64_eor_vec(arm64_v30, arm64_v31, arm64_v0, arm64_arr_8b)
insn_eor_16b:
arm64_eor_vec(arm64_v1, arm64_v2, arm64_v3, arm64_arr_16b)
insn_bic_16b:
arm64_bic_vec(arm64_v4, arm64_v5, arm64_v6, arm64_arr_16b)
insn_orn_8b:
arm64_orn_vec(arm64_v7, arm64_v8, arm64_v9, arm64_arr_8b)
insn_bsl_16b:
arm64_bsl_vec(arm64_v10, arm64_v11, arm64_v12, arm64_arr_16b)
insn_bit_8b:
arm64_bit_vec(arm64_v13, arm64_v14, arm64_v15, arm64_arr_8b)
insn_bif_16b:
arm64_bif_vec(arm64_v16, arm64_v17, arm64_v18, arm64_arr_16b)

defer {
    assert(load.u32(insn_add_16b) == 0x4e228420, "add v0.16b, v1.16b, v2.16b");
    assert(load.u32(insn_add_8h) == 0x4e658483, "add v3.8h, v4.8h, v5.8h");
    assert(load.u32(insn_add_2s) == 0x0ea884e6, "add v6.2s, v7.2s, v8.2s");
    assert(load.u32(insn_add_2d) == 0x4eeb8549, "add v9.2d, v10.2d, v11.2d");
    assert(load.u32(insn_sub_4s) == 0x6eae85ac, "sub v12.4s, v13.4s, v14.4s");
    assert(load.u32(insn_sub_8b) == 0x2e31860f, "sub v15.8b, v16.8b, v17.8b");
    assert(load.u32(insn_mul_8b) == 0x0e349e72, "mul v18.8b, v19.8b, v20.8b");
    assert(load.u32(insn_mul_4s) == 0x4eb79ed5, "mul v21.4s, v22.4s, v23.4s");
    assert(load.u32(insn_and_16b) == 0x4e3a1f38, "and v24.16b, v25.16b, v26.16b");
    assert(load.u32(insn_orr_8b) == 0x0ebd1f9b, "orr v27.8b, v28.8b, v29.8b");
    assert(load.u32(insn_eor_8b) == 0x2e201ffe, "eor v30.8b, v31.8b, v0.8b");
    assert(load.u32(insn_eor_16b) == 0x6e231c41, "eor v1.16b, v2.16b, v3.16b");
    assert(load.u32(insn_bic_16b) == 0x4e661ca4, "bic v4.16b, v5.16b, v6.16b");
    assert(load.u32(insn_orn_8b) == 0x0ee91d07, "orn v7.8b, v8.8b, v9.8b");
    assert(load.u32(insn_bsl_16b) == 0x6e6c1d6a, "bsl v10.16b, v11.16b, v12.16b");
    assert(load.u32(insn_bit_8b) == 0x2eaf1dcd, "bit v13.8b, v14.8b, v15.8b");
    assert(load.u32(insn_bif_16b) == 0x6ef21e30, "bif v16.16b, v17.16b, v18.16b");
}
