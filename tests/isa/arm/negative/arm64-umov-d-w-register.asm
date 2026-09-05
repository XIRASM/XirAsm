// UMOV D extraction requires an X destination (LLVM vi64: GPR64, Q=1);
// a W destination must be rejected.
import("arm/arm64.inc")

arm64_umov(arm64_w0, arm64_ts_d, 0, arm64_v1)
