// SQDMULH exists only for H/S lanes (LLVM SIMDThreeSameVectorHS); 2D must
// be rejected.
import("arm/arm64.inc")

arm64_sqdmulh_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_2d)
