// CBZ imm19 spans +/-2^18 words; a 1 MiB reserved jump exceeds it.
// The reserved tail advances the logical address without file bytes, so the
// out-of-range distance costs no output size.
// Expected failure: cbz: forward branch out of range
import("arm/arm64.inc");

site:
arm64_cbz(arm64_x0, "far")
reserve(0x100000)
far:
emit.u8(0)
