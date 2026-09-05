// An acquire-release exclusive pair must be all-W or all-X (LLVM
// LDAXPW/LDAXPX take a single regtype for both Rt and Rt2).
// Expected failure: ldaxp: mixed W/X registers
import("arm/arm64.inc");

arm64_ldaxp(arm64_x0, arm64_w1, arm64_x2)
