// REV32 exists only for B/H arrangements (LLVM SIMDTwoVectorBH); 2D must
// be rejected.
import("arm/arm64.inc")

arm64_rev32_vec(arm64_v0, arm64_v1, arm64_arr_2d)
