// The unsigned-immediate field spans 0..4095 elements (32760 bytes for X).
// Expected failure: load/store offset out of range
import("arm/arm64.inc");

arm64_ldr_imm(arm64_x0, arm64_x1, 32768)
