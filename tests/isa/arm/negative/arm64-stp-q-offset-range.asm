// Q pair imm7 is scaled by 16 with range -64..63, so the byte offset limit
// is -1024..1008; 1024 must be rejected.
import("arm/arm64.inc")

arm64_stp_q(arm64_v0, arm64_v1, arm64_x2, 1024)
