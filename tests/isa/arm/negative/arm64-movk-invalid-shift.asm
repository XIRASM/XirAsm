// Move-wide shift must be one of 0/16/32/48 (hw field).
// Expected failure: move-wide shift must be 0, 16, 32, or 48
import("arm/arm64.inc");

arm64_movk(arm64_x1, 1, 12)
