// 100K AArch64 instructions written in natural ISA text, for the same purpose as
// x86_100k.asm: measure frontend throughput on a large source.
//
// Every instruction here goes through the generated A64 macro library, so the
// number this fixture prints covers the whole path a DSL user takes -- matching
// the text, resolving operands, choosing an encoding form -- rather than a direct
// API call. That is the number worth watching when the DSL is optimised.
//
// The body mixes operand shapes on purpose: register and shifted-register
// arithmetic, scaled and unscaled addressing, an immediate, a pair load, a
// vector op, a lane op, a float op and a conditional branch. Each macro expands
// into a wrapper call, so the loop also exercises how macro expansion scales.
import("arm/a64-macros.inc")

for i in range(0, 10000) {
    add x0, x1, x2
    add x3, x0, x4, lsl #3
    ldr x5, [x6, #64]
    str x5, [x7, #128]
    ldp x8, x9, [sp, #16]
    movz w10, #0x1234
    add v0.4s, v1.4s, v2.4s
    fadd d0, d1, d2
    cmp x0, x3
    b.ne a64_100k_next
}

a64_100k_next:
emit.u8(0xc0);
