// A64 synchronization: exclusive and ordered load/store (M4.6).
//
// Implemented family by family under the M4.6 implementation rules
// (one family per reviewed stage).
//
// Shared layout (LLVM AArch64InstrFormats.td, BaseLoadStoreExclusive):
//   size(31-30) 001000(29-24) o2(23) L(22) o1(21) Rs(20-16) o0(15)
//   Rt2(14-10) Rn(9-5) Rt(4-0).
// Plain exclusive load/store use o2=0, o1=0, o0=0; the acquire/release
// families and the pair forms set those bits in their own stages. Rn is
// GPR64sp0 (an X register or SP, never ZR: encoding 31 reads SP); Rt of a
// load may be ZR; the STXR status Ws is a W register (ZR allowed, SP not).

// Internal: exclusive/ordered load/store. o1 selects the pair form (Rt2
// becomes a real register field instead of the fixed 11111); o2 (bit 23)
// and o0 (bit 15) distinguish the ordered families (LDAR/STLR set both,
// LDAXR/STLXR set o0 only).
fn arm64_emit_ldst_exclusive(size: u64, is_load: bool, o1: u64, o2: u64, o0: u64, rs: u64, rt2: u64, rn: u64, rt: u64, what: string) {
    assert(size <= 3, sym.join(what, ": size out of range"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(what, ": base cannot be ZR (reads SP)"));
    arm64_check_no_sp(rt, what);
    let l: u64 = 0
    if is_load {
        l = 1
    }
    emit.u32((size << 30) | (0x8 << 24) | (o2 << 23) | (l << 22) | (o1 << 21)
        | ((rs & 0x1f) << 16) | (o0 << 15) | ((rt2 & 0x1f) << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDXR (W/X by Rt). ARM ARM C6.2.193; LLVM LDXRW/LDXRX
// (LoadExclusive <sz, o2=0, L=1, o1=0, o0=0>, Rs = 11111).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldxr w9, [sp]   -> 0x885f7fe9
//   ldxr x10, [x11] -> 0xc85f7d6a
fn arm64_ldxr(rt: u64, rn: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, true, 0, 0, 0, 0x1f, 0x1f, rn, rt, "ldxr")
}

// STXR (status Ws, W/X data Rt). ARM ARM C6.2.349; LLVM STXRW/STXRX
// (StoreExclusive <sz, 0, 0, 0, 0>, Ws = Inst{20-16}, a W register).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   stxr wzr, w4, [sp] -> 0x881f7fe4
//   stxr w5, x6, [x7]  -> 0xc8057ce6
fn arm64_stxr(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stxr status must be a W register");
    arm64_check_no_sp(ws, "stxr status");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, false, 0, 0, 0, arm64_reg_number(ws), 0x1f, rn, rt, "stxr")
}

// LDXP (exclusive pair, W/W or X/X). ARM ARM C6.2.194; LLVM LDXPW/LDXPX
// (LoadExclusivePair <sz, o2=0, L=1, o1=1, o0=0>, Rs = 11111, Rt2 = Inst{14-10}).
// A pair must be all-W or all-X (mixed widths unencodable); ZR allowed, SP not.
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldxp w12, wzr, [sp] -> 0x887f7fec
//   ldxp x13, x14, [x15] -> 0xc87f39ed
fn arm64_ldxp(rt: u64, rt2: u64, rn: u64) {
    arm64_check_same_width(rt, rt2, "ldxp");
    arm64_check_no_sp(rt2, "ldxp");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, true, 1, 0, 0, 0x1f, arm64_reg_number(rt2), rn, rt, "ldxp")
}

// STXP (status Ws, exclusive data pair). ARM ARM C6.2.350; LLVM STXPW/STXPX
// (StoreExclusivePair <sz, 0, 0, 1, 0>, Ws = Inst{20-16}, Rt2 = Inst{14-10}).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   stxp w11, w12, w13, [x14] -> 0x882b35cc
//   stxp wzr, x23, x14, [x15] -> 0xc83f39f7
fn arm64_stxp(ws: u64, rt: u64, rt2: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stxp status must be a W register");
    arm64_check_no_sp(ws, "stxp status");
    arm64_check_same_width(rt, rt2, "stxp");
    arm64_check_no_sp(rt2, "stxp");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, false, 1, 0, 0, arm64_reg_number(ws), arm64_reg_number(rt2), rn, rt, "stxp")
}

