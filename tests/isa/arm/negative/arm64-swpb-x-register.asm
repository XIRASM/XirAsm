// LSE byte forms take W registers for both Rs and Rt (LLVM GPR32 for
// SWPB/LDADDB and friends); an X register has no encoding.
// Expected failure: swpb: requires a W register
import("arm/arm64.inc");

arm64_swpb(arm64_x0, arm64_w1, arm64_x2, arm64_order_plain)
