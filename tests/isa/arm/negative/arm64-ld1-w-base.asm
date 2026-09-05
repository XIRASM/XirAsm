// LD1 base is GPR64sp (X register or SP); a W base must be rejected.
import("arm/arm64.inc")

arm64_ld1(arm64_v0, arm64_arr_8b, arm64_w1)
