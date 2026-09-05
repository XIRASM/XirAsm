// Move-wide writes ZR or a general register at encoding 31, never SP.
// Expected failure: move-wide destination cannot be SP
import("arm/arm64.inc");

arm64_movz(arm64_sp, 1, 0)
