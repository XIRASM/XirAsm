// Byte and halfword exclusive/ordered forms take a W data register only
// (LLVM GPR32:$Rt for LDXRB/LDARB and friends); X registers are invalid.
// Expected failure: ldxrb requires a W register
import("arm/arm64.inc");

arm64_ldxrb(arm64_x0, arm64_x1)
