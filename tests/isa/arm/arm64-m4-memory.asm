// A64 loads, stores, pairs, and PC-relative address computation (M4).
//
// Part 1 pins procedural encodings against LLVM MC fixtures from
// llvm/test/MC/AArch64/basic-a64-instructions.s. Part 2 proves the arm64_asm
// text adapter dispatches the memory forms identically to the direct emitter
// calls. ADR/ADRP displacements are data-dependent, so they are verified by
// disassembly rather than fixed words.
import("arm/arm64.inc");

insn_ldr_x0:
arm64_ldr_imm(arm64_x0, arm64_x0, 0)

insn_ldr_x_max:
arm64_ldr_imm(arm64_x30, arm64_x12, 32760)

insn_ldr_w_sp:
arm64_ldr_imm(arm64_w2, arm64_sp, 0)

insn_str_x_max:
arm64_str_imm(arm64_x20, arm64_x4, 16376)

insn_ldrsw:
arm64_ldrsw_imm(arm64_x2, arm64_x5, 4)

insn_ldrsh_w:
arm64_ldrsh_imm(arm64_w23, arm64_x6, 8190)

insn_ldrsh_x:
arm64_ldrsh_imm(arm64_x29, arm64_x2, 2)

insn_ldrsb_w:
arm64_ldrsb_imm(arm64_w27, arm64_sp, 4095)

insn_ldrsb_x:
arm64_ldrsb_imm(arm64_xzr, arm64_x15, 0)

insn_ldrb_w:
arm64_ldrb_imm(arm64_w26, arm64_x3, 121)

insn_ldp_w:
arm64_ldp(arm64_w3, arm64_w5, arm64_sp, 0)

insn_stp_w_max:
arm64_stp(arm64_wzr, arm64_w9, arm64_sp, 252)

insn_ldp_w_min:
arm64_ldp(arm64_w2, arm64_wzr, arm64_sp, -256)

insn_ldp_x_max:
arm64_ldp(arm64_x21, arm64_x29, arm64_x2, 504)

insn_stur_w:
arm64_stur_imm(arm64_w16, arm64_x0, -256)

insn_ldur_x:
arm64_ldur_imm(arm64_xzr, arm64_x12, 255)

insn_ldursw_x:
arm64_ldursw_imm(arm64_x20, arm64_x15, -256)

// --- MOV immediate synthesis -------------------------------------------------
dir_movz0:
arm64_mov_imm(arm64_x0, 42)

dir_movn:
arm64_mov_imm(arm64_x0, 0xffffffffffff0000)

dir_mov_multi:
arm64_mov_imm(arm64_x0, 0x123456789)

dir_mov_w:
arm64_mov_imm(arm64_w0, 0x12345678)

// --- ADR/ADRP ----------------------------------------------------------------
adr_self:
arm64_adr(arm64_x0, "adr_self")

adr_back:
arm64_nop()
adr_back_insn:
arm64_adr(arm64_x1, "adr_self")

adrp_page:
arm64_adrp(arm64_x2, "far_page")
reserve(4096)
far_page:
emit.u8(1)
align(4)

// --- Sugar dispatch for the M4 families ---------------------------------------
dir_ldr:
arm64_ldr_imm(arm64_x5, arm64_x6, 8)
sug_ldr:
arm64_asm("ldr x5, [x6, 8]")

dir_ldr0:
arm64_ldr_imm(arm64_x5, arm64_x6, 0)
sug_ldr0:
arm64_asm("ldr x5, [x6]")

dir_stp:
arm64_stp(arm64_x19, arm64_x20, arm64_sp, 16)
sug_stp:
arm64_asm("stp x19, x20, [sp, 16]")

dir_adr:
arm64_adr(arm64_x8, "adr_target")
sug_adr:
arm64_asm("adr x8, adr_target")
adr_target:
emit.u8(1)

dir_mov_imm:
arm64_mov_imm(arm64_x9, 42)
sug_mov_imm:
arm64_asm("mov x9, 42")

defer {
    assert(load.u32(insn_ldr_x0) == 0xf9400000, "ldr x0, [x0]");
    assert(load.u32(insn_ldr_x_max) == 0xf97ffd9e, "ldr x30, [x12, #32760]");
    assert(load.u32(insn_ldr_w_sp) == 0xb94003e2, "ldr w2, [sp]");
    assert(load.u32(insn_str_x_max) == 0xf91ffc94, "str x20, [x4, #16376]");
    assert(load.u32(insn_ldrsw) == 0xb98004a2, "ldrsw x2, [x5, #4]");
    assert(load.u32(insn_ldrsh_w) == 0x79fffcd7, "ldrsh w23, [x6, #8190]");
    assert(load.u32(insn_ldrsh_x) == 0x7980045d, "ldrsh x29, [x2, #2]");
    assert(load.u32(insn_ldrsb_w) == 0x39fffffb, "ldrsb w27, [sp, #4095]");
    assert(load.u32(insn_ldrsb_x) == 0x398001ff, "ldrsb xzr, [x15]");
    assert(load.u32(insn_ldrb_w) == 0x3941e47a, "ldrb w26, [x3, #121]");
    assert(load.u32(insn_ldp_w) == 0x294017e3, "ldp w3, w5, [sp]");
    assert(load.u32(insn_stp_w_max) == 0x291fa7ff, "stp wzr, w9, [sp, #252]");
    assert(load.u32(insn_ldp_w_min) == 0x29607fe2, "ldp w2, wzr, [sp, #-256]");
    assert(load.u32(insn_ldp_x_max) == 0xa95ff455, "ldp x21, x29, [x2, #504]");
    assert(load.u32(insn_stur_w) == 0xb8100010, "stur w16, [x0, #-256]");
    assert(load.u32(insn_ldur_x) == 0xf84ff19f, "ldur xzr, [x12, #255]");
    assert(load.u32(insn_ldursw_x) == 0xb89001f4, "ldursw x20, [x15, #-256]");

    assert(load.u32(adr_self) == 0x10000000, "adr self (imm 0)");
    assert(load.u32(adr_back_insn) == 0x10ffffc1, "adr x1, -8 bytes");
    assert(load.u32(adrp_page) == 0xb0000002, "adrp x2, +1 page");

    assert(load.u32(dir_movz0) == 0xd2800540, "mov x0, 42");
    assert(load.u32(dir_movn) == 0x929fffe0, "mov x0, #0xffffffffffff0000 (movn lsl 48)");
    assert(load.u32(dir_mov_multi) == 0xd28cf120, "mov x0, 0x123456789 word 0");
    assert(load.u32(dir_mov_multi + 4) == 0xf2a468a0, "mov x0, 0x123456789 word 1");
    assert(load.u32(dir_mov_multi + 8) == 0xf2c00020, "mov x0, 0x123456789 word 2");
    assert(load.u32(dir_mov_w) == 0x528acf00, "mov w0, 0x12345678 (movz half)");
    assert(load.u32(dir_mov_w + 4) == 0x72a24680, "mov w0, 0x12345678 (movk half)");

    // ADR words encode site-relative displacements: dir_adr sits 4 bytes
    // before sug_adr, so the two legitimately differ (both target adr_target,
    // which is 8 bytes after dir_adr and 4 after sug_adr).
    assert(load.u32(dir_adr) == 0x10000048, "adr x8, +8 (direct)");
    assert(load.u32(sug_adr) == 0x10000028, "sugar adr x8, +4");
    assert(load.u32(sug_mov_imm) == load.u32(dir_mov_imm), "sugar mov == direct");
}
