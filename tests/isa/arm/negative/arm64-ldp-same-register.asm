// Integer LDP with Rt2==Rt is constrained unpredictable (clang rejects
// it); the integer pair load must reject it too.
import("arm/arm64.inc")

arm64_ldp(arm64_x0, arm64_x0, arm64_x1, 0)
