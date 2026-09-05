// M4.6 stage 1: plain exclusive load/store (LDXR/STXR), W and X widths.
//
// Field layout (LLVM AArch64InstrFormats.td, BaseLoadStoreExclusive):
//   size(31-30) 001000(29-24) o2(23)=0 L(22) o1(21)=0 Rs(20-16) o0(15)=0
//   Rt2(14-10)=11111 Rn(9-5) Rt(4-0).
// LDXR: LoadExclusive <sz, 0, 1, 0, 0> with Rs = 11111; STXR: StoreExclusive
// <sz, 0, 0, 0, 0> with Ws = Inst{20-16} (a W register; ZR allowed).
// Fixture words: llvm/test/MC/AArch64/basic-a64-instructions.s
//   (ldxr w9 / ldxr x10 / stxr wzr,w4 / stxr w5,x6), re-assembled from the
//   same GNU source with clang --target=aarch64 (words matched 4/4).
import("arm/arm64.inc")

insn_ldxr_w:
arm64_ldxr(arm64_w9, arm64_sp)
insn_ldxr_x:
arm64_ldxr(arm64_x10, arm64_x11)
insn_stxr_w:
arm64_stxr(arm64_wzr, arm64_w4, arm64_sp)
insn_stxr_x:
arm64_stxr(arm64_w5, arm64_x6, arm64_x7)

// Stage 2: exclusive pair (LDXP/STXP), o1=1 with a real Rt2 field.
// LDXPW/LDXPX = LoadExclusivePair <sz, 0, 1, 1, 0>, Rs = 11111;
// STXPW/STXPX = StoreExclusivePair <sz, 0, 0, 1, 0>, Ws = Inst{20-16}.
// Pair registers must be all-W or all-X; ZR allowed, SP not.
insn_ldxp_w:
arm64_ldxp(arm64_w12, arm64_wzr, arm64_sp)
insn_ldxp_x:
arm64_ldxp(arm64_x13, arm64_x14, arm64_x15)
insn_stxp_w:
arm64_stxp(arm64_w11, arm64_w12, arm64_w13, arm64_x14)
insn_stxp_x:
arm64_stxp(arm64_wzr, arm64_x23, arm64_x14, arm64_x15)

// Stage 3: ordered load/store (LDAR/STLR), o2=1 and o0=1 (bits 23/15).
// LDARW/LDARX = LoadAcquire <sz, 1, 1, 0, 1>;
// STLRW/STLRX = StoreRelease <sz, 1, 0, 0, 1>. Rs = Rt2 = 11111.
insn_ldar_w:
arm64_ldar(arm64_w1, arm64_x2)
insn_ldar_x:
arm64_ldar(arm64_x3, arm64_x4)
insn_stlr_w:
arm64_stlr(arm64_w5, arm64_x6)
insn_stlr_x:
arm64_stlr(arm64_x7, arm64_x8)

// Stage 4: acquire/release exclusives, o0=1 (bit 15) with o2=0.
// LDAXRW/LDAXRX = LoadExclusive <sz, 0, 1, 0, 1>;
// STLXRW/STLXRX = StoreExclusive <sz, 0, 0, 0, 1>;
// LDAXPW/LDAXPX = LoadExclusivePair <sz, 0, 1, 1, 1>;
// STLXPW/STLXPX = StoreExclusivePair <sz, 0, 0, 1, 1>.
insn_ldaxr_w:
arm64_ldaxr(arm64_w9, arm64_x10)
insn_ldaxr_x:
arm64_ldaxr(arm64_x11, arm64_x12)
insn_stlxr_w:
arm64_stlxr(arm64_w13, arm64_w14, arm64_x15)
insn_stlxr_x:
arm64_stlxr(arm64_w16, arm64_x17, arm64_x18)
insn_ldaxp_w:
arm64_ldaxp(arm64_w19, arm64_w20, arm64_x21)
insn_ldaxp_x:
arm64_ldaxp(arm64_x22, arm64_x23, arm64_x24)
insn_stlxp_x:
arm64_stlxp(arm64_w25, arm64_x26, arm64_x27, arm64_x28)

