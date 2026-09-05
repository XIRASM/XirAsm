// LDR (literal) opc=01 requires an X target register (ARM ARM C6.2.175);
// the W literal form is a separate API (arm64_ldrw_lit, opc=00). LLVM
// encodes "ldr w0, label" as the W form, never as opc=01 with a W Rt.
// Expected failure: ldr literal requires an X register
import("arm/arm64.inc");

arm64_ldr_lit(arm64_w0, "lit")
lit:
emit.u8(1)
align(4)
