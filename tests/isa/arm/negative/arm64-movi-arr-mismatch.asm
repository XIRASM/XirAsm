// MOVI halfword form requires a 4H/8H arrangement; 4S must be rejected.
import("arm/arm64.inc")

arm64_movi_h(arm64_v0, arm64_arr_4s, 0x12, false)
