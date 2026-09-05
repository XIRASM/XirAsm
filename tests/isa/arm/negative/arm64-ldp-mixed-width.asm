// LDP/STP pair registers must be the same width (both W or both X); a mixed
// X0/W1 pair is architecturally invalid.
// Expected failure: load/store pair: mixed W/X registers
import("arm/arm64.inc");

arm64_ldp(arm64_x0, arm64_w1, arm64_x2, 0)
