// A64 system instructions: barriers, hints, BTI (M4.8), with the table-driven
// MRS/MSR/TLBI families to follow in M6.
//
// Barrier/hint layout (LLVM HintI / Barrier classes): 1101010100(31-22)
// 0(21) 00(20-19) 0011(18-15) CRm(11-8) opc(7-5) 11111(4-0). DMB opc = 0b101,
// DSB opc = 0b100, ISB opc = 0b110 (CRm = 15). HINT: opc = 0b000, CRm = 0,
// imm(11-5); BTI is HINT with imm 32 (any), 34 (c), 36 (j), 38 (jc).

const arm64_barrier_sy: u64 = 15
const arm64_barrier_st: u64 = 14
const arm64_barrier_ld: u64 = 13
const arm64_barrier_ish: u64 = 11
const arm64_barrier_ishst: u64 = 10
const arm64_barrier_ishld: u64 = 9
const arm64_barrier_nsh: u64 = 7
const arm64_barrier_nshst: u64 = 6
const arm64_barrier_nshld: u64 = 5
const arm64_barrier_osh: u64 = 3
const arm64_barrier_oshst: u64 = 2
const arm64_barrier_oshld: u64 = 1

fn arm64_emit_barrier(opc: u64, crm: u64, what: string) {
    assert(crm <= 15, sym.join(what, ": barrier option out of range"));
    emit.u32(0xd5033000 | (crm << 8) | (opc << 5) | 0x1f)
}

// DMB (data memory barrier). ARM ARM C6.2.87; option via CRm.
fn arm64_dmb(option: u64) {
    arm64_emit_barrier(5, option, "dmb")
}

// DSB (data synchronization barrier). ARM ARM C6.2.88.
fn arm64_dsb(option: u64) {
    arm64_emit_barrier(4, option, "dsb")
}

// ISB (instruction synchronization barrier). ARM ARM C6.2.156.
fn arm64_isb() {
    arm64_emit_barrier(6, 15, "isb")
}

// HINT (imm 0..127). ARM ARM C6.2.155; LLVM HintI.
fn arm64_hint(imm: u64) {
    assert(imm <= 127, "hint immediate out of range");
    emit.u32(0xd503201f | (imm << 5))
}

const arm64_bti_none: u64 = 32
const arm64_bti_c: u64 = 34
const arm64_bti_j: u64 = 36
const arm64_bti_jc: u64 = 38

// BTI (branch target identification). ARM ARM C6.2.39; LLVM BTI classes.
// kind: 32 = any target, 34 = c, 36 = j, 38 = jc.
fn arm64_bti(kind: u64) {
    assert(kind == arm64_bti_none || kind == arm64_bti_c
        || kind == arm64_bti_j || kind == arm64_bti_jc,
        "bti: kind must be one of the arm64_bti_* constants");
    arm64_hint(kind)
}

// --- Exception generation -----------------------------------------------------
// LLVM ExceptionGeneration: 11010100(31-24) op1(23-21) imm16(20-5) 000(4-2)
// ll(1-0). SVC = op1 000 ll 01, HVC = 000 ll 10, SMC = 000 ll 11,
// BRK = op1 001 ll 00, HLT = op1 010 ll 00.

fn arm64_emit_exception(op1: u64, ll: u64, imm: u64, what: string) {
    assert(imm <= 0xffff, sym.join(what, ": immediate out of range 0..65535"));
    emit.u32(0xd4000000 | (op1 << 21) | ((imm & 0xffff) << 5) | ll)
}

// SVC (supervisor call). ARM ARM C6.2.342.
fn arm64_svc(imm: u64) {
    arm64_emit_exception(0, 1, imm, "svc")
}

// HVC (hypervisor call). ARM ARM C6.2.150.
fn arm64_hvc(imm: u64) {
    arm64_emit_exception(0, 2, imm, "hvc")
}

// SMC (secure monitor call). ARM ARM C6.2.319.
fn arm64_smc(imm: u64) {
    arm64_emit_exception(0, 3, imm, "smc")
}

// BRK (breakpoint). ARM ARM C6.2.42.
fn arm64_brk(imm: u64) {
    arm64_emit_exception(1, 0, imm, "brk")
}

// HLT (halt). ARM ARM C6.2.148.
fn arm64_hlt(imm: u64) {
    arm64_emit_exception(2, 0, imm, "hlt")
}

// --- System registers (M6): MRS / MSR (register) and MSR (immediate) ----------
// Layout (LLVM RtSystemI / MSRpstateImm0_15): 1101010100(31-22) L(21)
// op0(20-19) op1(18-16) CRn(15-12) CRm(11-8) op2(7-5) Rt(4-0). MRS sets
// L = 1, MSR sets L = 0. MSR (immediate) is L = 0 with Rt = 11111, the
// 6-bit PState field at 18-16/7-5, a fixed 0100 at 15-12, and imm4 at 11-8.
// Rt is GPR64 (X registers and XZR; SP is not encodable).

fn arm64_msr_sys(sys: u64, rt: u64) {
    assert(arm64_reg_is64(rt) || arm64_reg_number(rt) == 31,
        "msr: Rt must be an X register or XZR");
    arm64_check_no_sp(rt, "msr");
    const op0: u64 = (sys >> 14) & 3
    const op1: u64 = (sys >> 11) & 7
    const crn: u64 = (sys >> 7) & 15
    const crm: u64 = (sys >> 3) & 15
    const op2: u64 = sys & 7
    emit.u32(0xd5000000 | (op0 << 19) | (op1 << 16) | (crn << 12) | (crm << 8)
        | (op2 << 5) | arm64_reg_number(rt))
}

fn arm64_mrs_sys(rt: u64, sys: u64) {
    assert(arm64_reg_is64(rt) || arm64_reg_number(rt) == 31,
        "mrs: Rt must be an X register or XZR");
    arm64_check_no_sp(rt, "mrs");
    const op0: u64 = (sys >> 14) & 3
    const op1: u64 = (sys >> 11) & 7
    const crn: u64 = (sys >> 7) & 15
    const crm: u64 = (sys >> 3) & 15
    const op2: u64 = sys & 7
    emit.u32(0xd5000000 | (1 << 21) | (op0 << 19) | (op1 << 16) | (crn << 12)
        | (crm << 8) | (op2 << 5) | arm64_reg_number(rt))
}

const arm64_pstate_spsel: u64 = 5
const arm64_pstate_daifset: u64 = 30
const arm64_pstate_daifclr: u64 = 31
const arm64_pstate_pan: u64 = 4
const arm64_pstate_uao: u64 = 3

// MSR (immediate): PState field (6 bits: op1<<3 | op2) with a 4-bit
// immediate in CRm. ARM ARM C6.2.330; LLVM MSRpstateImm0_15.
fn arm64_msr_pstate(field: u64, imm: u64) {
    assert(field <= 63, "msr: pstate field out of range");
    assert(imm <= 15, "msr: pstate immediate out of range");
    emit.u32(0xd5000000 | ((field >> 3) << 16) | (0x4 << 12) | (imm << 8)
        | ((field & 7) << 5) | 0x1f)
}

// ERET: exception return; PC from ELR_ELx, PSTATE from SPSR_ELx. LLVM
// SpecialReturn<0b0100> (InstrInfo.td:3635) over BaseBranchReg: opc at
// bits 24-21, Rn and Rd fields fixed to 11111. Takes no operands; the
// PAC variants (ERETAA/ERETAB, FEAT_PAuth) are out of scope.
// clang: eret -> 0xd69f03e0.
fn arm64_eret() {
    emit.u32(0xd69f03e0)
}
