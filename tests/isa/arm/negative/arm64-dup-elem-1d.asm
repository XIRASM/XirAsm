// DUP (element) does not support the 1D arrangement (clang rejects it);
// 1D must be rejected.
import("arm/arm64.inc")

arm64_dup_elem(arm64_v0, arm64_arr_1d, arm64_v1, 0)
