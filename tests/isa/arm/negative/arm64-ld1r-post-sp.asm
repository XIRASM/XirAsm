// The post-index increment register cannot be SP (only an X register or
// xzr for the #size immediate form); SP must be rejected.
import("arm/arm64.inc")

arm64_ld1r_post(arm64_v0, arm64_arr_8b, arm64_x1, arm64_sp)
