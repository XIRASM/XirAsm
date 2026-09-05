// Multi-register LD1 reads sequential registers (Rt+1 mod 32); a
// non-sequential pair must be rejected for clear diagnostics.
import("arm/arm64.inc")

arm64_ld1_2(arm64_v0, arm64_v5, arm64_arr_8b, arm64_x1)
