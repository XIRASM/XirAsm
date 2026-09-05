// The exception immediate is 16 bits (LLVM timm32_0_65535); 0x10000 does not
// fit.
// Expected failure: svc: immediate out of range 0..65535
import("arm/arm64.inc");

arm64_svc(0x10000)
