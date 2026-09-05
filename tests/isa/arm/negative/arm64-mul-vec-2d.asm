// Vector MUL exists only for B/H/S lanes (LLVM SIMDThreeSameVectorBHS);
// 2D must be rejected.
import("arm/arm64.inc")

arm64_mul_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_2d)
