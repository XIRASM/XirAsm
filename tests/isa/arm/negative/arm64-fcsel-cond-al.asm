// FCSEL follows the established conditional-family rule: only the fourteen
// real condition codes (0..13) are accepted, matching the CSEL/CCMP emitters.
import("arm/arm64.inc")

arm64_fcsel_d(arm64_v0, arm64_v1, arm64_v2, 14)
