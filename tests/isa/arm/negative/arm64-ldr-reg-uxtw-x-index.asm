// Register-offset loads with the UXTW/SXTW options require a W index; an X
// index register is architecturally invalid for UXTW/SXTW.
// Expected failure: register-offset: UXTW/SXTW index requires a W register
import("arm/arm64.inc");

arm64_ldrsw_reg(arm64_x0, arm64_x1, arm64_x2, arm64_ldst_opt_uxtw, false)
