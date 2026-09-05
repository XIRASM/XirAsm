// The STXR status register Ws is a W register (LLVM StoreExclusive declares
// (outs GPR32:$Ws)); an X status register is architecturally invalid.
// Expected failure: stxr status must be a W register
import("arm/arm64.inc");

arm64_stxr(arm64_x0, arm64_x1, arm64_x2)
