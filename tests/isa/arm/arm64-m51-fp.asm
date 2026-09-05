// M5a: scalar floating point — load/store, arithmetic, compare, move.
//
// FP load/store unsigned immediate: size(31-30) 111 V=1 01 opc imm12 Rn Rt
// (opc 00 STR / 01 LDR; size 10 = S, 11 = D, imm12 scaled by 4/8).
// Scalar arithmetic (LLVM TwoOperandFPData): 00011110 type 1 Rm opcode 10
// Rn Rd — FMUL 0000, FDIV 0001, FADD 0010, FSUB 0011.
// One-source (LLVM OneOperandFPData): FMOV 000, FABS 001, FNEG 010,
// FSQRT 011 at bits 17-15.
// Compare (LLVM BaseTwoOperandFPComparison): Rm, 001000 at 15-10; the zero
// form has Rm = 00000 and 01000 at 4-0.
// All words extracted mechanically from clang -target=aarch64 assembly.
import("arm/arm64.inc")

insn_fldr_s:
arm64_fldr_s(arm64_v0, arm64_x1, 4)
insn_fldr_d:
arm64_fldr_d(arm64_v2, arm64_x3, 8)
insn_fstr_s:
arm64_fstr_s(arm64_v5, arm64_x6, 0)
insn_fstr_d:
arm64_fstr_d(arm64_v7, arm64_x8, 16)
insn_fadd_s:
arm64_fadd_s(arm64_v2, arm64_v0, arm64_v1)
insn_fadd_d:
arm64_fadd_d(arm64_v2, arm64_v0, arm64_v1)
insn_fsub_d:
arm64_fsub_d(arm64_v3, arm64_v0, arm64_v1)
insn_fmul_d:
arm64_fmul_d(arm64_v4, arm64_v0, arm64_v1)
insn_fdiv_d:
arm64_fdiv_d(arm64_v5, arm64_v0, arm64_v1)
insn_fabs_s:
arm64_fabs_s(arm64_v6, arm64_v7)
insn_fabs_d:
arm64_fabs_d(arm64_v6, arm64_v7)
insn_fneg_d:
arm64_fneg_d(arm64_v8, arm64_v9)
insn_fsqrt_d:
arm64_fsqrt_d(arm64_v10, arm64_v11)
insn_fcmp_s:
arm64_fcmp_s(arm64_v0, arm64_v1)
insn_fcmp_d:
arm64_fcmp_d(arm64_v0, arm64_v1)
insn_fcmp_dz:
arm64_fcmp_z_d(arm64_v0)
insn_fmov_s:
arm64_fmov_s(arm64_v2, arm64_v0)
insn_fmov_d:
arm64_fmov_d(arm64_v2, arm64_v0)
insn_fcmpe_s:
arm64_fcmpe_s(arm64_v0, arm64_v1)
insn_fcmpe_d:
arm64_fcmpe_d(arm64_v2, arm64_v3)
insn_fcmpe_z_s:
arm64_fcmpe_z_s(arm64_v4)
insn_fcmpe_z_d:
arm64_fcmpe_z_d(arm64_v5)

defer {
    assert(load.u32(insn_fldr_s) == 0xbd400420, "ldr s0, [x1, #4]");
    assert(load.u32(insn_fldr_d) == 0xfd400462, "ldr d2, [x3, #8]");
    assert(load.u32(insn_fstr_s) == 0xbd0000c5, "str s5, [x6]");
    assert(load.u32(insn_fstr_d) == 0xfd000907, "str d7, [x8, #16]");
    assert(load.u32(insn_fadd_s) == 0x1e212802, "fadd s2, s0, s1");
    assert(load.u32(insn_fadd_d) == 0x1e612802, "fadd d2, d0, d1");
    assert(load.u32(insn_fsub_d) == 0x1e613803, "fsub d3, d0, d1");
    assert(load.u32(insn_fmul_d) == 0x1e610804, "fmul d4, d0, d1");
    assert(load.u32(insn_fdiv_d) == 0x1e611805, "fdiv d5, d0, d1");
    assert(load.u32(insn_fabs_s) == 0x1e20c0e6, "fabs s6, s7");
    assert(load.u32(insn_fabs_d) == 0x1e60c0e6, "fabs d6, d7");
    assert(load.u32(insn_fneg_d) == 0x1e614128, "fneg d8, d9");
    assert(load.u32(insn_fsqrt_d) == 0x1e61c16a, "fsqrt d10, d11");
    assert(load.u32(insn_fcmp_s) == 0x1e212000, "fcmp s0, s1");
    assert(load.u32(insn_fcmp_d) == 0x1e612000, "fcmp d0, d1");
    assert(load.u32(insn_fcmp_dz) == 0x1e602008, "fcmp d0, #0.0");
    assert(load.u32(insn_fmov_s) == 0x1e204002, "fmov s2, s0");
    assert(load.u32(insn_fmov_d) == 0x1e604002, "fmov d2, d0");
    assert(load.u32(insn_fcmpe_s) == 0x1e212010, "fcmpe s0, s1");
    assert(load.u32(insn_fcmpe_d) == 0x1e632050, "fcmpe d2, d3");
    assert(load.u32(insn_fcmpe_z_s) == 0x1e202098, "fcmpe s4, #0.0");
    assert(load.u32(insn_fcmpe_z_d) == 0x1e6020b8, "fcmpe d5, #0.0");
}
