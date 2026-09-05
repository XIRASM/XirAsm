// FCVTZS destination is GPR32/GPR64 in LLVM (no ZR, no SP); wzr must be
// rejected even though the encoding field exists.
import("arm/arm64.inc")

arm64_fcvtzs_w_s(arm64_wzr, arm64_v0)
