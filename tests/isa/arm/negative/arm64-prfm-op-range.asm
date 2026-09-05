// The PRFM Rt field carries the 5-bit prfop; values above 31 have no encoding.
// Expected failure: prfm operation out of range
import("arm/arm64.inc");

arm64_prfm_reg(arm64_x0, 32, arm64_x1, arm64_ldst_opt_lsl, false)