// LDAR (load-acquire, W/X by Rt). ARM ARM C6.2.186; LLVM LDARW/LDARX
// (LoadAcquire <sz, o2=1, L=1, o1=0, o0=1>, Rs = Rt2 = 11111).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldar wzr, [x1] -> 0x88dffc3f
//   ldar x1, [x2]  -> 0xc8dffc41
fn arm64_ldar(rt: u64, rn: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, true, 0, 1, 1, 0x1f, 0x1f, rn, rt, "ldar")
}

// STLR (store-release, W/X by Rt). ARM ARM C6.2.352; LLVM STLRW/STLRX
// (StoreRelease <sz, o2=1, L=0, o1=0, o0=1>, Rs = Rt2 = 11111).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   stlr wzr, [x1] -> 0x889ffc3f
//   stlr x30, [x2] -> 0xc89ffc5e
fn arm64_stlr(rt: u64, rn: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, false, 0, 1, 1, 0x1f, 0x1f, rn, rt, "stlr")
}

// LDAXR (load-acquire exclusive, W/X by Rt). ARM ARM C6.2.181; LLVM
// LDAXRW/LDAXRX (LoadExclusive <sz, o2=0, L=1, o1=0, o0=1>, Rs = 11111).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldaxr wzr, [x22] -> 0x885ffedf
//   ldaxr x21, [x23] -> 0xc85ffef5
fn arm64_ldaxr(rt: u64, rn: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, true, 0, 0, 1, 0x1f, 0x1f, rn, rt, "ldaxr")
}

// STLXR (store-release exclusive, status Ws, W/X data Rt). ARM ARM C6.2.351;
// LLVM STLXRW/STLXRX (StoreExclusive <sz, o2=0, L=0, o1=0, o0=1>,
// Ws = Inst{20-16}).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   stlxr wzr, w17, [sp] -> 0x881ffff1
//   stlxr w18, x19, [x20] -> 0xc812fe93
fn arm64_stlxr(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stlxr status must be a W register");
    arm64_check_no_sp(ws, "stlxr status");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, false, 0, 0, 1, arm64_reg_number(ws), 0x1f, rn, rt, "stlxr")
}

// LDAXP (load-acquire exclusive pair). ARM ARM C6.2.180; LLVM LDAXPW/LDAXPX
// (LoadExclusivePair <sz, o2=0, L=1, o1=1, o0=1>, Rs = 11111).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   ldaxp w26, wzr, [sp] -> 0x887ffffa
//   ldaxp x27, x28, [x30] -> 0xc87ff3db
fn arm64_ldaxp(rt: u64, rt2: u64, rn: u64) {
    arm64_check_same_width(rt, rt2, "ldaxp");
    arm64_check_no_sp(rt2, "ldaxp");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, true, 1, 0, 1, 0x1f, arm64_reg_number(rt2), rn, rt, "ldaxp")
}

// STLXP (store-release exclusive pair, status Ws). ARM ARM C6.2.350;
// LLVM STLXPW/STLXPX (StoreExclusivePair <sz, o2=0, L=0, o1=1, o0=1>,
// Ws = Inst{20-16}).
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   stlxp wzr, w22, w23, [x24] -> 0x883fdf16
//   stlxp w25, x26, x27, [sp] -> 0xc839effa
fn arm64_stlxp(ws: u64, rt: u64, rt2: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stlxp status must be a W register");
    arm64_check_no_sp(ws, "stlxp status");
    arm64_check_same_width(rt, rt2, "stlxp");
    arm64_check_no_sp(rt2, "stlxp");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldst_exclusive(size, false, 1, 0, 1, arm64_reg_number(ws), arm64_reg_number(rt2), rn, rt, "stlxp")
}

// --- Stage 5: byte/halfword variants (sz = 00/01, data Rt must be W) ------

// LDXRB/LDXRH. ARM ARM C6.2.192/C6.2.191; LLVM LDXRB/LDXRH
// (LoadExclusive <sz, 0, 1, 0, 0>). Fixture: ldxrb w7, [x9] -> 0x085f7d27.
fn arm64_ldxrb(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldxrb requires a W register");
    arm64_emit_ldst_exclusive(0, true, 0, 0, 0, 0x1f, 0x1f, rn, rt, "ldxrb")
}

fn arm64_ldxrh(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldxrh requires a W register");
    arm64_emit_ldst_exclusive(1, true, 0, 0, 0, 0x1f, 0x1f, rn, rt, "ldxrh")
}

