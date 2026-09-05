// DMB's barrier option rides CRm (0..15); 16 has no encoding.
// Expected failure: dmb: barrier option out of range
import("arm/arm64.inc");

arm64_dmb(16)
