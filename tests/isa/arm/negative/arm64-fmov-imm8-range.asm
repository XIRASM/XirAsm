// FMOV (immediate) carries an 8-bit imm8 field; 256 must be rejected.
import("arm/arm64.inc")

arm64_fmov_imm_s(arm64_v0, 256)
