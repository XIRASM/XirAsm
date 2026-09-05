// Vector integer compares have no 1D arrangement; 1D must be rejected.
import("arm/arm64.inc")

arm64_cmeq_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_1d)