// STXRB/STXRH. ARM ARM C6.2.348/C6.2.347; LLVM STXRB/STXRH
// (StoreExclusive <sz, 0, 0, 0, 0>). Fixture: stxrb w1, w2, [x3] -> 0x08017c62.
fn arm64_stxrb(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stxrb status must be a W register");
    arm64_check_no_sp(ws, "stxrb status");
    assert(!arm64_reg_is64(rt), "stxrb requires a W register");
    arm64_emit_ldst_exclusive(0, false, 0, 0, 0, arm64_reg_number(ws), 0x1f, rn, rt, "stxrb")
}

fn arm64_stxrh(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stxrh status must be a W register");
    arm64_check_no_sp(ws, "stxrh status");
    assert(!arm64_reg_is64(rt), "stxrh requires a W register");
    arm64_emit_ldst_exclusive(1, false, 0, 0, 0, arm64_reg_number(ws), 0x1f, rn, rt, "stxrh")
}

// LDAXRB/LDAXRH. LLVM LoadAcquire <sz, 0, 1, 0, 1>.
// Fixture: ldaxrb w19, [x21] -> 0x085ffeb3.
fn arm64_ldaxrb(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldaxrb requires a W register");
    arm64_emit_ldst_exclusive(0, true, 0, 0, 1, 0x1f, 0x1f, rn, rt, "ldaxrb")
}

fn arm64_ldaxrh(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldaxrh requires a W register");
    arm64_emit_ldst_exclusive(1, true, 0, 0, 1, 0x1f, 0x1f, rn, rt, "ldaxrh")
}

// STLXRB/STLXRH. LLVM StoreExclusive <sz, 0, 0, 0, 1>.
// Fixture: stlxrb w14, w15, [x16] -> 0x080efe0f.
fn arm64_stlxrb(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stlxrb status must be a W register");
    arm64_check_no_sp(ws, "stlxrb status");
    assert(!arm64_reg_is64(rt), "stlxrb requires a W register");
    arm64_emit_ldst_exclusive(0, false, 0, 0, 1, arm64_reg_number(ws), 0x1f, rn, rt, "stlxrb")
}

fn arm64_stlxrh(ws: u64, rt: u64, rn: u64) {
    assert(!arm64_reg_is64(ws), "stlxrh status must be a W register");
    arm64_check_no_sp(ws, "stlxrh status");
    assert(!arm64_reg_is64(rt), "stlxrh requires a W register");
    arm64_emit_ldst_exclusive(1, false, 0, 0, 1, arm64_reg_number(ws), 0x1f, rn, rt, "stlxrh")
}

// LDARB/LDARH. LLVM LoadAcquire <sz, 1, 1, 0, 1>.
// Fixture: ldarb w29, [sp] -> 0x08dffffd.
fn arm64_ldarb(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldarb requires a W register");
    arm64_emit_ldst_exclusive(0, true, 0, 1, 1, 0x1f, 0x1f, rn, rt, "ldarb")
}

fn arm64_ldarh(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldarh requires a W register");
    arm64_emit_ldst_exclusive(1, true, 0, 1, 1, 0x1f, 0x1f, rn, rt, "ldarh")
}

// STLRB/STLRH. LLVM StoreRelease <sz, 1, 0, 0, 1>.
// Fixture: stlrb w27, [sp] -> 0x089ffffb.
fn arm64_stlrb(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "stlrb requires a W register");
    arm64_emit_ldst_exclusive(0, false, 0, 1, 1, 0x1f, 0x1f, rn, rt, "stlrb")
}

fn arm64_stlrh(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "stlrh requires a W register");
    arm64_emit_ldst_exclusive(1, false, 0, 1, 1, 0x1f, 0x1f, rn, rt, "stlrh")
}

// --- Stage 6: LSE atomics (FEAT_LSE, ARMv8.1) -------------------------------
// Layout (LLVM AArch64InstrFormats.td 12333-12340):
//   SWP:  size(31-30) 111000(29-24) A(23) R(22) 1(21) Rs(20-16) 1(15)
//         OPC(14-12) 00(11-10) Rn(9-5) Rt(4-0), OPC = 000.
//   LDOP: as SWP with bit15 = 0 and OPC = LDADD 000 / LDCLR 001 / LDEOR 010 /
//         LDSET 011 / LDSMAX 100 / LDSMIN 101 / LDUMAX 110 / LDUMIN 111.
//   CAS:  size 001000(29-24) NP(23)=1 A(22) 1(21) Rs(20-16) R(15)
//         Rt2(14-10)=11111 Rn(9-5) Rt(4-0).
// Rs is the source value register, Rt the result register; both share the
// width class (W for sz 00-10, X for sz 11, CAS B/H are W-only), ZR allowed,
// SP rejected. Ordering folds into the A/R bits.