// Stage 5: byte/halfword variants (sz = 00/01); data Rt must be W.
insn_ldxrb_w:
arm64_ldxrb(arm64_w7, arm64_x9)
insn_ldxrh_w:
arm64_ldxrh(arm64_wzr, arm64_x10)
insn_stxrb_w:
arm64_stxrb(arm64_w1, arm64_w2, arm64_x3)
insn_stxrh_w:
arm64_stxrh(arm64_w2, arm64_w3, arm64_x4)
insn_ldaxrb_w:
arm64_ldaxrb(arm64_w19, arm64_x21)
insn_ldaxrh_w:
arm64_ldaxrh(arm64_w20, arm64_sp)
insn_stlxrb_w:
arm64_stlxrb(arm64_w14, arm64_w15, arm64_x16)
insn_stlxrh_w:
arm64_stlxrh(arm64_w15, arm64_w16, arm64_x17)
insn_ldarb_w:
arm64_ldarb(arm64_w29, arm64_sp)
insn_ldarh_w:
arm64_ldarh(arm64_w30, arm64_x0)
insn_stlrb_w:
arm64_stlrb(arm64_w27, arm64_sp)
insn_stlrh_w:
arm64_stlrh(arm64_w28, arm64_x0)

// Stage 6: LSE atomics (FEAT_LSE). SWP: 111000 A R 1 Rs 1 OPC=000 00 Rn Rt;
// LDOP: bit15=0 with OPC = LDADD 000 / LDCLR 001 / LDEOR 010 / LDSET 011 /
// LDSMAX 100 / LDSMIN 101 / LDUMAX 110 / LDUMIN 111; ordering folds into
// A/R via arm64_order_plain/a/l/al.
insn_swp_w:
arm64_swp(arm64_w0, arm64_w1, arm64_x2, arm64_order_plain)
insn_swp_w_a:
arm64_swp(arm64_w0, arm64_w1, arm64_x2, arm64_order_a)
insn_swp_w_l:
arm64_swp(arm64_w0, arm64_w1, arm64_x2, arm64_order_l)
insn_swp_w_al:
arm64_swp(arm64_w0, arm64_w1, arm64_x2, arm64_order_al)
insn_swp_x_al:
arm64_swp(arm64_x2, arm64_x3, arm64_sp, arm64_order_al)
insn_cas_w:
arm64_cas(arm64_w0, arm64_w1, arm64_x2, arm64_order_plain)
insn_cas_w_al:
arm64_cas(arm64_w0, arm64_w1, arm64_x2, arm64_order_al)
insn_cas_x_l:
arm64_cas(arm64_x0, arm64_x1, arm64_x2, arm64_order_l)
insn_ldadd_w:
arm64_ldadd(arm64_w0, arm64_w1, arm64_x2, arm64_order_plain)
insn_ldadd_x:
arm64_ldadd(arm64_x2, arm64_x3, arm64_sp, arm64_order_plain)
insn_ldclr_x:
arm64_ldclr(arm64_x0, arm64_x1, arm64_x2, arm64_order_plain)
insn_ldeor_w:
arm64_ldeor(arm64_w2, arm64_w3, arm64_sp, arm64_order_plain)
insn_ldset_x:
arm64_ldset(arm64_x0, arm64_x1, arm64_x2, arm64_order_plain)
insn_ldsmax_w_a:
arm64_ldsmax(arm64_w0, arm64_w1, arm64_x2, arm64_order_a)
insn_ldsmin_x_l:
arm64_ldsmin(arm64_x0, arm64_x1, arm64_x2, arm64_order_l)
insn_ldumax_w:
arm64_ldumax(arm64_w0, arm64_w1, arm64_x2, arm64_order_plain)
insn_ldumin_x_al:
arm64_ldumin(arm64_x0, arm64_x1, arm64_x2, arm64_order_al)

