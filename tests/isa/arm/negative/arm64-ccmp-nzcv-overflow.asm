// The CCMP nzcv field spans 0..15.
// Expected failure: conditional compare nzcv out of range
import("arm/arm64.inc");

arm64_ccmp_imm(arm64_x0, 1, 16, arm64_cond_eq)
