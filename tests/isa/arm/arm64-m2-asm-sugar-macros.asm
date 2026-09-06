// arm64_asm text adapter: one representative per implemented family.
// The sugar parses with match.tokens and dispatches to the checked emitters;
// these asserts pin that dispatch end to end. Immediates are written without
// the '#' prefix (see include/arm/arm64/asm.inc).
import("arm/arm64-macros.inc");

insn_s_nop:
nop

insn_s_ret:
ret

insn_s_movz:
movz x0, 42

insn_s_movz_lsl:
movz x1, 42, lsl 16

insn_s_movk:
movk x2, 0x1234, lsl 48

insn_s_movn:
movn w3, 1

insn_s_mov_reg:
mov x4, x5

insn_s_add_imm:
add x6, x7, 1

insn_s_add_imm_lsl:
add w8, w9, 1, lsl 12

insn_s_cmp_imm:
subs xzr, x10, 1

insn_s_add_reg:
add x11, x12, x13

insn_s_add_reg_lsl:
add x14, x15, x16, lsl 3

insn_s_add_ext:
add x17, x18, w19, uxtb

insn_s_add_ext_imm:
add x20, x21, w22, uxtb 2

insn_s_orr_imm:
orr x23, x24, 0xff

insn_s_and_imm:
and w25, w26, 0x80008000

insn_s_cbz:
cbz x27, s_cbz_target
arm64_nop()
s_cbz_target:

insn_s_tbz:
tbz x28, 45, s_tbz_target
arm64_nop()
s_tbz_target:

insn_s_bcond:
b.eq s_bcond_target
arm64_nop()
s_bcond_target:

insn_s_b_back:
b insn_s_b_back

insn_s_blr:
blr x30

defer {
    assert(load.u32(insn_s_nop) == 0xd503201f, "asm: nop");
    assert(load.u32(insn_s_ret) == 0xd65f03c0, "asm: ret");
    assert(load.u32(insn_s_movz) == 0xd2800540, "asm: movz x0, 42");
    assert(load.u32(insn_s_movz_lsl) == 0xd2a00541, "asm: movz x1, 42, lsl 16");
    assert(load.u32(insn_s_movk) == 0xf2e24682, "asm: movk x2, 0x1234, lsl 48");
    assert(load.u32(insn_s_movn) == 0x12800023, "asm: movn w3, 1");
    assert(load.u32(insn_s_mov_reg) == 0xaa0503e4, "asm: mov x4, x5");
    assert(load.u32(insn_s_add_imm) == 0x910004e6, "asm: add x6, x7, 1");
    assert(load.u32(insn_s_add_imm_lsl) == 0x11400528, "asm: add w8, w9, 1, lsl 12");
    assert(load.u32(insn_s_cmp_imm) == 0xf100055f, "asm: subs xzr, x10, 1");
    assert(load.u32(insn_s_add_reg) == 0x8b0d018b, "asm: add x11, x12, x13");
    assert(load.u32(insn_s_add_reg_lsl) == 0x8b100dee, "asm: add x14, x15, x16, lsl 3");
    assert(load.u32(insn_s_add_ext) == 0x8b330251, "asm: add x17, x18, w19, uxtb");
    assert(load.u32(insn_s_add_ext_imm) == 0x8b360ab4, "asm: add x20, x21, w22, uxtb 2");
    assert(load.u32(insn_s_orr_imm) == 0xb2401f17, "asm: orr x23, x24, 0xff");
    assert(load.u32(insn_s_and_imm) == 0x12018359, "asm: and w25, w26, 0x80008000");
    assert(load.u32(insn_s_cbz) == 0xb400005b, "asm: cbz x27, +2 words");
    assert(load.u32(insn_s_tbz) == 0xb668005c, "asm: tbz x28, 45, +2 words");
    assert(load.u32(insn_s_bcond) == 0x54000040, "asm: b.eq +1 word");
    assert(load.u32(insn_s_b_back) == 0x14000000, "asm: b self");
    assert(load.u32(insn_s_blr) == 0xd63f03c0, "asm: blr x30");
}
