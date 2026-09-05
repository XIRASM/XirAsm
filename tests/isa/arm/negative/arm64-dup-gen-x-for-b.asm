// DUP (general) B/H/S lanes replicate a W register (LLVM GPR32); an X source
// for an 8B arrangement must be rejected.
import("arm/arm64.inc")

arm64_dup_gen(arm64_v0, arm64_arr_8b, arm64_x1)
