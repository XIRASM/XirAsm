// LDP with Rt2==Rt is CONSTRained UNPREDICTABLE (clang: "unpredictable LDP
// instruction, Rt2==Rt"); the FP pair load must reject it. STP with equal
// registers stays legal.
import("arm/arm64.inc")

arm64_ldp_s(arm64_v0, arm64_v0, arm64_x1, 0)
