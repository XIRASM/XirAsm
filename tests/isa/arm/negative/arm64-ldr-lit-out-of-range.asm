// Literal loads span +/-1 MiB; a target 1 MiB + 4 bytes away is out of range.
// The filler emits 262144 NOPs (1 MiB) between the load site and the target.
// Expected failure: ldr literal: literal out of range
import("arm/arm64.inc");

arm64_ldr_lit(arm64_x0, "far")
for i in range(0, 262144) {
    arm64_nop()
}
far:
