// SLI shift range is 0..T-1 (clang: "immediate must be an integer in range
// [0, 7]" for B lanes); 8 on B lanes must be rejected.
import("arm/arm64.inc")

arm64_sli(arm64_v0, arm64_v1, 8, arm64_arr_8b)
