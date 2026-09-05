// DUP (element) source index must be inside the full-register lane count for
// the element size (B: 0..15); 16 must be rejected.
import("arm/arm64.inc")

arm64_dup_elem(arm64_v0, arm64_arr_16b, arm64_v1, 16)