const arm64_order_plain: u64 = 0
const arm64_order_a: u64 = 1
const arm64_order_l: u64 = 2
const arm64_order_al: u64 = 3

// Stage 7: LSE byte/halfword sizes (sz = 00/01); data Rs/Rt must be W.
// Fixtures: llvm/test/MC/AArch64/armv8.1a-lse.s
//   swpb w0, w1, [x2] -> 0x38208041   casb w0, w1, [x2] -> 0x08a07c41
fn arm64_emit_lse_bh(size: u64, is_swap: bool, op3: u64, opname: string, rs: u64, rt: u64, rn: u64, order: u64) {
    assert(size == 0 || size == 1, sym.join(opname, ": size must be B or H"));
    assert(!arm64_reg_is64(rs), sym.join(opname, ": requires a W register"));
    assert(!arm64_reg_is64(rt), sym.join(opname, ": requires a W register"));
    arm64_emit_lse(size, is_swap, op3, rs, rn, rt, order, opname)
}

fn arm64_swpb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, true, 0, "swpb", rs, rt, rn, order)
}

fn arm64_swph(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, true, 0, "swph", rs, rt, rn, order)
}

fn arm64_casb(rs: u64, rt: u64, rn: u64, order: u64) {
    assert(order <= 3, "casb: ordering must be 0..3 (plain/a/l/al)");
    assert(!arm64_reg_is64(rs), "casb: requires a W register");
    assert(!arm64_reg_is64(rt), "casb: requires a W register");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn), "casb: base must be an X register or SP");
    assert(!arm64_reg_is_zr(rn), "casb: base cannot be ZR (reads SP)");
    arm64_check_no_sp(rs, "casb");
    arm64_check_no_sp(rt, "casb");
    let a: u64 = order & 1
    let r: u64 = (order >> 1) & 1
    emit.u32((0 << 30) | (0x8 << 24) | (1 << 23) | (a << 22) | (1 << 21)
        | ((rs & 0x1f) << 16) | (r << 15) | (0x1f << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

fn arm64_cash(rs: u64, rt: u64, rn: u64, order: u64) {
    assert(order <= 3, "cash: ordering must be 0..3 (plain/a/l/al)");
    assert(!arm64_reg_is64(rs), "cash: requires a W register");
    assert(!arm64_reg_is64(rt), "cash: requires a W register");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn), "cash: base must be an X register or SP");
    assert(!arm64_reg_is_zr(rn), "cash: base cannot be ZR (reads SP)");
    arm64_check_no_sp(rs, "cash");
    arm64_check_no_sp(rt, "cash");
    let a: u64 = order & 1
    let r: u64 = (order >> 1) & 1
    emit.u32((1 << 30) | (0x8 << 24) | (1 << 23) | (a << 22) | (1 << 21)
        | ((rs & 0x1f) << 16) | (r << 15) | (0x1f << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

fn arm64_ldaddb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 0, "ldaddb", rs, rt, rn, order)
}

fn arm64_ldaddh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 0, "ldaddh", rs, rt, rn, order)
}

fn arm64_ldclrb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 1, "ldclrb", rs, rt, rn, order)
}

fn arm64_ldclrh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 1, "ldclrh", rs, rt, rn, order)
}

fn arm64_ldeorb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 2, "ldeorb", rs, rt, rn, order)
}

fn arm64_ldeorh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 2, "ldeorh", rs, rt, rn, order)
}

fn arm64_ldsetb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 3, "ldsetb", rs, rt, rn, order)
}

fn arm64_ldseth(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 3, "ldseth", rs, rt, rn, order)
}

fn arm64_ldsmaxb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 4, "ldsmaxb", rs, rt, rn, order)
}

fn arm64_ldsmaxh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 4, "ldsmaxh", rs, rt, rn, order)
}

fn arm64_ldsminb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 5, "ldsminb", rs, rt, rn, order)
}

