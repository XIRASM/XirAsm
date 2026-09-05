// The exclusive base Rn is GPR64sp0 (LLVM (ins GPR64sp0:$Rn)): an X register
// or SP. Encoding 31 in the Rn field reads SP, so ZR is not encodable.
// Expected failure: ldxr: base cannot be ZR (reads SP)
import("arm/arm64.inc");

arm64_ldxr(arm64_x0, arm64_xzr)
