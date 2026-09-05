// A64 PC-relative branches require word-aligned sites and targets.
// Expected failure: b: branch target must be word aligned
import("arm/arm64.inc");

site:
arm64_b("misaligned")
emit.u8(0)
misaligned:
emit.u8(0)
