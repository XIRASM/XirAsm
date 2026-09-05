// FMOV (immediate) targets an S or D register; a W register must be rejected.
import("arm/arm64.inc")

arm64_fmov_imm_s(arm64_w0, 112)
