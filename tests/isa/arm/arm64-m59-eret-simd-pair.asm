// Batch: ERET (exception return) and SIMD pair load/store —
// LDP/STP/LDNP/STNP for S/D/Q registers (kernel NEON context save/restore
// and media code pair access).
//
// Encodings follow LLVM SpecialReturn and BaseLoadStorePairOffset/NoAlloc
// with V=1 (see include/arm/arm64/simd.inc and system.inc). Pinned words
// extracted mechanically from clang --target=aarch64-linux-gnu
// -march=armv8.4-a object bytes by the mkwords.sh pipeline.
import("arm/arm64.inc")

insn_eret:
arm64_eret()
insn_ldp_s:
arm64_ldp_s(arm64_v0, arm64_v1, arm64_x2, 0)
insn_ldp_d:
arm64_ldp_d(arm64_v3, arm64_v4, arm64_x5, 8)
insn_ldp_q:
arm64_ldp_q(arm64_v6, arm64_v7, arm64_sp, 0)
insn_stp_s:
arm64_stp_s(arm64_v8, arm64_v9, arm64_x10, 252)
insn_stp_d:
arm64_stp_d(arm64_v11, arm64_v12, arm64_x13, -8)
insn_stp_q:
arm64_stp_q(arm64_v14, arm64_v15, arm64_x16, -16)
insn_ldnp_s:
arm64_ldnp_s(arm64_v17, arm64_v18, arm64_x19, 0)
insn_ldnp_d:
arm64_ldnp_d(arm64_v20, arm64_v21, arm64_x22, 16)
insn_ldnp_q:
arm64_ldnp_q(arm64_v23, arm64_v24, arm64_x25, -16)
insn_stnp_s:
arm64_stnp_s(arm64_v25, arm64_v26, arm64_x27, 0)
insn_stnp_d:
arm64_stnp_d(arm64_v28, arm64_v29, arm64_x30, 8)
insn_stnp_q:
arm64_stnp_q(arm64_v0, arm64_v1, arm64_x2, -16)

defer {
    assert(load.u32(insn_eret) == 0xd69f03e0, "eret");
    assert(load.u32(insn_ldp_s) == 0x2d400440, "ldp s0, s1, [x2]");
    assert(load.u32(insn_ldp_d) == 0x6d4090a3, "ldp d3, d4, [x5, #8]");
    assert(load.u32(insn_ldp_q) == 0xad401fe6, "ldp q6, q7, [sp]");
    assert(load.u32(insn_stp_s) == 0x2d1fa548, "stp s8, s9, [x10, #252]");
    assert(load.u32(insn_stp_d) == 0x6d3fb1ab, "stp d11, d12, [x13, #-8]");
    assert(load.u32(insn_stp_q) == 0xad3fbe0e, "stp q14, q15, [x16, #-16]");
    assert(load.u32(insn_ldnp_s) == 0x2c404a71, "ldnp s17, s18, [x19]");
    assert(load.u32(insn_ldnp_d) == 0x6c4156d4, "ldnp d20, d21, [x22, #16]");
    assert(load.u32(insn_ldnp_q) == 0xac7fe337, "ldnp q23, q24, [x25, #-16]");
    assert(load.u32(insn_stnp_s) == 0x2c006b79, "stnp s25, s26, [x27]");
    assert(load.u32(insn_stnp_d) == 0x6c00f7dc, "stnp d28, d29, [x30, #8]");
    assert(load.u32(insn_stnp_q) == 0xac3f8440, "stnp q0, q1, [x2, #-16]");
}
