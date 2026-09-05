// LDP with a W register first and an X register second is the reverse mixed
// form; both orders must be rejected.
// Expected failure: load/store pair: mixed W/X registers
import("arm/arm64.inc");

arm64_ldp(arm64_w0, arm64_x1, arm64_x2, 0)
