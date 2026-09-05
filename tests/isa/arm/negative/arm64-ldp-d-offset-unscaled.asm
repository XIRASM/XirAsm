// D pair offsets are multiples of 8; 4 must be rejected.
import("arm/arm64.inc")

arm64_ldp_d(arm64_v0, arm64_v1, arm64_x2, 4)
