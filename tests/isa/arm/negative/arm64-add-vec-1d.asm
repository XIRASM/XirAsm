// Vector ADD has no 1D arrangement (three-same D form is 2D only); 1D must
// be rejected.
import("arm/arm64.inc")

arm64_add_vec(arm64_v0, arm64_v1, arm64_v2, arm64_arr_1d)
