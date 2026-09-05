// LDAPRB takes a W data register (LLVM RCPCLoad declares GPR32:$Rt for the
// byte form); an X register has no encoding.
// Expected failure: ldaprb requires a W register
import("arm/arm64.inc");

arm64_ldaprb(arm64_x0, arm64_x1)
