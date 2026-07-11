origin(0)

include("repeat.inc")
include("repeat.inc")

import("module/once.inc")
import("module/once.inc")

print("module bytes", here())
warn("diagnostic example", true)
assert(here() == 4, "unexpected module output")

emit.u8(0x44)
