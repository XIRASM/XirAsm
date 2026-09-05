// LLVM rejects a bare W index on sign-extending register-offset loads
// ("ldrsw x0, [x1, w2]" -> expected 'uxtw' or 'sxtw' with optional shift);
// the extension must be spelled out. Our sugar follows that rule.
// Expected failure: arm64_asm: ldrsw: bare W index needs an explicit uxtw/sxtw option
import("arm/arm64.inc");

arm64_asm("ldrsw x0, [x1, w2]")
