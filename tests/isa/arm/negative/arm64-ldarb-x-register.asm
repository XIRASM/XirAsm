// Byte and halfword acquire loads take a W data register only
// (LLVM LoadAcquire declares GPR32:$Rt for LDARB/LDARH).
// Expected failure: ldarb requires a W register
import("arm/arm64.inc");

arm64_ldarb(arm64_x0, arm64_x1)
