// FCSEL requires V registers on all three register operands; a W register
// must be rejected (LLVM FCSEL Srrr/Drrr: FPR32/FPR64 only).
import("arm/arm64.inc")

arm64_fcsel_s(arm64_w0, arm64_v1, arm64_v2, arm64_cond_eq)
