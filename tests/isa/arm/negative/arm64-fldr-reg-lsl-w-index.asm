// FP register-offset LSL/SXTX options require an X index register (LLVM
// roX: GPR64); a W index under LSL must be rejected.
import("arm/arm64.inc")

arm64_fldr_s_reg(arm64_v0, arm64_x1, arm64_w2, arm64_ldst_opt_lsl, false)
