// ADD (immediate) imm12 spans 0..4095.
// Expected failure: add/sub imm12 out of range
import("arm/arm64.inc");

arm64_add_imm(arm64_x0, arm64_x1, 4096, 0)
