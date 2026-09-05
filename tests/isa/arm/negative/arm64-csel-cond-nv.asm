// Condition code 15 (NV) is not encodable in the conditional select group.
// Expected failure: conditional select requires a real condition code (0..13)
import("arm/arm64.inc");

arm64_csel(arm64_x0, arm64_x1, arm64_x2, 15)
