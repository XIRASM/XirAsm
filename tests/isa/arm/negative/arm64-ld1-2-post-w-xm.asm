// The post-index increment must be an X register (or xzr); a W register
// must be rejected.
import("arm/arm64.inc")

arm64_ld1_2_post(arm64_v0, arm64_v1, arm64_arr_8b, arm64_x2, arm64_w3)
