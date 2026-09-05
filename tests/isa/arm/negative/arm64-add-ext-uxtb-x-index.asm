// Extended add/sub options uxtb/uxth/uxtw/sxtb/sxth/sxtw all extend from a
// W source register. LLVM rejects an X source for the narrow extends:
// "add x0, x1, x2, uxtb" -> expected 'sxtx' 'uxtx' or 'lsl'.
// Expected failure: uxtb/uxth/uxtw/sxtb/sxth/sxtw require a W register
import("arm/arm64.inc");

arm64_add_ext(arm64_x0, arm64_x1, arm64_x2, arm64_uxtb, 0)
