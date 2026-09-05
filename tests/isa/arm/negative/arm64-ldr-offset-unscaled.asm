// LDR (unsigned immediate) offsets are scaled by the element size: an X load
// only accepts multiples of 8.
// Expected failure: load/store offset must be a multiple of the element size (8
import("arm/arm64.inc");

arm64_ldr_imm(arm64_x0, arm64_x1, 4)
