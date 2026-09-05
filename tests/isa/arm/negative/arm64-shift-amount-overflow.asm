// A 32-bit shifted-register form only allows shift amounts 0..31.
// Expected failure: add/sub shifted register amount out of range
import("arm/arm64.inc");

arm64_add_reg(arm64_w0, arm64_w1, arm64_w2, 0, 32)
