// SMOV S extraction exists only with an X destination (LLVM vi32to64);
// a W destination must be rejected (S->W is identity, UMOV covers it).
import("arm/arm64.inc")

arm64_smov(arm64_w0, arm64_ts_s, 0, arm64_v1)
