// The ordering parameter selects the A/R bits (0=plain, 1=a, 2=l, 3=al);
// anything beyond 3 has no encoding.
// Expected failure: swp: ordering must be 0..3 (plain/a/l/al)
import("arm/arm64.inc");

arm64_swp(arm64_w0, arm64_w1, arm64_x2, 4)
