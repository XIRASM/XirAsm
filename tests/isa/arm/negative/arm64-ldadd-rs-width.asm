// LDADD's source (Rs) and result (Rt) registers share one width class
// (LLVM LDOPregister expands GPR32 pairs for W and GPR64 pairs for X).
// Expected failure: ldadd: mixed W/X registers
import("arm/arm64.inc");

arm64_ldadd(arm64_x0, arm64_w1, arm64_x2, arm64_order_plain)
