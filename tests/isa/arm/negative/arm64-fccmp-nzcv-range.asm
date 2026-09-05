// FCCMP nzcv is a 4-bit field (imm32_0_15 in LLVM); 16 must be rejected.
import("arm/arm64.inc")

arm64_fccmp_s(arm64_v0, arm64_v1, 16, arm64_cond_ne)
