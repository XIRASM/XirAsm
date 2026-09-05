// Q pair post-index offset is scaled by 16 with range -64..63 (bytes
// -1024..1008); 1024 must be rejected.
import("arm/arm64.inc")

arm64_ldp_q_post(arm64_v0, arm64_v1, arm64_x2, 1024)
