// M4.7: integer multiply and divide family.
//
// 3-source layout (LLVM BaseMulAccum / WideMulAccum / MulHi):
//   sf(31) 0011011(30-24) opc(23-21) Rm(20-16) isSub(15) Ra(14-10) Rn(9-5)
//   Rd(4-0); opc 000 = MADD/MSUB, 001 = SMADDL/SMSUBL/SMULL, 011 =
//   UMADDL/UMSUBL/UMULL, 010 = SMULH, 110 = UMULH; widening forms force
//   sf = 1. Division rides the 2-source layout with op2 0b000011 (SDIV) /
//   0b000010 (UDIV).
// All words extracted mechanically from clang -target=aarch64 assembly.
import("arm/arm64.inc")

insn_mul_w:
arm64_mul(arm64_w3, arm64_w4, arm64_w5)
insn_mul_x:
arm64_mul(arm64_x3, arm64_x4, arm64_x5)
insn_madd_x:
arm64_madd(arm64_x0, arm64_x1, arm64_x2, arm64_x3)
insn_msub_w:
arm64_msub(arm64_w0, arm64_w1, arm64_w2, arm64_w3)
insn_smull:
arm64_smull(arm64_x0, arm64_w1, arm64_w2)
insn_umull:
arm64_umull(arm64_x1, arm64_w2, arm64_w3)
insn_smaddl:
arm64_smaddl(arm64_x2, arm64_w3, arm64_w4, arm64_x5)
insn_umaddl:
arm64_umaddl(arm64_x3, arm64_w4, arm64_w5, arm64_x6)
insn_smsubl:
arm64_smsubl(arm64_x4, arm64_w5, arm64_w6, arm64_x7)
insn_umsubl:
arm64_umsubl(arm64_x5, arm64_w6, arm64_w7, arm64_x8)
insn_smulh:
arm64_smulh(arm64_x9, arm64_x10, arm64_x11)
insn_umulh:
arm64_umulh(arm64_x12, arm64_x13, arm64_x14)
insn_sdiv_w:
arm64_sdiv(arm64_w15, arm64_w16, arm64_w17)
insn_sdiv_x:
arm64_sdiv(arm64_x18, arm64_x19, arm64_x20)
insn_udiv_w:
arm64_udiv(arm64_w21, arm64_w22, arm64_w23)
insn_udiv_x:
arm64_udiv(arm64_x24, arm64_x25, arm64_x26)

defer {
    assert(load.u32(insn_mul_w) == 0x1b057c83, "mul w3, w4, w5");
    assert(load.u32(insn_mul_x) == 0x9b057c83, "mul x3, x4, x5");
    assert(load.u32(insn_madd_x) == 0x9b020c20, "madd x0, x1, x2, x3");
    assert(load.u32(insn_msub_w) == 0x1b028c20, "msub w0, w1, w2, w3");
    assert(load.u32(insn_smull) == 0x9b227c20, "smull x0, w1, w2");
    assert(load.u32(insn_umull) == 0x9ba37c41, "umull x1, w2, w3");
    assert(load.u32(insn_smaddl) == 0x9b241462, "smaddl x2, w3, w4, x5");
    assert(load.u32(insn_umaddl) == 0x9ba51883, "umaddl x3, w4, w5, x6");
    assert(load.u32(insn_smsubl) == 0x9b269ca4, "smsubl x4, w5, w6, x7");
    assert(load.u32(insn_umsubl) == 0x9ba7a0c5, "umsubl x5, w6, w7, x8");
    assert(load.u32(insn_smulh) == 0x9b4b7d49, "smulh x9, x10, x11");
    assert(load.u32(insn_umulh) == 0x9bce7dac, "umulh x12, x13, x14");
    assert(load.u32(insn_sdiv_w) == 0x1ad10e0f, "sdiv w15, w16, w17");
    assert(load.u32(insn_sdiv_x) == 0x9ad40e72, "sdiv x18, x19, x20");
    assert(load.u32(insn_udiv_w) == 0x1ad70ad5, "udiv w21, w22, w23");
    assert(load.u32(insn_udiv_x) == 0x9ada0b38, "udiv x24, x25, x26");
}
