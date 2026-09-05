// LSE halfword forms take W registers for both Rs and Rt (LLVM GPR32 for
// LDADDH and friends); an X register has no encoding.
// Expected failure: ldaddb: requires a W register
import("arm/arm64.inc");

arm64_ldaddb(arm64_w0, arm64_x1, arm64_x2, arm64_order_plain)
