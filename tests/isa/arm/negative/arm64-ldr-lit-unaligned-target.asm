// Literal loads require a word-aligned target; a label on a byte at offset 5
// is not word aligned.
// Expected failure: ldr literal: literal must be word aligned
import("arm/arm64.inc");

arm64_ldr_lit(arm64_x0, "mid")
emit.u32(0)
emit.u8(1)
mid:
