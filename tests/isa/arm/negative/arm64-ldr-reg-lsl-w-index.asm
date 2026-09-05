// Register-offset LDR with the LSL option requires an X index; a W index
// register is architecturally invalid for LSL/SXTX.
// Expected failure: register-offset: LSL/SXTX index requires an X register
import("arm/arm64.inc");

arm64_ldr_reg(arm64_x0, arm64_x1, arm64_w2, false)
