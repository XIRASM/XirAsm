// LDAR's data register Rt is a GPR (LLVM (outs GPR32:$Rt) / GPR64:$Rt):
// SP is not encodable, ZR is.
// Expected failure: ldar: register cannot be SP
import("arm/arm64.inc");

arm64_ldar(arm64_sp, arm64_x0)