fn arm64_ldsminh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 5, "ldsminh", rs, rt, rn, order)
}

fn arm64_ldumaxb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 6, "ldumaxb", rs, rt, rn, order)
}

fn arm64_ldumaxh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 6, "ldumaxh", rs, rt, rn, order)
}

fn arm64_lduminb(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(0, false, 7, "lduminb", rs, rt, rn, order)
}

fn arm64_lduminh(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_lse_bh(1, false, 7, "lduminh", rs, rt, rn, order)
}

// --- Stage 8: CASP (compare and swap pair, FEAT_LSE) -------------------------
// LLVM BaseCASP = BaseCASEncoding with NP = 0: size(31-30) with W pair = 00
// and X pair = 01, 001000(29-24), A(22), 1(21), Rs(20-16), R(15),
// Rt2(14-10) = 11111, Rn(9-5), Rt(4-0). Rs is the expected/old even register
// (the pair adds +1), Rt the new even register; LLVM's pair operand classes
// accept only even GPRs (no ZR, no SP).

fn arm64_emit_casp(size: u64, want64: bool, opname: string, rs: u64, rt: u64, rn: u64, order: u64) {
    assert(order <= 3, sym.join(opname, ": ordering must be 0..3 (plain/a/l/al)"));
    if want64 {
        assert(arm64_reg_is64(rs), sym.join(opname, ": requires X pair registers"));
        assert(arm64_reg_is64(rt), sym.join(opname, ": requires X pair registers"));
    } else {
        assert(!arm64_reg_is64(rs), sym.join(opname, ": requires W pair registers"));
        assert(!arm64_reg_is64(rt), sym.join(opname, ": requires W pair registers"));
    }
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(opname, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(opname, ": base cannot be ZR (reads SP)"));
    arm64_check_no_sp(rs, opname);
    arm64_check_no_sp(rt, opname);
    assert(!arm64_reg_is_zr(rs), sym.join(opname, ": pair registers cannot be ZR"));
    assert(!arm64_reg_is_zr(rt), sym.join(opname, ": pair registers cannot be ZR"));
    assert(arm64_reg_number(rs) % 2 == 0, sym.join(opname, ": Rs must be an even register (pair = Rs, Rs+1)"));
    assert(arm64_reg_number(rt) % 2 == 0, sym.join(opname, ": Rt must be an even register (pair = Rt, Rt+1)"));
    arm64_check_same_width(rs, rt, opname);
    let a: u64 = order & 1
    let r: u64 = (order >> 1) & 1
    emit.u32((size << 30) | (0x8 << 24) | (a << 22) | (1 << 21)
        | ((rs & 0x1f) << 16) | (r << 15) | (0x1f << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// CASP (W pair, sz = 00). ARM ARM C6.2.172; LLVM CASPW (CompareAndSwapPair
// <0b00, ...>). Fixtures: llvm/test/MC/AArch64/armv8.1a-lse.s.
fn arm64_caspw(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_casp(0, false, "caspw", rs, rt, rn, order)
}

// CASP (X pair, sz = 01). LLVM CASPX (CompareAndSwapPair <0b01, ...>).
fn arm64_caspx(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_casp(1, true, "caspx", rs, rt, rn, order)
}

// --- Stage 9: LDAPR (RCpc load-acquire, FEAT_LRCPC / ARMv8.3) ----------------
// LLVM RCPCLoad: size(31-30) 111000(29-24) 1(23) 0(22) 1(21) Rs(20-16)=11111
// 1(15) 000(14-12) 00(11-10) Rn(9-5) Rt(4-0). The 11111 source field is a
// constant, so this shape gets its own emitter (the shared emit_lse would
// apply register-width checks to it).

fn arm64_emit_ldapr(size: u64, rn: u64, rt: u64, what: string) {
    assert(size <= 3, sym.join(what, ": size out of range"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(what, ": base cannot be ZR (reads SP)"));
    arm64_check_no_sp(rt, what);
    // Inst{29-10} fixed pattern from LLVM RCPCLoad, kept whole to avoid
    // field-split mistakes.
    emit.u32((size << 30) | (0b11100010111111110000 << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDAPR (W/X by Rt). ARM ARM C6.2.287; LLVM LDAPRW/LDAPRX.
fn arm64_ldapr(rt: u64, rn: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldapr(size, rn, rt, "ldapr")
}

// LDAPRB (W only). LLVM LDAPRB (sz = 00). Fixtures: armv8.3a-rcpc.s.
fn arm64_ldaprb(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldaprb requires a W register");
    arm64_emit_ldapr(0, rn, rt, "ldaprb")
}

// LDAPRH (W only). LLVM LDAPRH (sz = 01).
fn arm64_ldaprh(rt: u64, rn: u64) {
    assert(!arm64_reg_is64(rt), "ldaprh requires a W register");
    arm64_emit_ldapr(1, rn, rt, "ldaprh")
}

// --- Stage 10: LDAPUR/STLUR (unscaled RCpc, FEAT_LRCPC2 / ARMv8.4) -----------
// LLVM BaseLoadStoreUnscale with the V84 fixups Inst{29} = 0, Inst{24} = 1:
// size(31-30) 011(29-27) V=0(26) 01(25-24) opc(23-22) 0(21) imm9(20-12)
// 00(11-10) Rn(9-5) Rt(4-0). opc: 00 = store, 01 = load, 10 = sign-extend
// to X, 11 = sign-extend to W. Rn is GPR64sp; imm9 is unscaled -256..255.

fn arm64_emit_ldur_v84(size: u64, opc: u64, rt: u64, rn: u64, offset: u64, what: string) {
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(what, ": base cannot be ZR (reads SP)"));
    arm64_check_no_sp(rt, what);
    assert(offset < 0x100 || offset >= 0xffffffffffffff00,
        sym.join(what, ": offset out of range -256..255"));
    const imm9: u64 = offset & 0x1ff
    emit.u32((size << 30) | (0x3 << 27) | (1 << 24) | (opc << 22) | (imm9 << 12)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// LDAPURB (W only). LLVM LDAPURB (sz 00, opc 01). Fixtures: armv8.4a-ldst.s.
fn arm64_ldapurb(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldapurb requires a W register");
    arm64_emit_ldur_v84(0, 1, rt, rn, offset, "ldapurb")
}

// LDAPURH (W only). LLVM LDAPURH (sz 01, opc 01).
fn arm64_ldapurh(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "ldapurh requires a W register");
    arm64_emit_ldur_v84(1, 1, rt, rn, offset, "ldapurh")
}

// LDAPUR (W/X by Rt, opc 01). ARM ARM C6.2.286.
fn arm64_ldapur(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldur_v84(size, 1, rt, rn, offset, "ldapur")
}

// LDAPURSB (sign-extend byte; W form opc 11, X form opc 10 — the values are
// the 2-bit field patterns 0b11 / 0b10).
fn arm64_ldapursb(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 0
    let opc: u64 = 3
    if arm64_reg_is64(rt) {
        opc = 2
    }
    arm64_emit_ldur_v84(size, opc, rt, rn, offset, "ldapursb")
}

// LDAPURSH (sign-extend halfword; W form opc 0b11, X form opc 0b10).
fn arm64_ldapursh(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 1
    let opc: u64 = 3
    if arm64_reg_is64(rt) {
        opc = 2
    }
    arm64_emit_ldur_v84(size, opc, rt, rn, offset, "ldapursh")
}

// STLURB (W only, opc 00). LLVM STLURB.
fn arm64_stlurb(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "stlurb requires a W register");
    arm64_emit_ldur_v84(0, 0, rt, rn, offset, "stlurb")
}

// STLURH (W only, opc 00). LLVM STLURH.
fn arm64_stlurh(rt: u64, rn: u64, offset: u64) {
    assert(!arm64_reg_is64(rt), "stlurh requires a W register");
    arm64_emit_ldur_v84(1, 0, rt, rn, offset, "stlurh")
}

// STLUR (W/X by Rt, opc 00). ARM ARM C6.2.353.
fn arm64_stlur(rt: u64, rn: u64, offset: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_ldur_v84(size, 0, rt, rn, offset, "stlur")
}

fn arm64_emit_lse(size: u64, is_swap: bool, op3: u64, rs: u64, rn: u64, rt: u64, order: u64, what: string) {
    assert(order <= 3, sym.join(what, ": ordering must be 0..3 (plain/a/l/al)"));
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        sym.join(what, ": base must be an X register or SP"));
    assert(!arm64_reg_is_zr(rn), sym.join(what, ": base cannot be ZR (reads SP)"));
    arm64_check_no_sp(rs, what);
    arm64_check_no_sp(rt, what);
    arm64_check_same_width(rs, rt, what);
    let a: u64 = order & 1
    let r: u64 = (order >> 1) & 1
    let s: u64 = 0
    if is_swap {
        s = 1
    }
    emit.u32((size << 30) | (0x38 << 24) | (a << 23) | (r << 22) | (1 << 21)
        | ((rs & 0x1f) << 16) | (s << 15) | ((op3 & 7) << 12)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}

// SWP (swap, W/X by Rt). ARM ARM C6.2.459; LLVM BaseSWP (OPC = 000, bit15 = 1).
// Fixtures: llvm/test/MC/AArch64/armv8.1a-lse.s
//   swp w0, w1, [x2] -> 0xb8208041   swpal x2, x3, [sp] -> 0xf8e283e3
fn arm64_swp(rs: u64, rt: u64, rn: u64, order: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_lse(size, true, 0, rs, rn, rt, order, "swp")
}

fn arm64_emit_ldop(op3: u64, opname: string, rs: u64, rt: u64, rn: u64, order: u64) {
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    arm64_emit_lse(size, false, op3, rs, rn, rt, order, opname)
}

// LDADD (atomic add, result = old value). ARM ARM C6.2.213.
// Fixtures: ldadd w0, w1, [x2] -> 0xb8200041   ldadd x2, x3, [sp] -> 0xf82203e3
fn arm64_ldadd(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(0, "ldadd", rs, rt, rn, order)
}

// LDCLR (atomic bit clear). Fixture: ldclr w0, w1, [x2] -> 0xb8201041.
fn arm64_ldclr(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(1, "ldclr", rs, rt, rn, order)
}

// LDEOR (atomic xor). Fixture: ldeor w0, w1, [x2] -> 0xb8202041.
fn arm64_ldeor(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(2, "ldeor", rs, rt, rn, order)
}

// LDSET (atomic bit set). Fixture: ldset w0, w1, [x2] -> 0xb8203041.
fn arm64_ldset(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(3, "ldset", rs, rt, rn, order)
}

// LDSMAX (atomic signed max). Fixture: ldsmax w0, w1, [x2] -> 0xb8204041.
fn arm64_ldsmax(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(4, "ldsmax", rs, rt, rn, order)
}

// LDSMIN (atomic signed min). Fixture: ldsmin w0, w1, [x2] -> 0xb8205041.
fn arm64_ldsmin(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(5, "ldsmin", rs, rt, rn, order)
}

// LDUMAX (atomic unsigned max). Fixture: ldumax w0, w1, [x2] -> 0xb8206041.
fn arm64_ldumax(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(6, "ldumax", rs, rt, rn, order)
}

// LDUMIN (atomic unsigned min). Fixture: ldumin w0, w1, [x2] -> 0xb8207041.
fn arm64_ldumin(rs: u64, rt: u64, rn: u64, order: u64) {
    arm64_emit_ldop(7, "ldumin", rs, rt, rn, order)
}

// CAS (compare and swap). ARM ARM C6.2.171; LLVM BaseCAS (NP = 1).
// Rs = expected (in) / old value (out), Rt = new value; W forms take W
// registers with sz 00/01/10, X forms sz 11.
// Fixtures: llvm/test/MC/AArch64/armv8.1a-lse.s
//   cas w0, w1, [x2] -> 0x88a07c41   casal w0, w1, [x2] -> 0x88e0fc41
//   casb w0, w1, [x2] -> 0x08a07c41
fn arm64_cas(rs: u64, rt: u64, rn: u64, order: u64) {
    assert(order <= 3, "cas: ordering must be 0..3 (plain/a/l/al)");
    assert(arm64_reg_is64(rn) || arm64_reg_is_sp(rn),
        "cas: base must be an X register or SP");
    assert(!arm64_reg_is_zr(rn), "cas: base cannot be ZR (reads SP)");
    arm64_check_no_sp(rs, "cas");
    arm64_check_no_sp(rt, "cas");
    arm64_check_same_width(rs, rt, "cas");
    let size: u64 = 2
    if arm64_reg_is64(rt) {
        size = 3
    }
    let a: u64 = order & 1
    let r: u64 = (order >> 1) & 1
    emit.u32((size << 30) | (0x8 << 24) | (1 << 23) | (a << 22) | (1 << 21)
        | ((rs & 0x1f) << 16) | (r << 15) | (0x1f << 10)
        | (arm64_reg_number(rn) << 5) | arm64_reg_number(rt))
}
