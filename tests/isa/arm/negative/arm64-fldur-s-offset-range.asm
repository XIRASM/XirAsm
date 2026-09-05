// FP LDUR uses a 9-bit signed byte offset (-256..255); 256 must be rejected.
import("arm/arm64.inc")

arm64_fldur_s(arm64_v0, arm64_x1, 256)
