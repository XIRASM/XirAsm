// SIMD pair load/store base is GPR64sp (X register or SP); a W base must be
// rejected.
import("arm/arm64.inc")

arm64_ldp_s(arm64_v0, arm64_v1, arm64_w2, 0)
