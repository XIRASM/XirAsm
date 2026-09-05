// CRC32's Rm is a W register for the byte/halfword/word forms and an X
// register only for the sf = 1 X forms (LLVM StreamReg per def); a W Rm in
// crc32x is invalid.
// Expected failure: crc32x: Rm width must match the size
import("arm/arm64.inc");

arm64_crc32x(arm64_w0, arm64_w1, arm64_w2)
