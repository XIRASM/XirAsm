// Vector FSQRT is an FP two-misc op with S/D sizes only; 8B must be
// rejected.
import("arm/arm64.inc")

arm64_fsqrt_vec(arm64_v0, arm64_v1, arm64_arr_8b)
