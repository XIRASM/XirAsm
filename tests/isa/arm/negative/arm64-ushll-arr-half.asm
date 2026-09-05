// USHLL reads the low half (64-bit source arrangement); a 16B source needs
// the USHLL2 variant and must be rejected here.
import("arm/arm64.inc")

arm64_ushll(arm64_v0, arm64_v1, 3, arm64_arr_16b)
