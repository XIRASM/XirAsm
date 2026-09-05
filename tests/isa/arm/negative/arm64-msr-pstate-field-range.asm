// The PState field is 6 bits (op1<<3 | op2); 64 is out of range.
// Expected failure: msr: pstate field out of range
import("arm/arm64.inc");

arm64_msr_pstate(64, 0)
