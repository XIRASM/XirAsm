// A64 basics: register model, NOP/RET, move-wide immediate (MOVZ/MOVK).
//
// Each emitter call is followed by a deferred self-check against the
// architecture encoding. Golden bytes are cited from LLVM MC fixtures;
// the build.zig fixture pins the complete image byte for byte.
import("arm/arm64.inc");

insn_nop:
arm64_nop()

insn_ret:
arm64_ret()

// movz w2, #0, lsl #16      (llvm/test/MC/AArch64/basic-a64-instructions.s)
insn_movz_w2_shift16:
arm64_movz(arm64_w2, 0, 16)

// movk xzr, #4321, lsl #48  (basic-a64-instructions.s; Rd 31 = xzr, sf 1)
insn_movk_xzr_shift48:
arm64_movk(arm64_xzr, 4321, 48)

// movk x1, #1, lsl #16      (basic-a64-instructions.s)
insn_movk_x1_shift16:
arm64_movk(arm64_x1, 1, 16)

// Derived forms, cross-checked with independent disassembly:
//   movz x0, #42     = 0xd2800000 | 42 << 5
//   movz w0, #42     = 0x52800000 | 42 << 5
//   movk w3, #0x1234 = 0x72800000 | 0x1234 << 5 | 3
//   movz x30, #0xffff, lsl #48
//   movz wzr, #1     (Rd 31, sf 0)
insn_movz_x0:
arm64_movz(arm64_x0, 42, 0)

insn_movz_w0:
arm64_movz(arm64_w0, 42, 0)

insn_movk_w3:
arm64_movk(arm64_w3, 0x1234, 0)

insn_movz_x30_hw3:
arm64_movz(arm64_x30, 0xffff, 48)

insn_movz_wzr:
arm64_movz(arm64_wzr, 1, 0)

defer {
    assert(load.u32(insn_nop) == 0xd503201f, "nop encoding");
    assert(load.u32(insn_ret) == 0xd65f03c0, "ret encoding");
    assert(load.u32(insn_movz_w2_shift16) == 0x52a00002, "movz w2, #0, lsl #16");
    assert(load.u32(insn_movk_xzr_shift48) == 0xf2e21c3f, "movk xzr, #4321, lsl #48");
    assert(load.u32(insn_movk_x1_shift16) == 0xf2a00021, "movk x1, #1, lsl #16");
    assert(load.u32(insn_movz_x0) == 0xd2800540, "movz x0, #42");
    assert(load.u32(insn_movz_w0) == 0x52800540, "movz w0, #42");
    assert(load.u32(insn_movk_w3) == 0x72824683, "movk w3, #0x1234");
    assert(load.u32(insn_movz_x30_hw3) == 0xd2fffffe, "movz x30, #0xffff, lsl #48");
    assert(load.u32(insn_movz_wzr) == 0x5280003f, "movz wzr, #1");
}
