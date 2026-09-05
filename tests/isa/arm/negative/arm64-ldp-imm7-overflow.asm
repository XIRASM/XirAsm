// LDP (X pair) offsets are signed 7-bit values scaled by 8 (-512..504).
// Expected failure: load/store pair offset out of range
import("arm/arm64.inc");

arm64_ldp(arm64_x0, arm64_x2, arm64_x1, 512)
