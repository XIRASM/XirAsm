// INS (general) B/H/S lanes take a W source (LLVM GPR32); an X source for a
// B lane must be rejected.
import("arm/arm64.inc")

arm64_ins_gpr(arm64_v0, arm64_ts_b, 3, arm64_x1)
