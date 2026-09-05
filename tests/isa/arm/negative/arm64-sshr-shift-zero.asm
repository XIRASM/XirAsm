// Right shifts encode immhb = 2T - shift, so the amount is 1..T; 0 must be
// rejected.
import("arm/arm64.inc")

arm64_sshr(arm64_v0, arm64_v1, 0, arm64_arr_8b)
