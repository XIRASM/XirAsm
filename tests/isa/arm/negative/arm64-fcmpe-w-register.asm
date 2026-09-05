// FCMPE compares S/D registers only; a W register must be rejected (shares
// the FPR32/FPR64 validation path with FCMP).
import("arm/arm64.inc")

arm64_fcmpe_s(arm64_w0, arm64_v1)
