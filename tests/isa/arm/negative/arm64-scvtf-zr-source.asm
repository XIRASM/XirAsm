// SCVTF source is GPR32/GPR64 in LLVM (no ZR, no SP); wzr must be rejected.
import("arm/arm64.inc")

arm64_scvtf_s(arm64_v0, arm64_wzr)
