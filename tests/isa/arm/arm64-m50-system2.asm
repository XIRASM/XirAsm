// M6: system registers — MRS/MSR (register), MSR (immediate), and the
// table-driven TLBI/DC/AT/IC space.
//
// Layout (LLVM RtSystemI / BaseSystemI): 1101010100(31-22) L(21) op0(20-19)
// op1(18-16) CRn(15-12) CRm(11-8) op2(7-5) Rt(4-0). MRS L = 1, MSR L = 0;
// Rt is GPR64 (X/xzr, SP rejected). MSR (immediate) per MSRpstateImm0_15:
// Rt = 11111, pstatefield{5-3} at 18-16, 0100 at 15-12, imm4 at 11-8,
// pstatefield{2-0} at 7-5. The sysreg constants in sysreg_table.inc are
// generated from LLVM AArch64SystemOperands.td.
// Words pinned from clang -target=aarch64 assembly (mkwords pipeline).
import("arm/arm64.inc")

insn_mrs_midr:
arm64_mrs_sys(arm64_x0, arm64_sys_midr_el1)
insn_mrs_ctr:
arm64_mrs_sys(arm64_x1, arm64_sys_ctr_el0)
insn_msr_sctlr:
arm64_msr_sys(arm64_sys_sctlr_el1, arm64_x2)
insn_msr_daifset:
arm64_msr_pstate(arm64_pstate_daifset, 3)
insn_msr_daifclr:
arm64_msr_pstate(arm64_pstate_daifclr, 7)
insn_msr_spsel:
arm64_msr_pstate(arm64_pstate_spsel, 1)
insn_msr_pan:
arm64_msr_pstate(arm64_pstate_pan, 0)
insn_msr_uao:
arm64_msr_pstate(arm64_pstate_uao, 1)
insn_tlbi_vmalle1:
arm64_msr_sys(arm64_sys_tlbi_vmalle1, arm64_xzr)
insn_tlbi_vae1:
arm64_msr_sys(arm64_sys_tlbi_vae1, arm64_x0)
insn_dc_cvac:
arm64_msr_sys(arm64_sys_dc_cvac, arm64_x1)
insn_dc_zva:
arm64_msr_sys(arm64_sys_dc_zva, arm64_xzr)
insn_ic_iallu:
arm64_msr_sys(arm64_sys_ic_iallu, arm64_xzr)
insn_ic_ivau:
arm64_msr_sys(arm64_sys_ic_ivau, arm64_x3)
insn_at_s1e1r:
arm64_msr_sys(arm64_sys_at_s1e1r, arm64_x2)
insn_mrs_cntpct:
arm64_mrs_sys(arm64_x5, arm64_sys_cntpct_el0)

defer {
    assert(load.u32(insn_mrs_midr) == 0xd5380000, "mrs x0, midr_el1");
    assert(load.u32(insn_mrs_ctr) == 0xd53b0021, "mrs x1, ctr_el0");
    assert(load.u32(insn_msr_sctlr) == 0xd5181002, "msr sctlr_el1, x2");
    assert(load.u32(insn_msr_daifset) == 0xd50343df, "msr daifset, #3");
    assert(load.u32(insn_msr_daifclr) == 0xd50347ff, "msr daifclr, #7");
    assert(load.u32(insn_msr_spsel) == 0xd50041bf, "msr spsel, #1");
    assert(load.u32(insn_msr_pan) == 0xd500409f, "msr pan, #0");
    assert(load.u32(insn_msr_uao) == 0xd500417f, "msr uao, #1");
    assert(load.u32(insn_tlbi_vmalle1) == 0xd508871f, "tlbi vmalle1");
    assert(load.u32(insn_tlbi_vae1) == 0xd5088720, "tlbi vae1, x0");
    assert(load.u32(insn_dc_cvac) == 0xd50b7a21, "dc cvac, x1");
    assert(load.u32(insn_dc_zva) == 0xd50b743f, "dc zva");
    assert(load.u32(insn_ic_iallu) == 0xd508751f, "ic iallu");
    assert(load.u32(insn_ic_ivau) == 0xd50b7523, "ic ivau, x3");
    assert(load.u32(insn_at_s1e1r) == 0xd5087802, "at s1e1r, x2");
    assert(load.u32(insn_mrs_cntpct) == 0xd53be025, "mrs x5, cntpct_el0");
}
