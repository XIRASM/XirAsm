// Vector FP compares use S/D lanes only; 8B must be rejected.
import("arm/arm64.inc")

arm64_fcmeq_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_8b)
