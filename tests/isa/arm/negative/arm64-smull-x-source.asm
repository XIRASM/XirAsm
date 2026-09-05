// SMULL widens W sources into an X pair of results (LLVM WideMulAccum fixes
// sf = 1 with GPR32 sources); an X source register is invalid.
// Expected failure: smull: sources must be W registers
import("arm/arm64.inc");

arm64_smull(arm64_x0, arm64_x1, arm64_w2)
