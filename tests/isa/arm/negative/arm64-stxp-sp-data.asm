// Pair data registers are GPRs (LLVM (outs GPR32:$Ws), (ins regtype:$Rt,
// regtype:$Rt2)): SP is not encodable, ZR is.
// Expected failure: stxp: register cannot be SP
import("arm/arm64.inc");

arm64_stxp(arm64_w0, arm64_sp, arm64_x1, arm64_x2)
