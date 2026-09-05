// Vector FP arithmetic has no B/H arrangements in the S/D-only API (H is
// FEAT_FP16, out of scope); 8B must be rejected.
import("arm/arm64.inc")

arm64_fadd_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_8b)
