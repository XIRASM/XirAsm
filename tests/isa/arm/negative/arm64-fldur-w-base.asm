// FP LDUR base is GPR64sp (X register or SP); a W base must be rejected.
import("arm/arm64.inc")

arm64_fldur_s(arm64_v0, arm64_w1, 0)
