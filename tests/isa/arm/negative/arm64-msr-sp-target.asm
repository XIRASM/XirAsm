// MSR (register) takes a GPR64 Rt: X registers and XZR are encodable, SP is
// not (LLVM (ins GPR64:$Rt)).
// Expected failure: msr: register cannot be SP
import("arm/arm64.inc");

arm64_msr_sys(arm64_sys_sctlr_el1, arm64_sp)
