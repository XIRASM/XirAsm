// No-allocate pairs share the LDP/STP width rule: Rt and Rt2 must be the
// same width (LLVM LoadPairNoAlloc uses one regtype for both).
// Expected failure: load/store pair: mixed W/X registers
import("arm/arm64.inc");

arm64_ldnp(arm64_w0, arm64_x1, arm64_x2, 0)
