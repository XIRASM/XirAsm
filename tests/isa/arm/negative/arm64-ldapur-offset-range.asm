// The LDAPUR offset is unscaled imm9 (-256..255); 300 does not fit.
// Expected failure: ldapur: offset out of range -256..255
import("arm/arm64.inc");

arm64_ldapur(arm64_x0, arm64_x1, 300)
