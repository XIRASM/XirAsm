// MOVZ must reject an imm16 that does not fit.
// Expected failure: move-wide imm16 does not fit its field width
import("arm/arm64.inc");

arm64_movz(arm64_x0, 0x10000, 0)
