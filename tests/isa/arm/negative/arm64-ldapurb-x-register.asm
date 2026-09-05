// LDAPURB takes a W data register (LLVM BaseLoadUnscaleV84 declares
// GPR32:$Rt for the byte form); an X register has no encoding.
// Expected failure: ldapurb requires a W register
import("arm/arm64.inc");

arm64_ldapurb(arm64_x0, arm64_x1, 0)
