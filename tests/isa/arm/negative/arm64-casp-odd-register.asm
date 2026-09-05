// CASP pair operands are even registers (LLVM WSeqPair/XSeqPair operand
// classes); the pair members are Rs/Rs+1 and Rt/Rt+1, so an odd base
// register is unencodable.
// Expected failure: caspw: Rs must be an even register (pair = Rs, Rs+1)
import("arm/arm64.inc");

arm64_caspw(arm64_w1, arm64_w2, arm64_x3, arm64_order_plain)
