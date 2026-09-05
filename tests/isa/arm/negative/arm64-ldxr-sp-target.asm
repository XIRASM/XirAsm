// Exclusive load Rt is a GPR (LLVM (outs GPR32:$Rt) / GPR64:$Rt): SP is not
// encodable, ZR is. Encoding 31 in the Rt field reads ZR, never SP.
// Expected failure: ldxr: register cannot be SP
import("arm/arm64.inc");

arm64_ldxr(arm64_sp, arm64_x0)
