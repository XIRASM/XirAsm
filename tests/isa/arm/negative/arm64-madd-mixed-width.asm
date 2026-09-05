// MADD's four registers share one width class (LLVM BaseMulAccum uses one
// multype for Rn/Rm and one addtype for Rd/Ra, both equal for MADD).
// Expected failure: madd: mixed W/X registers
import("arm/arm64.inc");

arm64_madd(arm64_x0, arm64_x1, arm64_w2, arm64_x3)
