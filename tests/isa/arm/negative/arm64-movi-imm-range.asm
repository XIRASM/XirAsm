// The AdvSIMD modified immediate carries an 8-bit imm8; 256 must be
// rejected.
import("arm/arm64.inc")

arm64_movi_b(arm64_v0, arm64_arr_16b, 256)
