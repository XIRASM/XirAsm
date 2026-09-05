// An exclusive pair must be all-W or all-X (LLVM LDXPW/LDXPX take a single
// regtype for both Rt and Rt2); a mixed W/X pair is unencodable, matching
// the LDP/STP rule.
// Expected failure: ldxp: mixed W/X registers
import("arm/arm64.inc");

arm64_ldxp(arm64_w0, arm64_x1, arm64_x2)
