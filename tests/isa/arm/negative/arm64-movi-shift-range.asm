// MOVI word shift form accepts shift 0..3 (LSL 0/8/16/24); 4 must be
// rejected.
import("arm/arm64.inc")

arm64_movi_s(arm64_v0, arm64_arr_4s, 0x12, 4)
