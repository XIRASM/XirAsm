// The extend form's imm3 shift spans 0..4.
// Expected failure: add/sub extended imm3 must be 0..4
import("arm/arm64.inc");

arm64_add_ext(arm64_x0, arm64_x1, arm64_w2, arm64_uxtb, 5)
