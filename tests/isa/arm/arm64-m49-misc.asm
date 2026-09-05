// M4.9: coverage-gap batch — no-allocate pairs, data-processing (1 source),
// and exception generation.
//
// No-allocate pair (LLVM BaseLoadStorePairNoAlloc): opc(31-30) 101(29-27)
// V(26) 000(25-23) L(22) imm7(21-15) Rt2(14-10) Rn(9-5) Rt(4-0).
// Data-processing 1-source (LLVM BaseOneOperandData): sf(31) 1(30) 0(29)
// 11010110(28-21) 0(20-16) opc(15-10) Rn Rd — opc 000000 RBIT / 000001
// REV16 / 000010 REV32(X)+REV(W) / 000011 REV(X) / 000100 CLZ / 000101 CLS
// (S = 0 for every integer form, per the defs).
// Exception generation (LLVM ExceptionGeneration): 11010100(31-24) op1(23-21)
// imm16(20-5) 000(4-2) ll(1-0); SVC 000/01, HVC 000/10, SMC 000/11,
// BRK 001/00, HLT 010/00.
// All words extracted mechanically from clang -target=aarch64 assembly.
import("arm/arm64.inc")

insn_rbit_w:
arm64_rbit(arm64_w0, arm64_w1)
insn_rbit_x:
arm64_rbit(arm64_x0, arm64_x1)
insn_rev16_w:
arm64_rev16(arm64_w0, arm64_w1)
insn_rev16_x:
arm64_rev16(arm64_x0, arm64_x1)
insn_rev32_x:
arm64_rev32(arm64_x0, arm64_x1)
insn_rev_w:
arm64_rev(arm64_w0, arm64_w1)
insn_rev_x:
arm64_rev(arm64_x0, arm64_x1)
insn_clz_w:
arm64_clz(arm64_w0, arm64_w1)
insn_clz_x:
arm64_clz(arm64_x0, arm64_x1)
insn_cls_w:
arm64_cls(arm64_w0, arm64_w1)
insn_cls_x:
arm64_cls(arm64_x0, arm64_x1)
insn_ldnp_w:
arm64_ldnp(arm64_w0, arm64_w1, arm64_x2, 0)
insn_stnp_w:
arm64_stnp(arm64_w0, arm64_w1, arm64_x2, 0)
insn_ldnp_x:
arm64_ldnp(arm64_x0, arm64_x1, arm64_x2, 0)
insn_svc:
arm64_svc(0x123)
insn_hvc:
arm64_hvc(1)
insn_smc:
arm64_smc(0)
insn_brk:
arm64_brk(4)
insn_hlt:
arm64_hlt(2)

defer {
    assert(load.u32(insn_rbit_w) == 0x5ac00020, "rbit w0, w1");
    assert(load.u32(insn_rbit_x) == 0xdac00020, "rbit x0, w1");
    assert(load.u32(insn_rev16_w) == 0x5ac00420, "rev16 w0, w1");
    assert(load.u32(insn_rev16_x) == 0xdac00420, "rev16 x0, w1");
    assert(load.u32(insn_rev32_x) == 0xdac00820, "rev32 x0, w1");
    assert(load.u32(insn_rev_w) == 0x5ac00820, "rev w0, w1");
    assert(load.u32(insn_rev_x) == 0xdac00c20, "rev x0, w1");
    assert(load.u32(insn_clz_w) == 0x5ac01020, "clz w0, w1");
    assert(load.u32(insn_clz_x) == 0xdac01020, "clz x0, w1");
    assert(load.u32(insn_cls_w) == 0x5ac01420, "cls w0, w1");
    assert(load.u32(insn_cls_x) == 0xdac01420, "cls x0, w1");
    assert(load.u32(insn_ldnp_w) == 0x28400440, "ldnp w0, w1, [x2]");
    assert(load.u32(insn_stnp_w) == 0x28000440, "stnp w0, w1, [x2]");
    assert(load.u32(insn_ldnp_x) == 0xa8400440, "ldnp x0, x1, [x2]");
    assert(load.u32(insn_svc) == 0xd4002461, "svc #0x123");
    assert(load.u32(insn_hvc) == 0xd4000022, "hvc #1");
    assert(load.u32(insn_smc) == 0xd4000003, "smc #0");
    assert(load.u32(insn_brk) == 0xd4200080, "brk #4");
    assert(load.u32(insn_hlt) == 0xd4400040, "hlt #2");
}
