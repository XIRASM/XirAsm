// A64 core integer: add/sub (immediate / shifted register / extended register),
// logical shifted register, and the shift aliases (LSL/LSR/ASR/ROR), MOVN and
// the MOV register alias.
//
// Expected words marked (MC) are byte-for-byte fixtures from
// llvm/test/MC/AArch64/basic-a64-instructions.s; the rest are hand-derived
// from the same field layouts and cross-checked with radare2.
import("arm/arm64.inc");

insn_add_imm_w:
arm64_add_imm(arm64_w4, arm64_w5, 0, 0)

insn_add_imm_lsl_w:
arm64_add_imm(arm64_w30, arm64_w29, 1, 12)

insn_sub_imm_lsl_w:
arm64_sub_imm(arm64_w4, arm64_w20, 546, 12)

insn_add_imm_x:
arm64_add_imm(arm64_x5, arm64_x7, 1638, 0)

insn_add_imm_x0:
arm64_add_imm(arm64_x0, arm64_x1, 1, 0)

// cmp x0, #1
insn_cmp_imm:
arm64_adds_imm(arm64_xzr, arm64_x0, 1, 0)

// sub x0, sp, #16
insn_sub_sp_imm:
arm64_subs_imm(arm64_x0, arm64_sp, 16, 0)

insn_add_reg_w:
arm64_add_reg(arm64_w3, arm64_w5, arm64_w7, 0, 0)

insn_add_reg_lsl_w:
arm64_add_reg(arm64_w17, arm64_w29, arm64_w20, 0, 31)

insn_add_reg_lsr_w:
arm64_add_reg(arm64_w21, arm64_w22, arm64_w23, 1, 0)

// sub x0, x1, x2, asr #5
insn_sub_reg_asr_x:
arm64_sub_reg(arm64_x0, arm64_x1, arm64_x2, 2, 5)

insn_add_ext_uxtb:
arm64_add_ext(arm64_x2, arm64_x4, arm64_w5, arm64_uxtb, 0)

// cmn x4, w5, uxtb #2
insn_cmn_ext_imm:
arm64_adds_ext(arm64_xzr, arm64_x4, arm64_w5, arm64_uxtb, 2)

// cmn sp, w19, uxth #4  (ADDS XZR, SP, w19, uxth #4)
insn_cmn_sp_ext:
arm64_adds_ext(arm64_xzr, arm64_sp, arm64_w19, arm64_uxth, 4)

insn_bic_reg_w:
arm64_bic_reg(arm64_w2, arm64_w7, arm64_w9, 0, 0)

insn_orn_reg_w:
arm64_orn_reg(arm64_w2, arm64_w5, arm64_w29, 0, 0)

insn_bics_reg_w:
arm64_bics_reg(arm64_w3, arm64_w5, arm64_w7, 0, 0)

// mov x0, x1 via ORR
insn_orr_mov_x:
arm64_orr_reg(arm64_x0, arm64_xzr, arm64_x1, 0, 0)

insn_mov_reg_x:
arm64_mov_reg(arm64_x0, arm64_x1)

insn_mov_reg_w:
arm64_mov_reg(arm64_w3, arm64_w4)

// mov x0, #-1
insn_movn_x0:
arm64_movn(arm64_x0, 0, 0)

insn_asr_x_mc:
arm64_asr(arm64_x3, arm64_x4, 63)

insn_asr_w_mc:
arm64_asr(arm64_w3, arm64_w2, 0)

insn_lsl_x:
arm64_lsl(arm64_x0, arm64_x1, 4)

insn_lsr_x:
arm64_lsr(arm64_x0, arm64_x1, 4)

insn_ror_w:
arm64_ror(arm64_w3, arm64_w5, 0)

defer {
    assert(load.u32(insn_add_imm_w) == 0x110000a4, "add w4, w5, #0");
    assert(load.u32(insn_add_imm_lsl_w) == 0x114007be, "add w30, w29, #1, lsl #12");
    assert(load.u32(insn_sub_imm_lsl_w) == 0x51488a84, "sub w4, w20, #546, lsl #12");
    assert(load.u32(insn_add_imm_x) == 0x911998e5, "add x5, x7, #1638");
    assert(load.u32(insn_add_imm_x0) == 0x91000420, "add x0, x1, #1");
    assert(load.u32(insn_cmp_imm) == 0xb100041f, "cmp x0, #1 (adds xzr)");
    assert(load.u32(insn_sub_sp_imm) == 0xf10043e0, "sub x0, sp, #16 (subs)");
    assert(load.u32(insn_add_reg_w) == 0x0b0700a3, "add w3, w5, w7");
    assert(load.u32(insn_add_reg_lsl_w) == 0x0b147fb1, "add w17, w29, w20, lsl #31");
    assert(load.u32(insn_add_reg_lsr_w) == 0x0b5702d5, "add w21, w22, w23, lsr #0");
    assert(load.u32(insn_sub_reg_asr_x) == 0xcb821420, "sub x0, x1, x2, asr #5");
    assert(load.u32(insn_add_ext_uxtb) == 0x8b250082, "add x2, x4, w5, uxtb");
    assert(load.u32(insn_cmn_ext_imm) == 0xab25089f, "cmn x4, w5, uxtb #2");
    assert(load.u32(insn_cmn_sp_ext) == 0xab3333ff, "cmn sp, w19, uxth #4");
    assert(load.u32(insn_bic_reg_w) == 0x0a2900e2, "bic w2, w7, w9");
    assert(load.u32(insn_orn_reg_w) == 0x2a3d00a2, "orn w2, w5, w29");
    assert(load.u32(insn_bics_reg_w) == 0x6a2700a3, "bics w3, w5, w7");
    assert(load.u32(insn_orr_mov_x) == 0xaa0103e0, "mov x0, x1 via orr");
    assert(load.u32(insn_mov_reg_x) == load.u32(insn_orr_mov_x), "mov_reg == orr alias");
    assert(load.u32(insn_mov_reg_w) == 0x2a0403e3, "mov w3, w4");
    assert(load.u32(insn_movn_x0) == 0x92800000, "movn x0, #0");
    assert(load.u32(insn_asr_x_mc) == 0x937ffc83, "asr x3, x4, #63");
    assert(load.u32(insn_asr_w_mc) == 0x13007c43, "asr w3, w2, #0");
    assert(load.u32(insn_lsl_x) == 0xd37cec20, "lsl x0, x1, #4");
    assert(load.u32(insn_lsr_x) == 0xd344fc20, "lsr x0, x1, #4");
    assert(load.u32(insn_ror_w) == 0x138500a3, "ror w3, w5, #0 (extr alias)");
}