// Stage 7: LSE byte/halfword sizes (sz 00/01); Rs/Rt must be W.
// Fixtures: armv8.1a-lse.s (swpb 0x38208041 / casb 0x08a07c41 patterns).
insn_swpb_w:
arm64_swpb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_swph_w:
arm64_swph(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_casb_w:
arm64_casb(arm64_w0, arm64_w1, arm64_x2, arm64_order_plain)
insn_casb_w_al:
arm64_casb(arm64_w0, arm64_w1, arm64_x2, arm64_order_al)
insn_cash_w_a:
arm64_cash(arm64_w3, arm64_w4, arm64_x5, arm64_order_a)
insn_ldaddb_w:
arm64_ldaddb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_ldaddh_w_a:
arm64_ldaddh(arm64_w4, arm64_w5, arm64_x6, arm64_order_a)
insn_ldclrb_w:
arm64_ldclrb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_ldeorh_w_l:
arm64_ldeorh(arm64_w4, arm64_w5, arm64_x6, arm64_order_l)
insn_ldsetb_w:
arm64_ldsetb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_ldsmaxb_w:
arm64_ldsmaxb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_ldsminh_w:
arm64_ldsminh(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_ldumaxb_w:
arm64_ldumaxb(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)
insn_lduminh_w:
arm64_lduminh(arm64_w4, arm64_w5, arm64_x6, arm64_order_plain)

// Stage 8: CASP (compare and swap pair). W pair sz=00, X pair sz=01;
// NP=0; Rs/Rt are even registers (the pair adds +1), no ZR/SP.
insn_casp_w:
arm64_caspw(arm64_w10, arm64_w12, arm64_x14, arm64_order_plain)
insn_casp_x_al:
arm64_caspx(arm64_x0, arm64_x2, arm64_x4, arm64_order_al)

// Stage 9: LDAPR (RCpc load-acquire, v8.3) — the LSE swap shape with a
// fixed 11111 source, A=1/R=0. LLVM RCPCLoad.
insn_ldapr_w:
arm64_ldapr(arm64_w0, arm64_x2)
insn_ldapr_x:
arm64_ldapr(arm64_x1, arm64_x3)
insn_ldaprb_w:
arm64_ldaprb(arm64_w4, arm64_x5)
insn_ldaprh_w:
arm64_ldaprh(arm64_w6, arm64_sp)

// Stage 10: LDAPUR/STLUR (unscaled RCpc, v8.4) — LDUR shape with 011/01
// fixups; opc 00=store, 01=load, 10=sext→X, 11=sext→W; imm9 -256..255.
insn_ldapurb_w:
arm64_ldapurb(arm64_w0, arm64_x1, -8)
insn_ldapurh_w:
arm64_ldapurh(arm64_w2, arm64_x3, 0)
insn_ldapur_w:
arm64_ldapur(arm64_x4, arm64_x5, 255)
insn_ldapursb_x:
arm64_ldapursb(arm64_x6, arm64_x7, -1)
insn_ldapursh_w:
arm64_ldapursh(arm64_w8, arm64_x9, 7)
insn_stlurb_w:
arm64_stlurb(arm64_w10, arm64_x11, -256)
insn_stlurh_w:
arm64_stlurh(arm64_w12, arm64_x13, 0)
insn_stlur_x:
arm64_stlur(arm64_x14, arm64_x15, 100)

defer {
    // Assert lines generated mechanically by mkwords.sh from the stage
    // corpus (clang --target=aarch64 object bytes; corpus fixture words
    // match).
    assert(load.u32(insn_ldxr_w) == 0x885f7fe9, "ldxr w9, [sp]");
    assert(load.u32(insn_ldxr_x) == 0xc85f7d6a, "ldxr x10, [x11]");
    assert(load.u32(insn_stxr_w) == 0x881f7fe4, "stxr wzr, w4, [sp]");
    assert(load.u32(insn_stxr_x) == 0xc8057ce6, "stxr w5, x6, [x7]");
    assert(load.u32(insn_ldxp_w) == 0x887f7fec, "ldxp w12, wzr, [sp]");
    assert(load.u32(insn_ldxp_x) == 0xc87f39ed, "ldxp x13, x14, [x15]");
    assert(load.u32(insn_stxp_w) == 0x882b35cc, "stxp w11, w12, w13, [x14]");
    assert(load.u32(insn_stxp_x) == 0xc83f39f7, "stxp wzr, x23, x14, [x15]");
    assert(load.u32(insn_ldar_w) == 0x88dffc41, "ldar w1, [x2]");
    assert(load.u32(insn_ldar_x) == 0xc8dffc83, "ldar x3, [x4]");
    assert(load.u32(insn_stlr_w) == 0x889ffcc5, "stlr w5, [x6]");
    assert(load.u32(insn_stlr_x) == 0xc89ffd07, "stlr x7, [x8]");
    assert(load.u32(insn_ldaxr_w) == 0x885ffd49, "ldaxr w9, [x10]");
    assert(load.u32(insn_ldaxr_x) == 0xc85ffd8b, "ldaxr x11, [x12]");
    assert(load.u32(insn_stlxr_w) == 0x880dfdee, "stlxr w13, w14, [x15]");
    assert(load.u32(insn_stlxr_x) == 0xc810fe51, "stlxr w16, x17, [x18]");
    assert(load.u32(insn_ldaxp_w) == 0x887fd2b3, "ldaxp w19, w20, [x21]");
    assert(load.u32(insn_ldaxp_x) == 0xc87fdf16, "ldaxp x22, x23, [x24]");
    assert(load.u32(insn_stlxp_x) == 0xc839ef9a, "stlxp w25, x26, x27, [x28]");
    assert(load.u32(insn_ldxrb_w) == 0x085f7d27, "ldxrb w7, [x9]");
    assert(load.u32(insn_ldxrh_w) == 0x485f7d5f, "ldxrh wzr, [x10]");
    assert(load.u32(insn_stxrb_w) == 0x08017c62, "stxrb w1, w2, [x3]");
    assert(load.u32(insn_stxrh_w) == 0x48027c83, "stxrh w2, w3, [x4]");
    assert(load.u32(insn_ldaxrb_w) == 0x085ffeb3, "ldaxrb w19, [x21]");
    assert(load.u32(insn_ldaxrh_w) == 0x485ffff4, "ldaxrh w20, [sp]");
    assert(load.u32(insn_stlxrb_w) == 0x080efe0f, "stlxrb w14, w15, [x16]");
    assert(load.u32(insn_stlxrh_w) == 0x480ffe30, "stlxrh w15, w16, [x17]");
    assert(load.u32(insn_ldarb_w) == 0x08dffffd, "ldarb w29, [sp]");
    assert(load.u32(insn_ldarh_w) == 0x48dffc1e, "ldarh w30, [x0]");
    assert(load.u32(insn_stlrb_w) == 0x089ffffb, "stlrb w27, [sp]");
    assert(load.u32(insn_stlrh_w) == 0x489ffc1c, "stlrh w28, [x0]");
    assert(load.u32(insn_swp_w) == 0xb8208041, "swp w0, w1, [x2]");
    assert(load.u32(insn_swp_w_a) == 0xb8a08041, "swpa w0, w1, [x2]");
    assert(load.u32(insn_swp_w_l) == 0xb8608041, "swpl w0, w1, [x2]");
    assert(load.u32(insn_swp_w_al) == 0xb8e08041, "swpal w0, w1, [x2]");
    assert(load.u32(insn_swp_x_al) == 0xf8e283e3, "swpal x2, x3, [sp]");
    assert(load.u32(insn_cas_w) == 0x88a07c41, "cas w0, w1, [x2]");
    assert(load.u32(insn_cas_w_al) == 0x88e0fc41, "casal w0, w1, [x2]");
    assert(load.u32(insn_cas_x_l) == 0xc8a0fc41, "casl x0, x1, [x2]");
    assert(load.u32(insn_ldadd_w) == 0xb8200041, "ldadd w0, w1, [x2]");
    assert(load.u32(insn_ldadd_x) == 0xf82203e3, "ldadd x2, x3, [sp]");
    assert(load.u32(insn_ldclr_x) == 0xf8201041, "ldclr x0, x1, [x2]");
    assert(load.u32(insn_ldeor_w) == 0xb82223e3, "ldeor w2, w3, [sp]");
    assert(load.u32(insn_ldset_x) == 0xf8203041, "ldset x0, x1, [x2]");
    assert(load.u32(insn_ldsmax_w_a) == 0xb8a04041, "ldsmaxa w0, w1, [x2]");
    assert(load.u32(insn_ldsmin_x_l) == 0xf8605041, "ldsminl x0, x1, [x2]");
    assert(load.u32(insn_ldumax_w) == 0xb8206041, "ldumax w0, w1, [x2]");
    assert(load.u32(insn_ldumin_x_al) == 0xf8e07041, "lduminal x0, x1, [x2]");
    assert(load.u32(insn_swpb_w) == 0x382480c5, "swpb w4, w5, [x6]");
    assert(load.u32(insn_swph_w) == 0x782480c5, "swph w4, w5, [x6]");
    assert(load.u32(insn_casb_w) == 0x08a07c41, "casb w0, w1, [x2]");
    assert(load.u32(insn_casb_w_al) == 0x08e0fc41, "casalb w0, w1, [x2]");
    assert(load.u32(insn_cash_w_a) == 0x48e37ca4, "casah w3, w4, [x5]");
    assert(load.u32(insn_ldaddb_w) == 0x382400c5, "ldaddb w4, w5, [x6]");
    assert(load.u32(insn_ldaddh_w_a) == 0x78a400c5, "ldaddah w4, w5, [x6]");
    assert(load.u32(insn_ldclrb_w) == 0x382410c5, "ldclrb w4, w5, [x6]");
    assert(load.u32(insn_ldeorh_w_l) == 0x786420c5, "ldeorlh w4, w5, [x6]");
    assert(load.u32(insn_ldsetb_w) == 0x382430c5, "ldsetb w4, w5, [x6]");
    assert(load.u32(insn_ldsmaxb_w) == 0x382440c5, "ldsmaxb w4, w5, [x6]");
    assert(load.u32(insn_ldsminh_w) == 0x782450c5, "ldsminh w4, w5, [x6]");
    assert(load.u32(insn_ldumaxb_w) == 0x382460c5, "ldumaxb w4, w5, [x6]");
    assert(load.u32(insn_lduminh_w) == 0x782470c5, "lduminh w4, w5, [x6]");
    assert(load.u32(insn_casp_w) == 0x082a7dcc, "casp w10, w11, w12, w13, [x14]");
    assert(load.u32(insn_casp_x_al) == 0x4860fc82, "caspal x0, x1, x2, x3, [x4]");
    assert(load.u32(insn_ldapr_w) == 0xb8bfc040, "ldapr w0, [x2]");
    assert(load.u32(insn_ldapr_x) == 0xf8bfc061, "ldapr x1, [x3]");
    assert(load.u32(insn_ldaprb_w) == 0x38bfc0a4, "ldaprb w4, [x5]");
    assert(load.u32(insn_ldaprh_w) == 0x78bfc3e6, "ldaprh w6, [sp]");
    assert(load.u32(insn_ldapurb_w) == 0x195f8020, "ldapurb w0, [x1, #-8]");
    assert(load.u32(insn_ldapurh_w) == 0x59400062, "ldapurh w2, [x3]");
    assert(load.u32(insn_ldapur_w) == 0xd94ff0a4, "ldapur x4, [x5, #255]");
    assert(load.u32(insn_ldapursb_x) == 0x199ff0e6, "ldapursb x6, [x7, #-1]");
    assert(load.u32(insn_ldapursh_w) == 0x59c07128, "ldapursh w8, [x9, #7]");
    assert(load.u32(insn_stlurb_w) == 0x1910016a, "stlurb w10, [x11, #-256]");
    assert(load.u32(insn_stlurh_w) == 0x590001ac, "stlurh w12, [x13]");
    assert(load.u32(insn_stlur_x) == 0xd90641ee, "stlur x14, [x15, #100]");
}
