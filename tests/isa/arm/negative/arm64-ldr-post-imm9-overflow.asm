// Post-index writeback offsets are signed imm9 (-256..255); 300 does not fit.
// Expected failure: pre/post-index offset out of range -256..255
import("arm/arm64.inc");

arm64_ldr_post(arm64_x0, arm64_x1, 300)
