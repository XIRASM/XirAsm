// 0x102 is not a repeating bitmask pattern, so it cannot encode as an A64
// logical immediate.
// Expected failure: value is not a valid A64 logical immediate
import("arm/arm64.inc");

arm64_orr_imm(arm64_x0, arm64_x1, 0x102)
