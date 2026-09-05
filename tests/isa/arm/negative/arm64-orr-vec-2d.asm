// Vector logical ops are bitwise and define only 8B/16B arrangements
// (clang rejects .2D); 2D must be rejected.
import("arm/arm64.inc")

arm64_orr_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_2d)
