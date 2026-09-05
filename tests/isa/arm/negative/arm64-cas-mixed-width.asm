// CAS compares and swaps within one width class (LLVM BaseCAS uses a single
// RegisterClass RC for both Rs and Rt); a W/X mix is invalid.
// Expected failure: cas: mixed W/X registers
import("arm/arm64.inc");

arm64_cas(arm64_w0, arm64_x1, arm64_x2, arm64_order_plain)
