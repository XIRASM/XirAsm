// A64 PC-relative branches: B/BL (imm26), CBZ/CBNZ and B.cond (imm19),
// TBZ/TBNZ (imm14), plus register branches BR/BLR.
//
// Every branch goes through the placeholder + deferred patch mechanism, so a
// passing run proves forward and backward resolution for each family. Expected
// words below are hand-derived from the ARM ARM field layouts whose fixed bits
// and signed-displacement formula are pinned by the LLVM MC fixtures cited in
// include/arm/arm64.inc; the whole image is also disassembly-cross-checked.
import("arm/arm64.inc");

back_target:
arm64_nop()

// backward imm26: displacement -1 word
insn_b_back:
arm64_b("back_target")

// forward imm26: displacement +3 words (over two nops)
insn_b_fwd:
arm64_b("fwd_target")
arm64_nop()
arm64_nop()

fwd_target:
// forward imm26: displacement +2 words
insn_bl_fwd:
arm64_bl("bl_target")
arm64_nop()

bl_target:
// backward imm26: displacement -2 words
insn_bl_back:
arm64_bl("insn_bl_fwd")

// forward imm19: displacement +3 words
insn_cbz_fwd:
arm64_cbz(arm64_x5, "cbz_target")
arm64_nop()
arm64_nop()

cbz_target:
// backward imm19: displacement -3 words
insn_cbnz_back:
arm64_cbnz(arm64_x3, "insn_cbz_fwd")

// backward imm19 with ZR register (MC: cbz wzr, lbl is legal)
insn_cbz_wzr_back:
arm64_cbz(arm64_wzr, "cbz_target")

// backward imm19 with condition code lt
insn_bcond_back:
arm64_b_cond(arm64_cond_lt, "cbz_target")

// forward imm14: displacement +3 words
insn_tbz_fwd:
arm64_tbz(arm64_w5, 0, "tbz_target")
arm64_nop()
arm64_nop()

tbz_target:
// backward imm14 with b5 = 1 (bit 45 on an X register): displacement -3 words
insn_tbnz_back:
arm64_tbnz(arm64_x5, 45, "insn_tbz_fwd")

// register branches: no immediate field
insn_br_x16:
arm64_br(arm64_x16)

insn_blr_x30:
arm64_blr(arm64_x30)

defer {
    assert(load.u32(insn_b_back) == 0x17ffffff, "b backward -1 word");
    assert(load.u32(insn_b_fwd) == 0x14000003, "b forward +3 words");
    assert(load.u32(insn_bl_fwd) == 0x94000002, "bl forward +2 words");
    assert(load.u32(insn_bl_back) == 0x97fffffe, "bl backward -2 words");
    assert(load.u32(insn_cbz_fwd) == 0xb4000065, "cbz x5 forward +3 words");
    assert(load.u32(insn_cbnz_back) == 0xb5ffffa3, "cbnz x3 backward -3 words");
    assert(load.u32(insn_cbz_wzr_back) == 0x34ffffff, "cbz wzr backward -1 word");
    assert(load.u32(insn_bcond_back) == 0x54ffffcb, "b.lt backward -2 words");
    assert(load.u32(insn_tbz_fwd) == 0x36000065, "tbz w5, #0 forward +3 words");
    assert(load.u32(insn_tbnz_back) == 0xb76fffa5, "tbnz x5, #45 backward -3 words");
    assert(load.u32(insn_br_x16) == 0xd61f0200, "br x16");
    assert(load.u32(insn_blr_x30) == 0xd63f03c0, "blr x30");
}
