// EXT with 8B arrangement indexes the 64-bit concatenation (0..7); 8 must
// be rejected (use 16B for 0..15).
import("arm/arm64.inc")

arm64_ext(arm64_v0, arm64_v1, arm64_v2, 8, arm64_arr_8b)
