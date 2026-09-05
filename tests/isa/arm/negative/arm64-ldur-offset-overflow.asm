// LDUR offsets are raw signed 9-bit values (-256..255).
// Expected failure: load/store unscaled offset out of range -256..255
import("arm/arm64.inc");

arm64_ldur_imm(arm64_x0, arm64_x1, 300)
