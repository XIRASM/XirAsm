// AArch64 (A64) instruction encoding layer — module entry.
//
// XIRASM has no A64 backend; this layer emits A64 instruction words as data
// through `emit.u32` (little-endian words, matching A64 memory layout).
// Importing this file only declares constants and emitters; bytes appear when
// the emitters are called.
//
// Module map (import order follows dependencies):
//   arm64/regs.inc    register constants, identity checks, name table
//   arm64/bits.inc    bit math: field fitting, rotate, logical immediate codec
//   arm64/logic.inc   logical ops (register/immediate), bitfield, shift aliases
//   arm64/move.inc    move-wide immediate (MOVZ/MOVK/MOVN), MOV register
//   arm64/branch.inc  NOP/RET, condition codes, all PC-relative branches
//   arm64/alu.inc     add/subtract: immediate, shifted register, extended
//   arm64/cond.inc    conditional compare/select (CCMP/CCMN/CSEL family)
//   arm64/memory.inc  unscaled/pair/register-offset/literal loads and stores
//   arm64/sync.inc    exclusive and ordered load/store (M4.6)
//   arm64/system.inc  barriers, hints, BTI, MRS/MSR, PState
//   arm64/fp.inc      scalar floating point (M5a)
//   arm64/simd.inc    Advanced SIMD vector operations (M5b)
//   arm64/sysreg_table.inc  TLBI/DC/AT/IC and core SysReg encoding table
//   arm64/asm.inc     arm64_asm text adapter over the emitters
//
// Register model (see arm64/regs.inc):
//   register constants pack number (bits 4..0), width (bit 5) and SP identity
//   (bit 6) into one integer, so arm64_sp and arm64_xzr are distinct names for
//   the shared encoding 31.
//
// Truth sources:
//   - ARM ARM chapter C6: architecture semantics, final arbiter.
//   - LLVM lib/Target/AArch64: bit layouts and emitter/fixup behavior.
//   - LLVM llvm/test/MC/AArch64: expected-byte fixtures, cited per emitter.

import("arm64/regs.inc");
import("arm64/bits.inc");
import("arm64/logic.inc");
import("arm64/cond.inc");
import("arm64/move.inc");
import("arm64/branch.inc");
import("arm64/memory.inc");
import("arm64/alu.inc");
import("arm64/sync.inc");
import("arm64/system.inc");
import("arm64/fp.inc");
import("arm64/simd.inc");
import("arm64/sysreg_table.inc");
import("arm64/asm.inc");
