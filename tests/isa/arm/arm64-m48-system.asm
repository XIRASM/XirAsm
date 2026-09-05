// M4.8: system instructions — barriers, hints, BTI, and the CRC32 family.
//
// Barrier/hint layout (LLVM HintI / Barrier classes): 1101010100(31-22)
// 0(21) 00(20-19) 0011(18-15) CRm(11-8) opc(7-5) 11111(4-0); DMB opc = 0b101,
// DSB opc = 0b100, ISB opc = 0b110 (CRm = 15), HINT opc = 0b000 with
// imm(11-5). BTI is HINT imm 32/34/36/38 (any/c/j/jc).
// CRC32 (LLVM BaseCRC32): sf(31) 0011010110(30-21) Rm(20-16) 010(15-13)
// C(12) sz(11-10) Rn(9-5) Rd(4-0).
// All words extracted mechanically from clang -target=aarch64 assembly.
import("arm/arm64.inc")

insn_dmb_sy:
arm64_dmb(arm64_barrier_sy)
insn_dmb_ish:
arm64_dmb(arm64_barrier_ish)
insn_dmb_oshld:
arm64_dmb(arm64_barrier_oshld)
insn_dsb_sy:
arm64_dsb(arm64_barrier_sy)
insn_dsb_ld:
arm64_dsb(arm64_barrier_ld)
insn_isb:
arm64_isb()
insn_hint_nop:
arm64_hint(0)
insn_hint_5:
arm64_hint(5)
insn_bti:
arm64_bti(arm64_bti_none)
insn_bti_c:
arm64_bti(arm64_bti_c)
insn_bti_j:
arm64_bti(arm64_bti_j)
insn_bti_jc:
arm64_bti(arm64_bti_jc)
insn_crc32b:
arm64_crc32b(arm64_w0, arm64_w1, arm64_w2)
insn_crc32h:
arm64_crc32h(arm64_w3, arm64_w4, arm64_w5)
insn_crc32w:
arm64_crc32w(arm64_w6, arm64_w7, arm64_w8)
insn_crc32x:
arm64_crc32x(arm64_w0, arm64_w1, arm64_x2)
insn_crc32cb:
arm64_crc32cb(arm64_w9, arm64_w10, arm64_w11)
insn_crc32ch:
arm64_crc32ch(arm64_w12, arm64_w13, arm64_w14)
insn_crc32cw:
arm64_crc32cw(arm64_w15, arm64_w16, arm64_w17)
insn_crc32cx:
arm64_crc32cx(arm64_w18, arm64_w19, arm64_x20)

defer {
    assert(load.u32(insn_dmb_sy) == 0xd5033fbf, "dmb sy");
    assert(load.u32(insn_dmb_ish) == 0xd5033bbf, "dmb ish");
    assert(load.u32(insn_dmb_oshld) == 0xd50331bf, "dmb oshld");
    assert(load.u32(insn_dsb_sy) == 0xd5033f9f, "dsb sy");
    assert(load.u32(insn_dsb_ld) == 0xd5033d9f, "dsb ld");
    assert(load.u32(insn_isb) == 0xd5033fdf, "isb");
    assert(load.u32(insn_hint_nop) == 0xd503201f, "hint #0 (nop)");
    assert(load.u32(insn_hint_5) == 0xd50320bf, "hint #5 (sevl)");
    assert(load.u32(insn_bti) == 0xd503241f, "bti");
    assert(load.u32(insn_bti_c) == 0xd503245f, "bti c");
    assert(load.u32(insn_bti_j) == 0xd503249f, "bti j");
    assert(load.u32(insn_bti_jc) == 0xd50324df, "bti jc");
    assert(load.u32(insn_crc32b) == 0x1ac24020, "crc32b w0, w1, w2");
    assert(load.u32(insn_crc32h) == 0x1ac54483, "crc32h w3, w4, w5");
    assert(load.u32(insn_crc32w) == 0x1ac848e6, "crc32w w6, w7, w8");
    assert(load.u32(insn_crc32x) == 0x9ac24c20, "crc32x w0, w1, x2");
    assert(load.u32(insn_crc32cb) == 0x1acb5149, "crc32cb w9, w10, w11");
    assert(load.u32(insn_crc32ch) == 0x1ace55ac, "crc32ch w12, w13, w14");
    assert(load.u32(insn_crc32cw) == 0x1ad15a0f, "crc32cw w15, w16, w17");
    assert(load.u32(insn_crc32cx) == 0x9ad45e72, "crc32cx w18, w19, x20");
}
