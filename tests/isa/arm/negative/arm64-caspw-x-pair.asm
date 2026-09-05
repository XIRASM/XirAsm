// CASPW takes a W pair (sz = 00) and CASPX an X pair (sz = 01); the width
// is fixed by the wrapper, so an X pair in caspw is invalid.
// Expected failure: caspw: requires W pair registers
import("arm/arm64.inc");

arm64_caspw(arm64_x0, arm64_x2, arm64_x4, arm64_order_plain)
