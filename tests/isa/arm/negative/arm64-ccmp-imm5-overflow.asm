// The CCMP imm5 field spans 0..31.
// Expected failure: conditional compare imm5/register number out of range
import("arm/arm64.inc");

arm64_ccmp_imm(arm64_x0, 32, 0, arm64_cond_eq)
