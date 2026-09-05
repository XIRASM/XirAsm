// Vector permutes have no 1D arrangement (clang rejects it); 1D must be
// rejected.
import("arm/arm64.inc")

arm64_uzp1(arm64_v0, arm64_v1, arm64_v2, arm64_arr_1d)
