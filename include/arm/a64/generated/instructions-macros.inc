// Generated statement macros; one owner per mnemonic.

macro abs(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "abs")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 263170 || key == 263683 {
        a64_e5_abs_shape(shaped)
        a64_e5_abs(a64_operands(args, false, false, true, false, "abs"))
    } else {
        a64_abs_shape(shaped)
        a64_abs(a64_operands(args, false, false, true, false, "abs"))
    }
}

macro adc(...args) {
    a64_adc_shape(a64_operands(args, false, false, false, false, "adc"))
    a64_adc(a64_operands(args, false, false, true, false, "adc"))
}

macro adcs(...args) {
    a64_adcs_shape(a64_operands(args, false, false, false, false, "adcs"))
    a64_adcs(a64_operands(args, false, false, true, false, "adcs"))
}

macro add(...args) {
    a64_add_shape(a64_operands(args, false, false, false, false, "add"))
    a64_add(a64_operands(args, false, false, true, false, "add"))
}

macro addg(...args) {
    a64_addg_shape(a64_operands(args, false, false, false, false, "addg"))
    a64_addg(a64_operands(args, false, false, true, false, "addg"))
}

macro addhn(...args) {
    a64_addhn_shape(a64_operands(args, false, false, false, false, "addhn"))
    a64_addhn(a64_operands(args, false, false, true, false, "addhn"))
}

macro addhn2(...args) {
    a64_addhn2_shape(a64_operands(args, false, false, false, false, "addhn2"))
    a64_addhn2(a64_operands(args, false, false, true, false, "addhn2"))
}

macro addp(...args) {
    a64_addp_shape(a64_operands(args, false, false, false, false, "addp"))
    a64_addp(a64_operands(args, false, false, true, false, "addp"))
}

macro adds(...args) {
    a64_adds_shape(a64_operands(args, false, false, false, false, "adds"))
    a64_adds(a64_operands(args, false, false, true, false, "adds"))
}

macro addv(...args) {
    a64_addv_shape(a64_operands(args, false, false, false, false, "addv"))
    a64_addv(a64_operands(args, false, false, true, false, "addv"))
}

macro adr(...args) {
    a64_adr_shape(a64_operands(args, false, false, false, true, "adr"))
    a64_adr(a64_operands(args, false, false, true, true, "adr"))
}

macro adrp(...args) {
    a64_adrp_shape(a64_operands(args, false, false, false, true, "adrp"))
    a64_adrp(a64_operands(args, false, false, true, true, "adrp"))
}

macro aesd(...args) {
    a64_aesd_shape(a64_operands(args, false, false, false, false, "aesd"))
    a64_aesd(a64_operands(args, false, false, true, false, "aesd"))
}

macro aese(...args) {
    a64_aese_shape(a64_operands(args, false, false, false, false, "aese"))
    a64_aese(a64_operands(args, false, false, true, false, "aese"))
}

macro aesimc(...args) {
    a64_aesimc_shape(a64_operands(args, false, false, false, false, "aesimc"))
    a64_aesimc(a64_operands(args, false, false, true, false, "aesimc"))
}

macro aesmc(...args) {
    a64_aesmc_shape(a64_operands(args, false, false, false, false, "aesmc"))
    a64_aesmc(a64_operands(args, false, false, true, false, "aesmc"))
}

macro and(...args) {
    a64_and_shape(a64_operands(args, false, false, false, false, "and"))
    a64_and(a64_operands(args, false, false, true, false, "and"))
}

macro ands(...args) {
    a64_ands_shape(a64_operands(args, false, false, false, false, "ands"))
    a64_ands(a64_operands(args, false, false, true, false, "ands"))
}

macro asr(...args) {
    a64_asr_shape(a64_operands(args, false, false, false, false, "asr"))
    a64_asr(a64_operands(args, false, false, true, false, "asr"))
}

macro asrv(...args) {
    a64_asrv_shape(a64_operands(args, false, false, false, false, "asrv"))
    a64_asrv(a64_operands(args, false, false, true, false, "asrv"))
}

macro at(...args) {
    a64_at_shape(a64_operands(args, false, false, false, false, "at"))
    a64_at(a64_operands(args, false, false, true, false, "at"))
}

macro autda(...args) {
    a64_autda_shape(a64_operands(args, false, false, false, false, "autda"))
    a64_autda(a64_operands(args, false, false, true, false, "autda"))
}

macro autdb(...args) {
    a64_autdb_shape(a64_operands(args, false, false, false, false, "autdb"))
    a64_autdb(a64_operands(args, false, false, true, false, "autdb"))
}

macro autdza(...args) {
    a64_autdza_shape(a64_operands(args, false, false, false, false, "autdza"))
    a64_autdza(a64_operands(args, false, false, true, false, "autdza"))
}

macro autdzb(...args) {
    a64_autdzb_shape(a64_operands(args, false, false, false, false, "autdzb"))
    a64_autdzb(a64_operands(args, false, false, true, false, "autdzb"))
}

macro autia(...args) {
    a64_autia_shape(a64_operands(args, false, false, false, false, "autia"))
    a64_autia(a64_operands(args, false, false, true, false, "autia"))
}

macro autia1716(...args) {
    a64_autia1716_shape(a64_operands(args, false, false, false, false, "autia1716"))
    a64_autia1716(a64_operands(args, false, false, true, false, "autia1716"))
}

macro autiasp(...args) {
    a64_autiasp_shape(a64_operands(args, false, false, false, false, "autiasp"))
    a64_autiasp(a64_operands(args, false, false, true, false, "autiasp"))
}

macro autiaz(...args) {
    a64_autiaz_shape(a64_operands(args, false, false, false, false, "autiaz"))
    a64_autiaz(a64_operands(args, false, false, true, false, "autiaz"))
}

macro autib(...args) {
    a64_autib_shape(a64_operands(args, false, false, false, false, "autib"))
    a64_autib(a64_operands(args, false, false, true, false, "autib"))
}

macro autib1716(...args) {
    a64_autib1716_shape(a64_operands(args, false, false, false, false, "autib1716"))
    a64_autib1716(a64_operands(args, false, false, true, false, "autib1716"))
}

macro autibsp(...args) {
    a64_autibsp_shape(a64_operands(args, false, false, false, false, "autibsp"))
    a64_autibsp(a64_operands(args, false, false, true, false, "autibsp"))
}

macro autibz(...args) {
    a64_autibz_shape(a64_operands(args, false, false, false, false, "autibz"))
    a64_autibz(a64_operands(args, false, false, true, false, "autibz"))
}

macro autiza(...args) {
    a64_autiza_shape(a64_operands(args, false, false, false, false, "autiza"))
    a64_autiza(a64_operands(args, false, false, true, false, "autiza"))
}

macro autizb(...args) {
    a64_autizb_shape(a64_operands(args, false, false, false, false, "autizb"))
    a64_autizb(a64_operands(args, false, false, true, false, "autizb"))
}

macro axflag(...args) {
    a64_axflag_shape(a64_operands(args, false, false, false, false, "axflag"))
    a64_axflag(a64_operands(args, false, false, true, false, "axflag"))
}

macro b(...args) {
    a64_b_shape(a64_operands(args, false, false, false, true, "b"))
    a64_b(a64_operands(args, false, false, true, true, "b"))
}

macro b.eq(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("eq"), list.get(parsed, 0)))
}

macro b.ne(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("ne"), list.get(parsed, 0)))
}

macro b.cs(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("cs"), list.get(parsed, 0)))
}

macro b.cc(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("cc"), list.get(parsed, 0)))
}

macro b.mi(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("mi"), list.get(parsed, 0)))
}

macro b.pl(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("pl"), list.get(parsed, 0)))
}

macro b.vs(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("vs"), list.get(parsed, 0)))
}

macro b.vc(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("vc"), list.get(parsed, 0)))
}

macro b.hi(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("hi"), list.get(parsed, 0)))
}

macro b.ls(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("ls"), list.get(parsed, 0)))
}

macro b.ge(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("ge"), list.get(parsed, 0)))
}

macro b.lt(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("lt"), list.get(parsed, 0)))
}

macro b.gt(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("gt"), list.get(parsed, 0)))
}

macro b.le(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("le"), list.get(parsed, 0)))
}

macro b.al(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("al"), list.get(parsed, 0)))
}

macro b.nv(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("nv"), list.get(parsed, 0)))
}

macro b.hs(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("hs"), list.get(parsed, 0)))
}

macro b.lo(target) {
    const parsed: list = a64_operands(list.of(target), false, false, true, true, "b_cond_target")
    a64_b_cond(list.of(a64_cond("lo"), list.get(parsed, 0)))
}

macro bcax(...args) {
    a64_bcax_shape(a64_operands(args, false, false, false, false, "bcax"))
    a64_bcax(a64_operands(args, false, false, true, false, "bcax"))
}

macro bfc(...args) {
    a64_bfc_shape(a64_operands(args, false, false, false, false, "bfc"))
    a64_bfc(a64_operands(args, false, false, true, false, "bfc"))
}

macro bfcvt(...args) {
    a64_bfcvt_shape(a64_operands(args, false, false, false, false, "bfcvt"))
    a64_bfcvt(a64_operands(args, false, false, true, false, "bfcvt"))
}

macro bfcvtn(...args) {
    a64_bfcvtn_shape(a64_operands(args, false, false, false, false, "bfcvtn"))
    a64_bfcvtn(a64_operands(args, false, false, true, false, "bfcvtn"))
}

macro bfcvtn2(...args) {
    a64_bfcvtn2_shape(a64_operands(args, false, false, false, false, "bfcvtn2"))
    a64_bfcvtn2(a64_operands(args, false, false, true, false, "bfcvtn2"))
}

macro bfdot(...args) {
    a64_bfdot_shape(a64_operands(args, false, false, false, false, "bfdot"))
    a64_bfdot(a64_operands(args, false, false, true, false, "bfdot"))
}

macro bfi(...args) {
    a64_bfi_shape(a64_operands(args, false, false, false, false, "bfi"))
    a64_bfi(a64_operands(args, false, false, true, false, "bfi"))
}

macro bfm(...args) {
    a64_bfm_shape(a64_operands(args, false, false, false, false, "bfm"))
    a64_bfm(a64_operands(args, false, false, true, false, "bfm"))
}

macro bfmlalb(...args) {
    a64_bfmlalb_shape(a64_operands(args, false, false, false, false, "bfmlalb"))
    a64_bfmlalb(a64_operands(args, false, false, true, false, "bfmlalb"))
}

macro bfmlalt(...args) {
    a64_bfmlalt_shape(a64_operands(args, false, false, false, false, "bfmlalt"))
    a64_bfmlalt(a64_operands(args, false, false, true, false, "bfmlalt"))
}

macro bfmmla(...args) {
    a64_bfmmla_shape(a64_operands(args, false, false, false, false, "bfmmla"))
    a64_bfmmla(a64_operands(args, false, false, true, false, "bfmmla"))
}

macro bfxil(...args) {
    a64_bfxil_shape(a64_operands(args, false, false, false, false, "bfxil"))
    a64_bfxil(a64_operands(args, false, false, true, false, "bfxil"))
}

macro bic(...args) {
    a64_bic_shape(a64_operands(args, false, false, false, false, "bic"))
    a64_bic(a64_operands(args, false, false, true, false, "bic"))
}

macro bics(...args) {
    a64_bics_shape(a64_operands(args, false, false, false, false, "bics"))
    a64_bics(a64_operands(args, false, false, true, false, "bics"))
}

macro bif(...args) {
    a64_bif_shape(a64_operands(args, false, false, false, false, "bif"))
    a64_bif(a64_operands(args, false, false, true, false, "bif"))
}

macro bit(...args) {
    a64_bit_shape(a64_operands(args, false, false, false, false, "bit"))
    a64_bit(a64_operands(args, false, false, true, false, "bit"))
}

macro bl(...args) {
    a64_bl_shape(a64_operands(args, false, false, false, true, "bl"))
    a64_bl(a64_operands(args, false, false, true, true, "bl"))
}

macro blr(...args) {
    a64_blr_shape(a64_operands(args, false, false, false, false, "blr"))
    a64_blr(a64_operands(args, false, false, true, false, "blr"))
}

macro blraa(...args) {
    a64_blraa_shape(a64_operands(args, false, false, false, false, "blraa"))
    a64_blraa(a64_operands(args, false, false, true, false, "blraa"))
}

macro blraaz(...args) {
    a64_blraaz_shape(a64_operands(args, false, false, false, false, "blraaz"))
    a64_blraaz(a64_operands(args, false, false, true, false, "blraaz"))
}

macro blrab(...args) {
    a64_blrab_shape(a64_operands(args, false, false, false, false, "blrab"))
    a64_blrab(a64_operands(args, false, false, true, false, "blrab"))
}

macro blrabz(...args) {
    a64_blrabz_shape(a64_operands(args, false, false, false, false, "blrabz"))
    a64_blrabz(a64_operands(args, false, false, true, false, "blrabz"))
}

macro br(...args) {
    a64_br_shape(a64_operands(args, false, false, false, false, "br"))
    a64_br(a64_operands(args, false, false, true, false, "br"))
}

macro braa(...args) {
    a64_braa_shape(a64_operands(args, false, false, false, false, "braa"))
    a64_braa(a64_operands(args, false, false, true, false, "braa"))
}

macro braaz(...args) {
    a64_braaz_shape(a64_operands(args, false, false, false, false, "braaz"))
    a64_braaz(a64_operands(args, false, false, true, false, "braaz"))
}

macro brab(...args) {
    a64_brab_shape(a64_operands(args, false, false, false, false, "brab"))
    a64_brab(a64_operands(args, false, false, true, false, "brab"))
}

macro brabz(...args) {
    a64_brabz_shape(a64_operands(args, false, false, false, false, "brabz"))
    a64_brabz(a64_operands(args, false, false, true, false, "brabz"))
}

macro brk(...args) {
    a64_brk_shape(a64_operands(args, false, false, false, false, "brk"))
    a64_brk(a64_operands(args, false, false, true, false, "brk"))
}

macro bsl(...args) {
    a64_bsl_shape(a64_operands(args, false, false, false, false, "bsl"))
    a64_bsl(a64_operands(args, false, false, true, false, "bsl"))
}

macro bti(...args) {
    a64_bti_shape(a64_operands(args, false, false, false, false, "bti"))
    a64_bti(a64_operands(args, false, false, true, false, "bti"))
}

macro cas(...args) {
    a64_cas_shape(a64_operands(args, false, false, false, false, "cas"))
    a64_cas(a64_operands(args, false, false, true, false, "cas"))
}

macro casa(...args) {
    a64_casa_shape(a64_operands(args, false, false, false, false, "casa"))
    a64_casa(a64_operands(args, false, false, true, false, "casa"))
}

macro casab(...args) {
    a64_casab_shape(a64_operands(args, false, false, false, false, "casab"))
    a64_casab(a64_operands(args, false, false, true, false, "casab"))
}

macro casah(...args) {
    a64_casah_shape(a64_operands(args, false, false, false, false, "casah"))
    a64_casah(a64_operands(args, false, false, true, false, "casah"))
}

macro casal(...args) {
    a64_casal_shape(a64_operands(args, false, false, false, false, "casal"))
    a64_casal(a64_operands(args, false, false, true, false, "casal"))
}

macro casalb(...args) {
    a64_casalb_shape(a64_operands(args, false, false, false, false, "casalb"))
    a64_casalb(a64_operands(args, false, false, true, false, "casalb"))
}

macro casalh(...args) {
    a64_casalh_shape(a64_operands(args, false, false, false, false, "casalh"))
    a64_casalh(a64_operands(args, false, false, true, false, "casalh"))
}

macro casb(...args) {
    a64_casb_shape(a64_operands(args, false, false, false, false, "casb"))
    a64_casb(a64_operands(args, false, false, true, false, "casb"))
}

macro cash(...args) {
    a64_cash_shape(a64_operands(args, false, false, false, false, "cash"))
    a64_cash(a64_operands(args, false, false, true, false, "cash"))
}

macro casl(...args) {
    a64_casl_shape(a64_operands(args, false, false, false, false, "casl"))
    a64_casl(a64_operands(args, false, false, true, false, "casl"))
}

macro caslb(...args) {
    a64_caslb_shape(a64_operands(args, false, false, false, false, "caslb"))
    a64_caslb(a64_operands(args, false, false, true, false, "caslb"))
}

macro caslh(...args) {
    a64_caslh_shape(a64_operands(args, false, false, false, false, "caslh"))
    a64_caslh(a64_operands(args, false, false, true, false, "caslh"))
}

macro casp(...args) {
    a64_casp_shape(a64_operands(args, false, false, false, false, "casp"))
    a64_casp(a64_operands(args, false, false, true, false, "casp"))
}

macro caspa(...args) {
    a64_caspa_shape(a64_operands(args, false, false, false, false, "caspa"))
    a64_caspa(a64_operands(args, false, false, true, false, "caspa"))
}

macro caspal(...args) {
    a64_caspal_shape(a64_operands(args, false, false, false, false, "caspal"))
    a64_caspal(a64_operands(args, false, false, true, false, "caspal"))
}

macro caspl(...args) {
    a64_caspl_shape(a64_operands(args, false, false, false, false, "caspl"))
    a64_caspl(a64_operands(args, false, false, true, false, "caspl"))
}

macro cbnz(...args) {
    a64_cbnz_shape(a64_operands(args, false, false, false, true, "cbnz"))
    a64_cbnz(a64_operands(args, false, false, true, true, "cbnz"))
}

macro cbz(...args) {
    a64_cbz_shape(a64_operands(args, false, false, false, true, "cbz"))
    a64_cbz(a64_operands(args, false, false, true, true, "cbz"))
}

macro ccmn(...args) {
    a64_ccmn_shape(a64_operands(args, false, false, false, false, "ccmn"))
    a64_ccmn(a64_operands(args, false, false, true, false, "ccmn"))
}

macro ccmp(...args) {
    a64_ccmp_shape(a64_operands(args, false, false, false, false, "ccmp"))
    a64_ccmp(a64_operands(args, false, false, true, false, "ccmp"))
}

macro cfinv(...args) {
    a64_cfinv_shape(a64_operands(args, false, false, false, false, "cfinv"))
    a64_cfinv(a64_operands(args, false, false, true, false, "cfinv"))
}

macro cinc(...args) {
    a64_cinc_shape(a64_operands(args, false, false, false, false, "cinc"))
    a64_cinc(a64_operands(args, false, false, true, false, "cinc"))
}

macro cinv(...args) {
    a64_cinv_shape(a64_operands(args, false, false, false, false, "cinv"))
    a64_cinv(a64_operands(args, false, false, true, false, "cinv"))
}

macro clrex(...args) {
    a64_clrex_shape(a64_operands(args, false, false, false, false, "clrex"))
    a64_clrex(a64_operands(args, false, false, true, false, "clrex"))
}

macro cls(...args) {
    a64_cls_shape(a64_operands(args, false, false, false, false, "cls"))
    a64_cls(a64_operands(args, false, false, true, false, "cls"))
}

macro clz(...args) {
    a64_clz_shape(a64_operands(args, false, false, false, false, "clz"))
    a64_clz(a64_operands(args, false, false, true, false, "clz"))
}

macro cmeq(...args) {
    a64_cmeq_shape(a64_operands(args, false, false, false, false, "cmeq"))
    a64_cmeq(a64_operands(args, false, false, true, false, "cmeq"))
}

macro cmge(...args) {
    a64_cmge_shape(a64_operands(args, false, false, false, false, "cmge"))
    a64_cmge(a64_operands(args, false, false, true, false, "cmge"))
}

macro cmgt(...args) {
    a64_cmgt_shape(a64_operands(args, false, false, false, false, "cmgt"))
    a64_cmgt(a64_operands(args, false, false, true, false, "cmgt"))
}

macro cmhi(...args) {
    a64_cmhi_shape(a64_operands(args, false, false, false, false, "cmhi"))
    a64_cmhi(a64_operands(args, false, false, true, false, "cmhi"))
}

macro cmhs(...args) {
    a64_cmhs_shape(a64_operands(args, false, false, false, false, "cmhs"))
    a64_cmhs(a64_operands(args, false, false, true, false, "cmhs"))
}

macro cmle(...args) {
    a64_cmle_shape(a64_operands(args, false, false, false, false, "cmle"))
    a64_cmle(a64_operands(args, false, false, true, false, "cmle"))
}

macro cmlt(...args) {
    a64_cmlt_shape(a64_operands(args, false, false, false, false, "cmlt"))
    a64_cmlt(a64_operands(args, false, false, true, false, "cmlt"))
}

macro cmn(...args) {
    a64_cmn_shape(a64_operands(args, false, false, false, false, "cmn"))
    a64_cmn(a64_operands(args, false, false, true, false, "cmn"))
}

macro cmp(...args) {
    a64_cmp_shape(a64_operands(args, false, false, false, false, "cmp"))
    a64_cmp(a64_operands(args, false, false, true, false, "cmp"))
}

macro cmpp(...args) {
    a64_cmpp_shape(a64_operands(args, false, false, false, false, "cmpp"))
    a64_cmpp(a64_operands(args, false, false, true, false, "cmpp"))
}

macro cmtst(...args) {
    a64_cmtst_shape(a64_operands(args, false, false, false, false, "cmtst"))
    a64_cmtst(a64_operands(args, false, false, true, false, "cmtst"))
}

macro cneg(...args) {
    a64_cneg_shape(a64_operands(args, false, false, false, false, "cneg"))
    a64_cneg(a64_operands(args, false, false, true, false, "cneg"))
}

macro cnt(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "cnt")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 263170 || key == 263683 {
        a64_e5_cnt_shape(shaped)
        a64_e5_cnt(a64_operands(args, false, false, true, false, "cnt"))
    } else {
        a64_cnt_shape(shaped)
        a64_cnt(a64_operands(args, false, false, true, false, "cnt"))
    }
}

macro crc32b(...args) {
    a64_crc32b_shape(a64_operands(args, false, false, false, false, "crc32b"))
    a64_crc32b(a64_operands(args, false, false, true, false, "crc32b"))
}

macro crc32cb(...args) {
    a64_crc32cb_shape(a64_operands(args, false, false, false, false, "crc32cb"))
    a64_crc32cb(a64_operands(args, false, false, true, false, "crc32cb"))
}

macro crc32ch(...args) {
    a64_crc32ch_shape(a64_operands(args, false, false, false, false, "crc32ch"))
    a64_crc32ch(a64_operands(args, false, false, true, false, "crc32ch"))
}

macro crc32cw(...args) {
    a64_crc32cw_shape(a64_operands(args, false, false, false, false, "crc32cw"))
    a64_crc32cw(a64_operands(args, false, false, true, false, "crc32cw"))
}

macro crc32cx(...args) {
    a64_crc32cx_shape(a64_operands(args, false, false, false, false, "crc32cx"))
    a64_crc32cx(a64_operands(args, false, false, true, false, "crc32cx"))
}

macro crc32h(...args) {
    a64_crc32h_shape(a64_operands(args, false, false, false, false, "crc32h"))
    a64_crc32h(a64_operands(args, false, false, true, false, "crc32h"))
}

macro crc32w(...args) {
    a64_crc32w_shape(a64_operands(args, false, false, false, false, "crc32w"))
    a64_crc32w(a64_operands(args, false, false, true, false, "crc32w"))
}

macro crc32x(...args) {
    a64_crc32x_shape(a64_operands(args, false, false, false, false, "crc32x"))
    a64_crc32x(a64_operands(args, false, false, true, false, "crc32x"))
}

macro csdb(...args) {
    a64_csdb_shape(a64_operands(args, false, false, false, false, "csdb"))
    a64_csdb(a64_operands(args, false, false, true, false, "csdb"))
}

macro csel(...args) {
    a64_csel_shape(a64_operands(args, false, false, false, false, "csel"))
    a64_csel(a64_operands(args, false, false, true, false, "csel"))
}

macro cset(...args) {
    a64_cset_shape(a64_operands(args, false, false, false, false, "cset"))
    a64_cset(a64_operands(args, false, false, true, false, "cset"))
}

macro csetm(...args) {
    a64_csetm_shape(a64_operands(args, false, false, false, false, "csetm"))
    a64_csetm(a64_operands(args, false, false, true, false, "csetm"))
}

macro csinc(...args) {
    a64_csinc_shape(a64_operands(args, false, false, false, false, "csinc"))
    a64_csinc(a64_operands(args, false, false, true, false, "csinc"))
}

macro csinv(...args) {
    a64_csinv_shape(a64_operands(args, false, false, false, false, "csinv"))
    a64_csinv(a64_operands(args, false, false, true, false, "csinv"))
}

macro csneg(...args) {
    a64_csneg_shape(a64_operands(args, false, false, false, false, "csneg"))
    a64_csneg(a64_operands(args, false, false, true, false, "csneg"))
}

macro dc(...args) {
    a64_dc_shape(a64_operands(args, false, false, false, false, "dc"))
    a64_dc(a64_operands(args, false, false, true, false, "dc"))
}

macro dcps1(...args) {
    a64_dcps1_shape(a64_operands(args, false, false, false, false, "dcps1"))
    a64_dcps1(a64_operands(args, false, false, true, false, "dcps1"))
}

macro dcps2(...args) {
    a64_dcps2_shape(a64_operands(args, false, false, false, false, "dcps2"))
    a64_dcps2(a64_operands(args, false, false, true, false, "dcps2"))
}

macro dcps3(...args) {
    a64_dcps3_shape(a64_operands(args, false, false, false, false, "dcps3"))
    a64_dcps3(a64_operands(args, false, false, true, false, "dcps3"))
}

macro dgh(...args) {
    a64_dgh_shape(a64_operands(args, false, false, false, false, "dgh"))
    a64_dgh(a64_operands(args, false, false, true, false, "dgh"))
}

macro dmb(...args) {
    a64_dmb_shape(a64_operands(args, false, false, false, false, "dmb"))
    a64_dmb(a64_operands(args, false, false, true, false, "dmb"))
}

macro drps(...args) {
    a64_drps_shape(a64_operands(args, false, false, false, false, "drps"))
    a64_drps(a64_operands(args, false, false, true, false, "drps"))
}

macro dsb(...args) {
    a64_dsb_shape(a64_operands(args, false, false, false, false, "dsb"))
    a64_dsb(a64_operands(args, false, false, true, false, "dsb"))
}

macro dup(...args) {
    a64_dup_shape(a64_operands(args, false, false, false, false, "dup"))
    a64_dup(a64_operands(args, false, false, true, false, "dup"))
}

macro eon(...args) {
    a64_eon_shape(a64_operands(args, false, false, false, false, "eon"))
    a64_eon(a64_operands(args, false, false, true, false, "eon"))
}

macro eor(...args) {
    a64_eor_shape(a64_operands(args, false, false, false, false, "eor"))
    a64_eor(a64_operands(args, false, false, true, false, "eor"))
}

macro eor3(...args) {
    a64_eor3_shape(a64_operands(args, false, false, false, false, "eor3"))
    a64_eor3(a64_operands(args, false, false, true, false, "eor3"))
}

macro eret(...args) {
    a64_eret_shape(a64_operands(args, false, false, false, false, "eret"))
    a64_eret(a64_operands(args, false, false, true, false, "eret"))
}

macro eretaa(...args) {
    a64_eretaa_shape(a64_operands(args, false, false, false, false, "eretaa"))
    a64_eretaa(a64_operands(args, false, false, true, false, "eretaa"))
}

macro eretab(...args) {
    a64_eretab_shape(a64_operands(args, false, false, false, false, "eretab"))
    a64_eretab(a64_operands(args, false, false, true, false, "eretab"))
}

macro esb(...args) {
    a64_esb_shape(a64_operands(args, false, false, false, false, "esb"))
    a64_esb(a64_operands(args, false, false, true, false, "esb"))
}

macro ext(...args) {
    a64_ext_shape(a64_operands(args, false, false, false, false, "ext"))
    a64_ext(a64_operands(args, false, false, true, false, "ext"))
}

macro extr(...args) {
    a64_extr_shape(a64_operands(args, false, false, false, false, "extr"))
    a64_extr(a64_operands(args, false, false, true, false, "extr"))
}

macro fabd(...args) {
    a64_fabd_shape(a64_operands(args, false, false, false, false, "fabd"))
    a64_fabd(a64_operands(args, false, false, true, false, "fabd"))
}

macro fabs(...args) {
    a64_fabs_shape(a64_operands(args, false, false, false, false, "fabs"))
    a64_fabs(a64_operands(args, false, false, true, false, "fabs"))
}

macro facge(...args) {
    a64_facge_shape(a64_operands(args, false, false, false, false, "facge"))
    a64_facge(a64_operands(args, false, false, true, false, "facge"))
}

macro facgt(...args) {
    a64_facgt_shape(a64_operands(args, false, false, false, false, "facgt"))
    a64_facgt(a64_operands(args, false, false, true, false, "facgt"))
}

macro fadd(...args) {
    a64_fadd_shape(a64_operands(args, false, false, false, false, "fadd"))
    a64_fadd(a64_operands(args, false, false, true, false, "fadd"))
}

macro faddp(...args) {
    a64_faddp_shape(a64_operands(args, false, false, false, false, "faddp"))
    a64_faddp(a64_operands(args, false, false, true, false, "faddp"))
}

macro fcadd(...args) {
    a64_fcadd_shape(a64_operands(args, false, false, false, false, "fcadd"))
    a64_fcadd(a64_operands(args, false, false, true, false, "fcadd"))
}

macro fccmp(...args) {
    a64_fccmp_shape(a64_operands(args, false, false, false, false, "fccmp"))
    a64_fccmp(a64_operands(args, false, false, true, false, "fccmp"))
}

macro fccmpe(...args) {
    a64_fccmpe_shape(a64_operands(args, false, false, false, false, "fccmpe"))
    a64_fccmpe(a64_operands(args, false, false, true, false, "fccmpe"))
}

macro fcmeq(...args) {
    a64_fcmeq_shape(a64_operands(args, false, true, false, false, "fcmeq"))
    a64_fcmeq(a64_operands(args, false, true, true, false, "fcmeq"))
}

macro fcmge(...args) {
    a64_fcmge_shape(a64_operands(args, false, true, false, false, "fcmge"))
    a64_fcmge(a64_operands(args, false, true, true, false, "fcmge"))
}

macro fcmgt(...args) {
    a64_fcmgt_shape(a64_operands(args, false, true, false, false, "fcmgt"))
    a64_fcmgt(a64_operands(args, false, true, true, false, "fcmgt"))
}

macro fcmla(...args) {
    a64_fcmla_shape(a64_operands(args, false, false, false, false, "fcmla"))
    a64_fcmla(a64_operands(args, false, false, true, false, "fcmla"))
}

macro fcmle(...args) {
    a64_fcmle_shape(a64_operands(args, false, true, false, false, "fcmle"))
    a64_fcmle(a64_operands(args, false, true, true, false, "fcmle"))
}

macro fcmlt(...args) {
    a64_fcmlt_shape(a64_operands(args, false, true, false, false, "fcmlt"))
    a64_fcmlt(a64_operands(args, false, true, true, false, "fcmlt"))
}

macro fcmp(...args) {
    a64_fcmp_shape(a64_operands(args, false, true, false, false, "fcmp"))
    a64_fcmp(a64_operands(args, false, true, true, false, "fcmp"))
}

macro fcmpe(...args) {
    a64_fcmpe_shape(a64_operands(args, false, true, false, false, "fcmpe"))
    a64_fcmpe(a64_operands(args, false, true, true, false, "fcmpe"))
}

macro fcsel(...args) {
    a64_fcsel_shape(a64_operands(args, false, false, false, false, "fcsel"))
    a64_fcsel(a64_operands(args, false, false, true, false, "fcsel"))
}

macro fcvt(...args) {
    a64_fcvt_shape(a64_operands(args, false, false, false, false, "fcvt"))
    a64_fcvt(a64_operands(args, false, false, true, false, "fcvt"))
}

macro fcvtas(...args) {
    a64_fcvtas_shape(a64_operands(args, false, false, false, false, "fcvtas"))
    a64_fcvtas(a64_operands(args, false, false, true, false, "fcvtas"))
}

macro fcvtau(...args) {
    a64_fcvtau_shape(a64_operands(args, false, false, false, false, "fcvtau"))
    a64_fcvtau(a64_operands(args, false, false, true, false, "fcvtau"))
}

macro fcvtl(...args) {
    a64_fcvtl_shape(a64_operands(args, false, false, false, false, "fcvtl"))
    a64_fcvtl(a64_operands(args, false, false, true, false, "fcvtl"))
}

macro fcvtl2(...args) {
    a64_fcvtl2_shape(a64_operands(args, false, false, false, false, "fcvtl2"))
    a64_fcvtl2(a64_operands(args, false, false, true, false, "fcvtl2"))
}

macro fcvtms(...args) {
    a64_fcvtms_shape(a64_operands(args, false, false, false, false, "fcvtms"))
    a64_fcvtms(a64_operands(args, false, false, true, false, "fcvtms"))
}

macro fcvtmu(...args) {
    a64_fcvtmu_shape(a64_operands(args, false, false, false, false, "fcvtmu"))
    a64_fcvtmu(a64_operands(args, false, false, true, false, "fcvtmu"))
}

macro fcvtn(...args) {
    a64_fcvtn_shape(a64_operands(args, false, false, false, false, "fcvtn"))
    a64_fcvtn(a64_operands(args, false, false, true, false, "fcvtn"))
}

macro fcvtn2(...args) {
    a64_fcvtn2_shape(a64_operands(args, false, false, false, false, "fcvtn2"))
    a64_fcvtn2(a64_operands(args, false, false, true, false, "fcvtn2"))
}

macro fcvtns(...args) {
    a64_fcvtns_shape(a64_operands(args, false, false, false, false, "fcvtns"))
    a64_fcvtns(a64_operands(args, false, false, true, false, "fcvtns"))
}

macro fcvtnu(...args) {
    a64_fcvtnu_shape(a64_operands(args, false, false, false, false, "fcvtnu"))
    a64_fcvtnu(a64_operands(args, false, false, true, false, "fcvtnu"))
}

macro fcvtps(...args) {
    a64_fcvtps_shape(a64_operands(args, false, false, false, false, "fcvtps"))
    a64_fcvtps(a64_operands(args, false, false, true, false, "fcvtps"))
}

macro fcvtpu(...args) {
    a64_fcvtpu_shape(a64_operands(args, false, false, false, false, "fcvtpu"))
    a64_fcvtpu(a64_operands(args, false, false, true, false, "fcvtpu"))
}

macro fcvtxn(...args) {
    a64_fcvtxn_shape(a64_operands(args, false, false, false, false, "fcvtxn"))
    a64_fcvtxn(a64_operands(args, false, false, true, false, "fcvtxn"))
}

macro fcvtxn2(...args) {
    a64_fcvtxn2_shape(a64_operands(args, false, false, false, false, "fcvtxn2"))
    a64_fcvtxn2(a64_operands(args, false, false, true, false, "fcvtxn2"))
}

macro fcvtzs(...args) {
    a64_fcvtzs_shape(a64_operands(args, false, false, false, false, "fcvtzs"))
    a64_fcvtzs(a64_operands(args, false, false, true, false, "fcvtzs"))
}

macro fcvtzu(...args) {
    a64_fcvtzu_shape(a64_operands(args, false, false, false, false, "fcvtzu"))
    a64_fcvtzu(a64_operands(args, false, false, true, false, "fcvtzu"))
}

macro fdiv(...args) {
    a64_fdiv_shape(a64_operands(args, false, false, false, false, "fdiv"))
    a64_fdiv(a64_operands(args, false, false, true, false, "fdiv"))
}

macro fjcvtzs(...args) {
    a64_fjcvtzs_shape(a64_operands(args, false, false, false, false, "fjcvtzs"))
    a64_fjcvtzs(a64_operands(args, false, false, true, false, "fjcvtzs"))
}

macro fmadd(...args) {
    a64_fmadd_shape(a64_operands(args, false, false, false, false, "fmadd"))
    a64_fmadd(a64_operands(args, false, false, true, false, "fmadd"))
}

macro fmax(...args) {
    a64_fmax_shape(a64_operands(args, false, false, false, false, "fmax"))
    a64_fmax(a64_operands(args, false, false, true, false, "fmax"))
}

macro fmaxnm(...args) {
    a64_fmaxnm_shape(a64_operands(args, false, false, false, false, "fmaxnm"))
    a64_fmaxnm(a64_operands(args, false, false, true, false, "fmaxnm"))
}

macro fmaxnmp(...args) {
    a64_fmaxnmp_shape(a64_operands(args, false, false, false, false, "fmaxnmp"))
    a64_fmaxnmp(a64_operands(args, false, false, true, false, "fmaxnmp"))
}

macro fmaxnmv(...args) {
    a64_fmaxnmv_shape(a64_operands(args, false, false, false, false, "fmaxnmv"))
    a64_fmaxnmv(a64_operands(args, false, false, true, false, "fmaxnmv"))
}

macro fmaxp(...args) {
    a64_fmaxp_shape(a64_operands(args, false, false, false, false, "fmaxp"))
    a64_fmaxp(a64_operands(args, false, false, true, false, "fmaxp"))
}

macro fmaxv(...args) {
    a64_fmaxv_shape(a64_operands(args, false, false, false, false, "fmaxv"))
    a64_fmaxv(a64_operands(args, false, false, true, false, "fmaxv"))
}

macro fmin(...args) {
    a64_fmin_shape(a64_operands(args, false, false, false, false, "fmin"))
    a64_fmin(a64_operands(args, false, false, true, false, "fmin"))
}

macro fminnm(...args) {
    a64_fminnm_shape(a64_operands(args, false, false, false, false, "fminnm"))
    a64_fminnm(a64_operands(args, false, false, true, false, "fminnm"))
}

macro fminnmp(...args) {
    a64_fminnmp_shape(a64_operands(args, false, false, false, false, "fminnmp"))
    a64_fminnmp(a64_operands(args, false, false, true, false, "fminnmp"))
}

macro fminnmv(...args) {
    a64_fminnmv_shape(a64_operands(args, false, false, false, false, "fminnmv"))
    a64_fminnmv(a64_operands(args, false, false, true, false, "fminnmv"))
}

macro fminp(...args) {
    a64_fminp_shape(a64_operands(args, false, false, false, false, "fminp"))
    a64_fminp(a64_operands(args, false, false, true, false, "fminp"))
}

macro fminv(...args) {
    a64_fminv_shape(a64_operands(args, false, false, false, false, "fminv"))
    a64_fminv(a64_operands(args, false, false, true, false, "fminv"))
}

macro fmla(...args) {
    a64_fmla_shape(a64_operands(args, false, false, false, false, "fmla"))
    a64_fmla(a64_operands(args, false, false, true, false, "fmla"))
}

macro fmlal(...args) {
    a64_fmlal_shape(a64_operands(args, false, false, false, false, "fmlal"))
    a64_fmlal(a64_operands(args, false, false, true, false, "fmlal"))
}

macro fmlal2(...args) {
    a64_fmlal2_shape(a64_operands(args, false, false, false, false, "fmlal2"))
    a64_fmlal2(a64_operands(args, false, false, true, false, "fmlal2"))
}

macro fmls(...args) {
    a64_fmls_shape(a64_operands(args, false, false, false, false, "fmls"))
    a64_fmls(a64_operands(args, false, false, true, false, "fmls"))
}

macro fmlsl(...args) {
    a64_fmlsl_shape(a64_operands(args, false, false, false, false, "fmlsl"))
    a64_fmlsl(a64_operands(args, false, false, true, false, "fmlsl"))
}

macro fmlsl2(...args) {
    a64_fmlsl2_shape(a64_operands(args, false, false, false, false, "fmlsl2"))
    a64_fmlsl2(a64_operands(args, false, false, true, false, "fmlsl2"))
}

macro fmov(...args) {
    a64_fmov_shape(a64_operands(args, true, false, false, false, "fmov"))
    a64_fmov(a64_operands(args, true, false, true, false, "fmov"))
}

macro fmsub(...args) {
    a64_fmsub_shape(a64_operands(args, false, false, false, false, "fmsub"))
    a64_fmsub(a64_operands(args, false, false, true, false, "fmsub"))
}

macro fmul(...args) {
    a64_fmul_shape(a64_operands(args, false, false, false, false, "fmul"))
    a64_fmul(a64_operands(args, false, false, true, false, "fmul"))
}

macro fmulx(...args) {
    a64_fmulx_shape(a64_operands(args, false, false, false, false, "fmulx"))
    a64_fmulx(a64_operands(args, false, false, true, false, "fmulx"))
}

macro fneg(...args) {
    a64_fneg_shape(a64_operands(args, false, false, false, false, "fneg"))
    a64_fneg(a64_operands(args, false, false, true, false, "fneg"))
}

macro fnmadd(...args) {
    a64_fnmadd_shape(a64_operands(args, false, false, false, false, "fnmadd"))
    a64_fnmadd(a64_operands(args, false, false, true, false, "fnmadd"))
}

macro fnmsub(...args) {
    a64_fnmsub_shape(a64_operands(args, false, false, false, false, "fnmsub"))
    a64_fnmsub(a64_operands(args, false, false, true, false, "fnmsub"))
}

macro fnmul(...args) {
    a64_fnmul_shape(a64_operands(args, false, false, false, false, "fnmul"))
    a64_fnmul(a64_operands(args, false, false, true, false, "fnmul"))
}

macro frecpe(...args) {
    a64_frecpe_shape(a64_operands(args, false, false, false, false, "frecpe"))
    a64_frecpe(a64_operands(args, false, false, true, false, "frecpe"))
}

macro frecps(...args) {
    a64_frecps_shape(a64_operands(args, false, false, false, false, "frecps"))
    a64_frecps(a64_operands(args, false, false, true, false, "frecps"))
}

macro frecpx(...args) {
    a64_frecpx_shape(a64_operands(args, false, false, false, false, "frecpx"))
    a64_frecpx(a64_operands(args, false, false, true, false, "frecpx"))
}

macro frint32x(...args) {
    a64_frint32x_shape(a64_operands(args, false, false, false, false, "frint32x"))
    a64_frint32x(a64_operands(args, false, false, true, false, "frint32x"))
}

macro frint32z(...args) {
    a64_frint32z_shape(a64_operands(args, false, false, false, false, "frint32z"))
    a64_frint32z(a64_operands(args, false, false, true, false, "frint32z"))
}

macro frint64x(...args) {
    a64_frint64x_shape(a64_operands(args, false, false, false, false, "frint64x"))
    a64_frint64x(a64_operands(args, false, false, true, false, "frint64x"))
}

macro frint64z(...args) {
    a64_frint64z_shape(a64_operands(args, false, false, false, false, "frint64z"))
    a64_frint64z(a64_operands(args, false, false, true, false, "frint64z"))
}

macro frinta(...args) {
    a64_frinta_shape(a64_operands(args, false, false, false, false, "frinta"))
    a64_frinta(a64_operands(args, false, false, true, false, "frinta"))
}

macro frinti(...args) {
    a64_frinti_shape(a64_operands(args, false, false, false, false, "frinti"))
    a64_frinti(a64_operands(args, false, false, true, false, "frinti"))
}

macro frintm(...args) {
    a64_frintm_shape(a64_operands(args, false, false, false, false, "frintm"))
    a64_frintm(a64_operands(args, false, false, true, false, "frintm"))
}

macro frintn(...args) {
    a64_frintn_shape(a64_operands(args, false, false, false, false, "frintn"))
    a64_frintn(a64_operands(args, false, false, true, false, "frintn"))
}

macro frintp(...args) {
    a64_frintp_shape(a64_operands(args, false, false, false, false, "frintp"))
    a64_frintp(a64_operands(args, false, false, true, false, "frintp"))
}

macro frintx(...args) {
    a64_frintx_shape(a64_operands(args, false, false, false, false, "frintx"))
    a64_frintx(a64_operands(args, false, false, true, false, "frintx"))
}

macro frintz(...args) {
    a64_frintz_shape(a64_operands(args, false, false, false, false, "frintz"))
    a64_frintz(a64_operands(args, false, false, true, false, "frintz"))
}

macro frsqrte(...args) {
    a64_frsqrte_shape(a64_operands(args, false, false, false, false, "frsqrte"))
    a64_frsqrte(a64_operands(args, false, false, true, false, "frsqrte"))
}

macro frsqrts(...args) {
    a64_frsqrts_shape(a64_operands(args, false, false, false, false, "frsqrts"))
    a64_frsqrts(a64_operands(args, false, false, true, false, "frsqrts"))
}

macro fsqrt(...args) {
    a64_fsqrt_shape(a64_operands(args, false, false, false, false, "fsqrt"))
    a64_fsqrt(a64_operands(args, false, false, true, false, "fsqrt"))
}

macro fsub(...args) {
    a64_fsub_shape(a64_operands(args, false, false, false, false, "fsub"))
    a64_fsub(a64_operands(args, false, false, true, false, "fsub"))
}

macro gmi(...args) {
    a64_gmi_shape(a64_operands(args, false, false, false, false, "gmi"))
    a64_gmi(a64_operands(args, false, false, true, false, "gmi"))
}

macro hint(...args) {
    a64_hint_shape(a64_operands(args, false, false, false, false, "hint"))
    a64_hint(a64_operands(args, false, false, true, false, "hint"))
}

macro hlt(...args) {
    a64_hlt_shape(a64_operands(args, false, false, false, false, "hlt"))
    a64_hlt(a64_operands(args, false, false, true, false, "hlt"))
}

macro hvc(...args) {
    a64_hvc_shape(a64_operands(args, false, false, false, false, "hvc"))
    a64_hvc(a64_operands(args, false, false, true, false, "hvc"))
}

macro ic(...args) {
    a64_ic_shape(a64_operands(args, false, false, false, false, "ic"))
    a64_ic(a64_operands(args, false, false, true, false, "ic"))
}

macro ins(...args) {
    a64_ins_shape(a64_operands(args, false, false, false, false, "ins"))
    a64_ins(a64_operands(args, false, false, true, false, "ins"))
}

macro irg(...args) {
    a64_irg_shape(a64_operands(args, false, false, false, false, "irg"))
    a64_irg(a64_operands(args, false, false, true, false, "irg"))
}

macro isb(...args) {
    a64_isb_shape(a64_operands(args, false, false, false, false, "isb"))
    a64_isb(a64_operands(args, false, false, true, false, "isb"))
}

macro ld1(...args) {
    a64_ld1_shape(a64_operands(args, false, false, false, false, "ld1"))
    a64_ld1(a64_operands(args, false, false, true, false, "ld1"))
}

macro ld1r(...args) {
    a64_ld1r_shape(a64_operands(args, false, false, false, false, "ld1r"))
    a64_ld1r(a64_operands(args, false, false, true, false, "ld1r"))
}

macro ld2(...args) {
    a64_ld2_shape(a64_operands(args, false, false, false, false, "ld2"))
    a64_ld2(a64_operands(args, false, false, true, false, "ld2"))
}

macro ld2r(...args) {
    a64_ld2r_shape(a64_operands(args, false, false, false, false, "ld2r"))
    a64_ld2r(a64_operands(args, false, false, true, false, "ld2r"))
}

macro ld3(...args) {
    a64_ld3_shape(a64_operands(args, false, false, false, false, "ld3"))
    a64_ld3(a64_operands(args, false, false, true, false, "ld3"))
}

macro ld3r(...args) {
    a64_ld3r_shape(a64_operands(args, false, false, false, false, "ld3r"))
    a64_ld3r(a64_operands(args, false, false, true, false, "ld3r"))
}

macro ld4(...args) {
    a64_ld4_shape(a64_operands(args, false, false, false, false, "ld4"))
    a64_ld4(a64_operands(args, false, false, true, false, "ld4"))
}

macro ld4r(...args) {
    a64_ld4r_shape(a64_operands(args, false, false, false, false, "ld4r"))
    a64_ld4r(a64_operands(args, false, false, true, false, "ld4r"))
}

macro ldadd(...args) {
    a64_ldadd_shape(a64_operands(args, false, false, false, false, "ldadd"))
    a64_ldadd(a64_operands(args, false, false, true, false, "ldadd"))
}

macro ldadda(...args) {
    a64_ldadda_shape(a64_operands(args, false, false, false, false, "ldadda"))
    a64_ldadda(a64_operands(args, false, false, true, false, "ldadda"))
}

macro ldaddab(...args) {
    a64_ldaddab_shape(a64_operands(args, false, false, false, false, "ldaddab"))
    a64_ldaddab(a64_operands(args, false, false, true, false, "ldaddab"))
}

macro ldaddah(...args) {
    a64_ldaddah_shape(a64_operands(args, false, false, false, false, "ldaddah"))
    a64_ldaddah(a64_operands(args, false, false, true, false, "ldaddah"))
}

macro ldaddal(...args) {
    a64_ldaddal_shape(a64_operands(args, false, false, false, false, "ldaddal"))
    a64_ldaddal(a64_operands(args, false, false, true, false, "ldaddal"))
}

macro ldaddalb(...args) {
    a64_ldaddalb_shape(a64_operands(args, false, false, false, false, "ldaddalb"))
    a64_ldaddalb(a64_operands(args, false, false, true, false, "ldaddalb"))
}

macro ldaddalh(...args) {
    a64_ldaddalh_shape(a64_operands(args, false, false, false, false, "ldaddalh"))
    a64_ldaddalh(a64_operands(args, false, false, true, false, "ldaddalh"))
}

macro ldaddb(...args) {
    a64_ldaddb_shape(a64_operands(args, false, false, false, false, "ldaddb"))
    a64_ldaddb(a64_operands(args, false, false, true, false, "ldaddb"))
}

macro ldaddh(...args) {
    a64_ldaddh_shape(a64_operands(args, false, false, false, false, "ldaddh"))
    a64_ldaddh(a64_operands(args, false, false, true, false, "ldaddh"))
}

macro ldaddl(...args) {
    a64_ldaddl_shape(a64_operands(args, false, false, false, false, "ldaddl"))
    a64_ldaddl(a64_operands(args, false, false, true, false, "ldaddl"))
}

macro ldaddlb(...args) {
    a64_ldaddlb_shape(a64_operands(args, false, false, false, false, "ldaddlb"))
    a64_ldaddlb(a64_operands(args, false, false, true, false, "ldaddlb"))
}

macro ldaddlh(...args) {
    a64_ldaddlh_shape(a64_operands(args, false, false, false, false, "ldaddlh"))
    a64_ldaddlh(a64_operands(args, false, false, true, false, "ldaddlh"))
}

macro ldapr(...args) {
    a64_ldapr_shape(a64_operands(args, false, false, false, false, "ldapr"))
    a64_ldapr(a64_operands(args, false, false, true, false, "ldapr"))
}

macro ldaprb(...args) {
    a64_ldaprb_shape(a64_operands(args, false, false, false, false, "ldaprb"))
    a64_ldaprb(a64_operands(args, false, false, true, false, "ldaprb"))
}

macro ldaprh(...args) {
    a64_ldaprh_shape(a64_operands(args, false, false, false, false, "ldaprh"))
    a64_ldaprh(a64_operands(args, false, false, true, false, "ldaprh"))
}

macro ldapur(...args) {
    a64_ldapur_shape(a64_operands(args, false, false, false, false, "ldapur"))
    a64_ldapur(a64_operands(args, false, false, true, false, "ldapur"))
}

macro ldapurb(...args) {
    a64_ldapurb_shape(a64_operands(args, false, false, false, false, "ldapurb"))
    a64_ldapurb(a64_operands(args, false, false, true, false, "ldapurb"))
}

macro ldapurh(...args) {
    a64_ldapurh_shape(a64_operands(args, false, false, false, false, "ldapurh"))
    a64_ldapurh(a64_operands(args, false, false, true, false, "ldapurh"))
}

macro ldapursb(...args) {
    a64_ldapursb_shape(a64_operands(args, false, false, false, false, "ldapursb"))
    a64_ldapursb(a64_operands(args, false, false, true, false, "ldapursb"))
}

macro ldapursh(...args) {
    a64_ldapursh_shape(a64_operands(args, false, false, false, false, "ldapursh"))
    a64_ldapursh(a64_operands(args, false, false, true, false, "ldapursh"))
}

macro ldapursw(...args) {
    a64_ldapursw_shape(a64_operands(args, false, false, false, false, "ldapursw"))
    a64_ldapursw(a64_operands(args, false, false, true, false, "ldapursw"))
}

macro ldar(...args) {
    a64_ldar_shape(a64_operands(args, false, false, false, false, "ldar"))
    a64_ldar(a64_operands(args, false, false, true, false, "ldar"))
}

macro ldarb(...args) {
    a64_ldarb_shape(a64_operands(args, false, false, false, false, "ldarb"))
    a64_ldarb(a64_operands(args, false, false, true, false, "ldarb"))
}

macro ldarh(...args) {
    a64_ldarh_shape(a64_operands(args, false, false, false, false, "ldarh"))
    a64_ldarh(a64_operands(args, false, false, true, false, "ldarh"))
}

macro ldaxp(...args) {
    a64_ldaxp_shape(a64_operands(args, false, false, false, false, "ldaxp"))
    a64_ldaxp(a64_operands(args, false, false, true, false, "ldaxp"))
}

macro ldaxr(...args) {
    a64_ldaxr_shape(a64_operands(args, false, false, false, false, "ldaxr"))
    a64_ldaxr(a64_operands(args, false, false, true, false, "ldaxr"))
}

macro ldaxrb(...args) {
    a64_ldaxrb_shape(a64_operands(args, false, false, false, false, "ldaxrb"))
    a64_ldaxrb(a64_operands(args, false, false, true, false, "ldaxrb"))
}

macro ldaxrh(...args) {
    a64_ldaxrh_shape(a64_operands(args, false, false, false, false, "ldaxrh"))
    a64_ldaxrh(a64_operands(args, false, false, true, false, "ldaxrh"))
}

macro ldclr(...args) {
    a64_ldclr_shape(a64_operands(args, false, false, false, false, "ldclr"))
    a64_ldclr(a64_operands(args, false, false, true, false, "ldclr"))
}

macro ldclra(...args) {
    a64_ldclra_shape(a64_operands(args, false, false, false, false, "ldclra"))
    a64_ldclra(a64_operands(args, false, false, true, false, "ldclra"))
}

macro ldclrab(...args) {
    a64_ldclrab_shape(a64_operands(args, false, false, false, false, "ldclrab"))
    a64_ldclrab(a64_operands(args, false, false, true, false, "ldclrab"))
}

macro ldclrah(...args) {
    a64_ldclrah_shape(a64_operands(args, false, false, false, false, "ldclrah"))
    a64_ldclrah(a64_operands(args, false, false, true, false, "ldclrah"))
}

macro ldclral(...args) {
    a64_ldclral_shape(a64_operands(args, false, false, false, false, "ldclral"))
    a64_ldclral(a64_operands(args, false, false, true, false, "ldclral"))
}

macro ldclralb(...args) {
    a64_ldclralb_shape(a64_operands(args, false, false, false, false, "ldclralb"))
    a64_ldclralb(a64_operands(args, false, false, true, false, "ldclralb"))
}

macro ldclralh(...args) {
    a64_ldclralh_shape(a64_operands(args, false, false, false, false, "ldclralh"))
    a64_ldclralh(a64_operands(args, false, false, true, false, "ldclralh"))
}

macro ldclrb(...args) {
    a64_ldclrb_shape(a64_operands(args, false, false, false, false, "ldclrb"))
    a64_ldclrb(a64_operands(args, false, false, true, false, "ldclrb"))
}

macro ldclrh(...args) {
    a64_ldclrh_shape(a64_operands(args, false, false, false, false, "ldclrh"))
    a64_ldclrh(a64_operands(args, false, false, true, false, "ldclrh"))
}

macro ldclrl(...args) {
    a64_ldclrl_shape(a64_operands(args, false, false, false, false, "ldclrl"))
    a64_ldclrl(a64_operands(args, false, false, true, false, "ldclrl"))
}

macro ldclrlb(...args) {
    a64_ldclrlb_shape(a64_operands(args, false, false, false, false, "ldclrlb"))
    a64_ldclrlb(a64_operands(args, false, false, true, false, "ldclrlb"))
}

macro ldclrlh(...args) {
    a64_ldclrlh_shape(a64_operands(args, false, false, false, false, "ldclrlh"))
    a64_ldclrlh(a64_operands(args, false, false, true, false, "ldclrlh"))
}

macro ldeor(...args) {
    a64_ldeor_shape(a64_operands(args, false, false, false, false, "ldeor"))
    a64_ldeor(a64_operands(args, false, false, true, false, "ldeor"))
}

macro ldeora(...args) {
    a64_ldeora_shape(a64_operands(args, false, false, false, false, "ldeora"))
    a64_ldeora(a64_operands(args, false, false, true, false, "ldeora"))
}

macro ldeorab(...args) {
    a64_ldeorab_shape(a64_operands(args, false, false, false, false, "ldeorab"))
    a64_ldeorab(a64_operands(args, false, false, true, false, "ldeorab"))
}

macro ldeorah(...args) {
    a64_ldeorah_shape(a64_operands(args, false, false, false, false, "ldeorah"))
    a64_ldeorah(a64_operands(args, false, false, true, false, "ldeorah"))
}

macro ldeoral(...args) {
    a64_ldeoral_shape(a64_operands(args, false, false, false, false, "ldeoral"))
    a64_ldeoral(a64_operands(args, false, false, true, false, "ldeoral"))
}

macro ldeoralb(...args) {
    a64_ldeoralb_shape(a64_operands(args, false, false, false, false, "ldeoralb"))
    a64_ldeoralb(a64_operands(args, false, false, true, false, "ldeoralb"))
}

macro ldeoralh(...args) {
    a64_ldeoralh_shape(a64_operands(args, false, false, false, false, "ldeoralh"))
    a64_ldeoralh(a64_operands(args, false, false, true, false, "ldeoralh"))
}

macro ldeorb(...args) {
    a64_ldeorb_shape(a64_operands(args, false, false, false, false, "ldeorb"))
    a64_ldeorb(a64_operands(args, false, false, true, false, "ldeorb"))
}

macro ldeorh(...args) {
    a64_ldeorh_shape(a64_operands(args, false, false, false, false, "ldeorh"))
    a64_ldeorh(a64_operands(args, false, false, true, false, "ldeorh"))
}

macro ldeorl(...args) {
    a64_ldeorl_shape(a64_operands(args, false, false, false, false, "ldeorl"))
    a64_ldeorl(a64_operands(args, false, false, true, false, "ldeorl"))
}

macro ldeorlb(...args) {
    a64_ldeorlb_shape(a64_operands(args, false, false, false, false, "ldeorlb"))
    a64_ldeorlb(a64_operands(args, false, false, true, false, "ldeorlb"))
}

macro ldeorlh(...args) {
    a64_ldeorlh_shape(a64_operands(args, false, false, false, false, "ldeorlh"))
    a64_ldeorlh(a64_operands(args, false, false, true, false, "ldeorlh"))
}

macro ldg(...args) {
    a64_ldg_shape(a64_operands(args, false, false, false, false, "ldg"))
    a64_ldg(a64_operands(args, false, false, true, false, "ldg"))
}

macro ldgm(...args) {
    a64_ldgm_shape(a64_operands(args, false, false, false, false, "ldgm"))
    a64_ldgm(a64_operands(args, false, false, true, false, "ldgm"))
}

macro ldlar(...args) {
    a64_ldlar_shape(a64_operands(args, false, false, false, false, "ldlar"))
    a64_ldlar(a64_operands(args, false, false, true, false, "ldlar"))
}

macro ldlarb(...args) {
    a64_ldlarb_shape(a64_operands(args, false, false, false, false, "ldlarb"))
    a64_ldlarb(a64_operands(args, false, false, true, false, "ldlarb"))
}

macro ldlarh(...args) {
    a64_ldlarh_shape(a64_operands(args, false, false, false, false, "ldlarh"))
    a64_ldlarh(a64_operands(args, false, false, true, false, "ldlarh"))
}

macro ldnp(...args) {
    a64_ldnp_shape(a64_operands(args, false, false, false, false, "ldnp"))
    a64_ldnp(a64_operands(args, false, false, true, false, "ldnp"))
}

macro ldp(...args) {
    a64_ldp_shape(a64_operands(args, false, false, false, false, "ldp"))
    a64_ldp(a64_operands(args, false, false, true, false, "ldp"))
}

macro ldpsw(...args) {
    a64_ldpsw_shape(a64_operands(args, false, false, false, false, "ldpsw"))
    a64_ldpsw(a64_operands(args, false, false, true, false, "ldpsw"))
}

macro ldr(...args) {
    a64_ldr_shape(a64_operands(args, false, false, false, true, "ldr"))
    a64_ldr(a64_operands(args, false, false, true, true, "ldr"))
}

macro ldraa(...args) {
    a64_ldraa_shape(a64_operands(args, false, false, false, false, "ldraa"))
    a64_ldraa(a64_operands(args, false, false, true, false, "ldraa"))
}

macro ldrab(...args) {
    a64_ldrab_shape(a64_operands(args, false, false, false, false, "ldrab"))
    a64_ldrab(a64_operands(args, false, false, true, false, "ldrab"))
}

macro ldrb(...args) {
    a64_ldrb_shape(a64_operands(args, false, false, false, false, "ldrb"))
    a64_ldrb(a64_operands(args, false, false, true, false, "ldrb"))
}

macro ldrh(...args) {
    a64_ldrh_shape(a64_operands(args, false, false, false, false, "ldrh"))
    a64_ldrh(a64_operands(args, false, false, true, false, "ldrh"))
}

macro ldrsb(...args) {
    a64_ldrsb_shape(a64_operands(args, false, false, false, false, "ldrsb"))
    a64_ldrsb(a64_operands(args, false, false, true, false, "ldrsb"))
}

macro ldrsh(...args) {
    a64_ldrsh_shape(a64_operands(args, false, false, false, false, "ldrsh"))
    a64_ldrsh(a64_operands(args, false, false, true, false, "ldrsh"))
}

macro ldrsw(...args) {
    a64_ldrsw_shape(a64_operands(args, false, false, false, true, "ldrsw"))
    a64_ldrsw(a64_operands(args, false, false, true, true, "ldrsw"))
}

macro ldset(...args) {
    a64_ldset_shape(a64_operands(args, false, false, false, false, "ldset"))
    a64_ldset(a64_operands(args, false, false, true, false, "ldset"))
}

macro ldseta(...args) {
    a64_ldseta_shape(a64_operands(args, false, false, false, false, "ldseta"))
    a64_ldseta(a64_operands(args, false, false, true, false, "ldseta"))
}

macro ldsetab(...args) {
    a64_ldsetab_shape(a64_operands(args, false, false, false, false, "ldsetab"))
    a64_ldsetab(a64_operands(args, false, false, true, false, "ldsetab"))
}

macro ldsetah(...args) {
    a64_ldsetah_shape(a64_operands(args, false, false, false, false, "ldsetah"))
    a64_ldsetah(a64_operands(args, false, false, true, false, "ldsetah"))
}

macro ldsetal(...args) {
    a64_ldsetal_shape(a64_operands(args, false, false, false, false, "ldsetal"))
    a64_ldsetal(a64_operands(args, false, false, true, false, "ldsetal"))
}

macro ldsetalb(...args) {
    a64_ldsetalb_shape(a64_operands(args, false, false, false, false, "ldsetalb"))
    a64_ldsetalb(a64_operands(args, false, false, true, false, "ldsetalb"))
}

macro ldsetalh(...args) {
    a64_ldsetalh_shape(a64_operands(args, false, false, false, false, "ldsetalh"))
    a64_ldsetalh(a64_operands(args, false, false, true, false, "ldsetalh"))
}

macro ldsetb(...args) {
    a64_ldsetb_shape(a64_operands(args, false, false, false, false, "ldsetb"))
    a64_ldsetb(a64_operands(args, false, false, true, false, "ldsetb"))
}

macro ldseth(...args) {
    a64_ldseth_shape(a64_operands(args, false, false, false, false, "ldseth"))
    a64_ldseth(a64_operands(args, false, false, true, false, "ldseth"))
}

macro ldsetl(...args) {
    a64_ldsetl_shape(a64_operands(args, false, false, false, false, "ldsetl"))
    a64_ldsetl(a64_operands(args, false, false, true, false, "ldsetl"))
}

macro ldsetlb(...args) {
    a64_ldsetlb_shape(a64_operands(args, false, false, false, false, "ldsetlb"))
    a64_ldsetlb(a64_operands(args, false, false, true, false, "ldsetlb"))
}

macro ldsetlh(...args) {
    a64_ldsetlh_shape(a64_operands(args, false, false, false, false, "ldsetlh"))
    a64_ldsetlh(a64_operands(args, false, false, true, false, "ldsetlh"))
}

macro ldsmax(...args) {
    a64_ldsmax_shape(a64_operands(args, false, false, false, false, "ldsmax"))
    a64_ldsmax(a64_operands(args, false, false, true, false, "ldsmax"))
}

macro ldsmaxa(...args) {
    a64_ldsmaxa_shape(a64_operands(args, false, false, false, false, "ldsmaxa"))
    a64_ldsmaxa(a64_operands(args, false, false, true, false, "ldsmaxa"))
}

macro ldsmaxab(...args) {
    a64_ldsmaxab_shape(a64_operands(args, false, false, false, false, "ldsmaxab"))
    a64_ldsmaxab(a64_operands(args, false, false, true, false, "ldsmaxab"))
}

macro ldsmaxah(...args) {
    a64_ldsmaxah_shape(a64_operands(args, false, false, false, false, "ldsmaxah"))
    a64_ldsmaxah(a64_operands(args, false, false, true, false, "ldsmaxah"))
}

macro ldsmaxal(...args) {
    a64_ldsmaxal_shape(a64_operands(args, false, false, false, false, "ldsmaxal"))
    a64_ldsmaxal(a64_operands(args, false, false, true, false, "ldsmaxal"))
}

macro ldsmaxalb(...args) {
    a64_ldsmaxalb_shape(a64_operands(args, false, false, false, false, "ldsmaxalb"))
    a64_ldsmaxalb(a64_operands(args, false, false, true, false, "ldsmaxalb"))
}

macro ldsmaxalh(...args) {
    a64_ldsmaxalh_shape(a64_operands(args, false, false, false, false, "ldsmaxalh"))
    a64_ldsmaxalh(a64_operands(args, false, false, true, false, "ldsmaxalh"))
}

macro ldsmaxb(...args) {
    a64_ldsmaxb_shape(a64_operands(args, false, false, false, false, "ldsmaxb"))
    a64_ldsmaxb(a64_operands(args, false, false, true, false, "ldsmaxb"))
}

macro ldsmaxh(...args) {
    a64_ldsmaxh_shape(a64_operands(args, false, false, false, false, "ldsmaxh"))
    a64_ldsmaxh(a64_operands(args, false, false, true, false, "ldsmaxh"))
}

macro ldsmaxl(...args) {
    a64_ldsmaxl_shape(a64_operands(args, false, false, false, false, "ldsmaxl"))
    a64_ldsmaxl(a64_operands(args, false, false, true, false, "ldsmaxl"))
}

macro ldsmaxlb(...args) {
    a64_ldsmaxlb_shape(a64_operands(args, false, false, false, false, "ldsmaxlb"))
    a64_ldsmaxlb(a64_operands(args, false, false, true, false, "ldsmaxlb"))
}

macro ldsmaxlh(...args) {
    a64_ldsmaxlh_shape(a64_operands(args, false, false, false, false, "ldsmaxlh"))
    a64_ldsmaxlh(a64_operands(args, false, false, true, false, "ldsmaxlh"))
}

macro ldsmin(...args) {
    a64_ldsmin_shape(a64_operands(args, false, false, false, false, "ldsmin"))
    a64_ldsmin(a64_operands(args, false, false, true, false, "ldsmin"))
}

macro ldsmina(...args) {
    a64_ldsmina_shape(a64_operands(args, false, false, false, false, "ldsmina"))
    a64_ldsmina(a64_operands(args, false, false, true, false, "ldsmina"))
}

macro ldsminab(...args) {
    a64_ldsminab_shape(a64_operands(args, false, false, false, false, "ldsminab"))
    a64_ldsminab(a64_operands(args, false, false, true, false, "ldsminab"))
}

macro ldsminah(...args) {
    a64_ldsminah_shape(a64_operands(args, false, false, false, false, "ldsminah"))
    a64_ldsminah(a64_operands(args, false, false, true, false, "ldsminah"))
}

macro ldsminal(...args) {
    a64_ldsminal_shape(a64_operands(args, false, false, false, false, "ldsminal"))
    a64_ldsminal(a64_operands(args, false, false, true, false, "ldsminal"))
}

macro ldsminalb(...args) {
    a64_ldsminalb_shape(a64_operands(args, false, false, false, false, "ldsminalb"))
    a64_ldsminalb(a64_operands(args, false, false, true, false, "ldsminalb"))
}

macro ldsminalh(...args) {
    a64_ldsminalh_shape(a64_operands(args, false, false, false, false, "ldsminalh"))
    a64_ldsminalh(a64_operands(args, false, false, true, false, "ldsminalh"))
}

macro ldsminb(...args) {
    a64_ldsminb_shape(a64_operands(args, false, false, false, false, "ldsminb"))
    a64_ldsminb(a64_operands(args, false, false, true, false, "ldsminb"))
}

macro ldsminh(...args) {
    a64_ldsminh_shape(a64_operands(args, false, false, false, false, "ldsminh"))
    a64_ldsminh(a64_operands(args, false, false, true, false, "ldsminh"))
}

macro ldsminl(...args) {
    a64_ldsminl_shape(a64_operands(args, false, false, false, false, "ldsminl"))
    a64_ldsminl(a64_operands(args, false, false, true, false, "ldsminl"))
}

macro ldsminlb(...args) {
    a64_ldsminlb_shape(a64_operands(args, false, false, false, false, "ldsminlb"))
    a64_ldsminlb(a64_operands(args, false, false, true, false, "ldsminlb"))
}

macro ldsminlh(...args) {
    a64_ldsminlh_shape(a64_operands(args, false, false, false, false, "ldsminlh"))
    a64_ldsminlh(a64_operands(args, false, false, true, false, "ldsminlh"))
}

macro ldtr(...args) {
    a64_ldtr_shape(a64_operands(args, false, false, false, false, "ldtr"))
    a64_ldtr(a64_operands(args, false, false, true, false, "ldtr"))
}

macro ldtrb(...args) {
    a64_ldtrb_shape(a64_operands(args, false, false, false, false, "ldtrb"))
    a64_ldtrb(a64_operands(args, false, false, true, false, "ldtrb"))
}

macro ldtrh(...args) {
    a64_ldtrh_shape(a64_operands(args, false, false, false, false, "ldtrh"))
    a64_ldtrh(a64_operands(args, false, false, true, false, "ldtrh"))
}

macro ldtrsb(...args) {
    a64_ldtrsb_shape(a64_operands(args, false, false, false, false, "ldtrsb"))
    a64_ldtrsb(a64_operands(args, false, false, true, false, "ldtrsb"))
}

macro ldtrsh(...args) {
    a64_ldtrsh_shape(a64_operands(args, false, false, false, false, "ldtrsh"))
    a64_ldtrsh(a64_operands(args, false, false, true, false, "ldtrsh"))
}

macro ldtrsw(...args) {
    a64_ldtrsw_shape(a64_operands(args, false, false, false, false, "ldtrsw"))
    a64_ldtrsw(a64_operands(args, false, false, true, false, "ldtrsw"))
}

macro ldumax(...args) {
    a64_ldumax_shape(a64_operands(args, false, false, false, false, "ldumax"))
    a64_ldumax(a64_operands(args, false, false, true, false, "ldumax"))
}

macro ldumaxa(...args) {
    a64_ldumaxa_shape(a64_operands(args, false, false, false, false, "ldumaxa"))
    a64_ldumaxa(a64_operands(args, false, false, true, false, "ldumaxa"))
}

macro ldumaxab(...args) {
    a64_ldumaxab_shape(a64_operands(args, false, false, false, false, "ldumaxab"))
    a64_ldumaxab(a64_operands(args, false, false, true, false, "ldumaxab"))
}

macro ldumaxah(...args) {
    a64_ldumaxah_shape(a64_operands(args, false, false, false, false, "ldumaxah"))
    a64_ldumaxah(a64_operands(args, false, false, true, false, "ldumaxah"))
}

macro ldumaxal(...args) {
    a64_ldumaxal_shape(a64_operands(args, false, false, false, false, "ldumaxal"))
    a64_ldumaxal(a64_operands(args, false, false, true, false, "ldumaxal"))
}

macro ldumaxalb(...args) {
    a64_ldumaxalb_shape(a64_operands(args, false, false, false, false, "ldumaxalb"))
    a64_ldumaxalb(a64_operands(args, false, false, true, false, "ldumaxalb"))
}

macro ldumaxalh(...args) {
    a64_ldumaxalh_shape(a64_operands(args, false, false, false, false, "ldumaxalh"))
    a64_ldumaxalh(a64_operands(args, false, false, true, false, "ldumaxalh"))
}

macro ldumaxb(...args) {
    a64_ldumaxb_shape(a64_operands(args, false, false, false, false, "ldumaxb"))
    a64_ldumaxb(a64_operands(args, false, false, true, false, "ldumaxb"))
}

macro ldumaxh(...args) {
    a64_ldumaxh_shape(a64_operands(args, false, false, false, false, "ldumaxh"))
    a64_ldumaxh(a64_operands(args, false, false, true, false, "ldumaxh"))
}

macro ldumaxl(...args) {
    a64_ldumaxl_shape(a64_operands(args, false, false, false, false, "ldumaxl"))
    a64_ldumaxl(a64_operands(args, false, false, true, false, "ldumaxl"))
}

macro ldumaxlb(...args) {
    a64_ldumaxlb_shape(a64_operands(args, false, false, false, false, "ldumaxlb"))
    a64_ldumaxlb(a64_operands(args, false, false, true, false, "ldumaxlb"))
}

macro ldumaxlh(...args) {
    a64_ldumaxlh_shape(a64_operands(args, false, false, false, false, "ldumaxlh"))
    a64_ldumaxlh(a64_operands(args, false, false, true, false, "ldumaxlh"))
}

macro ldumin(...args) {
    a64_ldumin_shape(a64_operands(args, false, false, false, false, "ldumin"))
    a64_ldumin(a64_operands(args, false, false, true, false, "ldumin"))
}

macro ldumina(...args) {
    a64_ldumina_shape(a64_operands(args, false, false, false, false, "ldumina"))
    a64_ldumina(a64_operands(args, false, false, true, false, "ldumina"))
}

macro lduminab(...args) {
    a64_lduminab_shape(a64_operands(args, false, false, false, false, "lduminab"))
    a64_lduminab(a64_operands(args, false, false, true, false, "lduminab"))
}

macro lduminah(...args) {
    a64_lduminah_shape(a64_operands(args, false, false, false, false, "lduminah"))
    a64_lduminah(a64_operands(args, false, false, true, false, "lduminah"))
}

macro lduminal(...args) {
    a64_lduminal_shape(a64_operands(args, false, false, false, false, "lduminal"))
    a64_lduminal(a64_operands(args, false, false, true, false, "lduminal"))
}

macro lduminalb(...args) {
    a64_lduminalb_shape(a64_operands(args, false, false, false, false, "lduminalb"))
    a64_lduminalb(a64_operands(args, false, false, true, false, "lduminalb"))
}

macro lduminalh(...args) {
    a64_lduminalh_shape(a64_operands(args, false, false, false, false, "lduminalh"))
    a64_lduminalh(a64_operands(args, false, false, true, false, "lduminalh"))
}

macro lduminb(...args) {
    a64_lduminb_shape(a64_operands(args, false, false, false, false, "lduminb"))
    a64_lduminb(a64_operands(args, false, false, true, false, "lduminb"))
}

macro lduminh(...args) {
    a64_lduminh_shape(a64_operands(args, false, false, false, false, "lduminh"))
    a64_lduminh(a64_operands(args, false, false, true, false, "lduminh"))
}

macro lduminl(...args) {
    a64_lduminl_shape(a64_operands(args, false, false, false, false, "lduminl"))
    a64_lduminl(a64_operands(args, false, false, true, false, "lduminl"))
}

macro lduminlb(...args) {
    a64_lduminlb_shape(a64_operands(args, false, false, false, false, "lduminlb"))
    a64_lduminlb(a64_operands(args, false, false, true, false, "lduminlb"))
}

macro lduminlh(...args) {
    a64_lduminlh_shape(a64_operands(args, false, false, false, false, "lduminlh"))
    a64_lduminlh(a64_operands(args, false, false, true, false, "lduminlh"))
}

macro ldur(...args) {
    a64_ldur_shape(a64_operands(args, false, false, false, false, "ldur"))
    a64_ldur(a64_operands(args, false, false, true, false, "ldur"))
}

macro ldurb(...args) {
    a64_ldurb_shape(a64_operands(args, false, false, false, false, "ldurb"))
    a64_ldurb(a64_operands(args, false, false, true, false, "ldurb"))
}

macro ldurh(...args) {
    a64_ldurh_shape(a64_operands(args, false, false, false, false, "ldurh"))
    a64_ldurh(a64_operands(args, false, false, true, false, "ldurh"))
}

macro ldursb(...args) {
    a64_ldursb_shape(a64_operands(args, false, false, false, false, "ldursb"))
    a64_ldursb(a64_operands(args, false, false, true, false, "ldursb"))
}

macro ldursh(...args) {
    a64_ldursh_shape(a64_operands(args, false, false, false, false, "ldursh"))
    a64_ldursh(a64_operands(args, false, false, true, false, "ldursh"))
}

macro ldursw(...args) {
    a64_ldursw_shape(a64_operands(args, false, false, false, false, "ldursw"))
    a64_ldursw(a64_operands(args, false, false, true, false, "ldursw"))
}

macro ldxp(...args) {
    a64_ldxp_shape(a64_operands(args, false, false, false, false, "ldxp"))
    a64_ldxp(a64_operands(args, false, false, true, false, "ldxp"))
}

macro ldxr(...args) {
    a64_ldxr_shape(a64_operands(args, false, false, false, false, "ldxr"))
    a64_ldxr(a64_operands(args, false, false, true, false, "ldxr"))
}

macro ldxrb(...args) {
    a64_ldxrb_shape(a64_operands(args, false, false, false, false, "ldxrb"))
    a64_ldxrb(a64_operands(args, false, false, true, false, "ldxrb"))
}

macro ldxrh(...args) {
    a64_ldxrh_shape(a64_operands(args, false, false, false, false, "ldxrh"))
    a64_ldxrh(a64_operands(args, false, false, true, false, "ldxrh"))
}

macro lsl(...args) {
    a64_lsl_shape(a64_operands(args, false, false, false, false, "lsl"))
    a64_lsl(a64_operands(args, false, false, true, false, "lsl"))
}

macro lslv(...args) {
    a64_lslv_shape(a64_operands(args, false, false, false, false, "lslv"))
    a64_lslv(a64_operands(args, false, false, true, false, "lslv"))
}

macro lsr(...args) {
    a64_lsr_shape(a64_operands(args, false, false, false, false, "lsr"))
    a64_lsr(a64_operands(args, false, false, true, false, "lsr"))
}

macro lsrv(...args) {
    a64_lsrv_shape(a64_operands(args, false, false, false, false, "lsrv"))
    a64_lsrv(a64_operands(args, false, false, true, false, "lsrv"))
}

macro madd(...args) {
    a64_madd_shape(a64_operands(args, false, false, false, false, "madd"))
    a64_madd(a64_operands(args, false, false, true, false, "madd"))
}

macro mla(...args) {
    a64_mla_shape(a64_operands(args, false, false, false, false, "mla"))
    a64_mla(a64_operands(args, false, false, true, false, "mla"))
}

macro mls(...args) {
    a64_mls_shape(a64_operands(args, false, false, false, false, "mls"))
    a64_mls(a64_operands(args, false, false, true, false, "mls"))
}

macro mneg(...args) {
    a64_mneg_shape(a64_operands(args, false, false, false, false, "mneg"))
    a64_mneg(a64_operands(args, false, false, true, false, "mneg"))
}

macro mov(...args) {
    a64_mov_shape(a64_operands(args, false, false, false, false, "mov"))
    a64_mov(a64_operands(args, false, false, true, false, "mov"))
}

macro movi(...args) {
    a64_movi_shape(a64_operands(args, false, false, false, false, "movi"))
    a64_movi(a64_operands(args, false, false, true, false, "movi"))
}

macro movk(...args) {
    a64_movk_shape(a64_operands(args, false, false, false, false, "movk"))
    a64_movk(a64_operands(args, false, false, true, false, "movk"))
}

macro movn(...args) {
    a64_movn_shape(a64_operands(args, false, false, false, false, "movn"))
    a64_movn(a64_operands(args, false, false, true, false, "movn"))
}

macro movz(...args) {
    a64_movz_shape(a64_operands(args, false, false, false, false, "movz"))
    a64_movz(a64_operands(args, false, false, true, false, "movz"))
}

macro mrs(...args) {
    a64_mrs_shape(a64_operands(args, false, false, false, false, "mrs"))
    a64_mrs(a64_operands(args, false, false, true, false, "mrs"))
}

macro msr(...args) {
    a64_msr_shape(a64_operands(args, false, false, false, false, "msr"))
    a64_msr(a64_operands(args, false, false, true, false, "msr"))
}

macro msub(...args) {
    a64_msub_shape(a64_operands(args, false, false, false, false, "msub"))
    a64_msub(a64_operands(args, false, false, true, false, "msub"))
}

macro mul(...args) {
    a64_mul_shape(a64_operands(args, false, false, false, false, "mul"))
    a64_mul(a64_operands(args, false, false, true, false, "mul"))
}

macro mvn(...args) {
    a64_mvn_shape(a64_operands(args, false, false, false, false, "mvn"))
    a64_mvn(a64_operands(args, false, false, true, false, "mvn"))
}

macro mvni(...args) {
    a64_mvni_shape(a64_operands(args, false, false, false, false, "mvni"))
    a64_mvni(a64_operands(args, false, false, true, false, "mvni"))
}

macro neg(...args) {
    a64_neg_shape(a64_operands(args, false, false, false, false, "neg"))
    a64_neg(a64_operands(args, false, false, true, false, "neg"))
}

macro negs(...args) {
    a64_negs_shape(a64_operands(args, false, false, false, false, "negs"))
    a64_negs(a64_operands(args, false, false, true, false, "negs"))
}

macro ngc(...args) {
    a64_ngc_shape(a64_operands(args, false, false, false, false, "ngc"))
    a64_ngc(a64_operands(args, false, false, true, false, "ngc"))
}

macro ngcs(...args) {
    a64_ngcs_shape(a64_operands(args, false, false, false, false, "ngcs"))
    a64_ngcs(a64_operands(args, false, false, true, false, "ngcs"))
}

macro nop(...args) {
    a64_nop_shape(a64_operands(args, false, false, false, false, "nop"))
    a64_nop(a64_operands(args, false, false, true, false, "nop"))
}

macro not(...args) {
    a64_not_shape(a64_operands(args, false, false, false, false, "not"))
    a64_not(a64_operands(args, false, false, true, false, "not"))
}

macro orn(...args) {
    a64_orn_shape(a64_operands(args, false, false, false, false, "orn"))
    a64_orn(a64_operands(args, false, false, true, false, "orn"))
}

macro orr(...args) {
    a64_orr_shape(a64_operands(args, false, false, false, false, "orr"))
    a64_orr(a64_operands(args, false, false, true, false, "orr"))
}

macro pacda(...args) {
    a64_pacda_shape(a64_operands(args, false, false, false, false, "pacda"))
    a64_pacda(a64_operands(args, false, false, true, false, "pacda"))
}

macro pacdb(...args) {
    a64_pacdb_shape(a64_operands(args, false, false, false, false, "pacdb"))
    a64_pacdb(a64_operands(args, false, false, true, false, "pacdb"))
}

macro pacdza(...args) {
    a64_pacdza_shape(a64_operands(args, false, false, false, false, "pacdza"))
    a64_pacdza(a64_operands(args, false, false, true, false, "pacdza"))
}

macro pacdzb(...args) {
    a64_pacdzb_shape(a64_operands(args, false, false, false, false, "pacdzb"))
    a64_pacdzb(a64_operands(args, false, false, true, false, "pacdzb"))
}

macro pacga(...args) {
    a64_pacga_shape(a64_operands(args, false, false, false, false, "pacga"))
    a64_pacga(a64_operands(args, false, false, true, false, "pacga"))
}

macro pacia(...args) {
    a64_pacia_shape(a64_operands(args, false, false, false, false, "pacia"))
    a64_pacia(a64_operands(args, false, false, true, false, "pacia"))
}

macro pacia1716(...args) {
    a64_pacia1716_shape(a64_operands(args, false, false, false, false, "pacia1716"))
    a64_pacia1716(a64_operands(args, false, false, true, false, "pacia1716"))
}

macro paciasp(...args) {
    a64_paciasp_shape(a64_operands(args, false, false, false, false, "paciasp"))
    a64_paciasp(a64_operands(args, false, false, true, false, "paciasp"))
}

macro paciaz(...args) {
    a64_paciaz_shape(a64_operands(args, false, false, false, false, "paciaz"))
    a64_paciaz(a64_operands(args, false, false, true, false, "paciaz"))
}

macro pacib(...args) {
    a64_pacib_shape(a64_operands(args, false, false, false, false, "pacib"))
    a64_pacib(a64_operands(args, false, false, true, false, "pacib"))
}

macro pacib1716(...args) {
    a64_pacib1716_shape(a64_operands(args, false, false, false, false, "pacib1716"))
    a64_pacib1716(a64_operands(args, false, false, true, false, "pacib1716"))
}

macro pacibsp(...args) {
    a64_pacibsp_shape(a64_operands(args, false, false, false, false, "pacibsp"))
    a64_pacibsp(a64_operands(args, false, false, true, false, "pacibsp"))
}

macro pacibz(...args) {
    a64_pacibz_shape(a64_operands(args, false, false, false, false, "pacibz"))
    a64_pacibz(a64_operands(args, false, false, true, false, "pacibz"))
}

macro paciza(...args) {
    a64_paciza_shape(a64_operands(args, false, false, false, false, "paciza"))
    a64_paciza(a64_operands(args, false, false, true, false, "paciza"))
}

macro pacizb(...args) {
    a64_pacizb_shape(a64_operands(args, false, false, false, false, "pacizb"))
    a64_pacizb(a64_operands(args, false, false, true, false, "pacizb"))
}

macro pmul(...args) {
    a64_pmul_shape(a64_operands(args, false, false, false, false, "pmul"))
    a64_pmul(a64_operands(args, false, false, true, false, "pmul"))
}

macro pmull(...args) {
    a64_pmull_shape(a64_operands(args, false, false, false, false, "pmull"))
    a64_pmull(a64_operands(args, false, false, true, false, "pmull"))
}

macro pmull2(...args) {
    a64_pmull2_shape(a64_operands(args, false, false, false, false, "pmull2"))
    a64_pmull2(a64_operands(args, false, false, true, false, "pmull2"))
}

macro prfm(...args) {
    a64_prfm_shape(a64_operands(args, false, false, false, true, "prfm"))
    a64_prfm(a64_operands(args, false, false, true, true, "prfm"))
}

macro prfum(...args) {
    a64_prfum_shape(a64_operands(args, false, false, false, false, "prfum"))
    a64_prfum(a64_operands(args, false, false, true, false, "prfum"))
}

macro pssbb(...args) {
    a64_pssbb_shape(a64_operands(args, false, false, false, false, "pssbb"))
    a64_pssbb(a64_operands(args, false, false, true, false, "pssbb"))
}

macro raddhn(...args) {
    a64_raddhn_shape(a64_operands(args, false, false, false, false, "raddhn"))
    a64_raddhn(a64_operands(args, false, false, true, false, "raddhn"))
}

macro raddhn2(...args) {
    a64_raddhn2_shape(a64_operands(args, false, false, false, false, "raddhn2"))
    a64_raddhn2(a64_operands(args, false, false, true, false, "raddhn2"))
}

macro rax1(...args) {
    a64_rax1_shape(a64_operands(args, false, false, false, false, "rax1"))
    a64_rax1(a64_operands(args, false, false, true, false, "rax1"))
}

macro rbit(...args) {
    a64_rbit_shape(a64_operands(args, false, false, false, false, "rbit"))
    a64_rbit(a64_operands(args, false, false, true, false, "rbit"))
}

macro ret(...args) {
    a64_ret_shape(a64_operands(args, false, false, false, false, "ret"))
    a64_ret(a64_operands(args, false, false, true, false, "ret"))
}

macro retaa(...args) {
    a64_retaa_shape(a64_operands(args, false, false, false, false, "retaa"))
    a64_retaa(a64_operands(args, false, false, true, false, "retaa"))
}

macro retab(...args) {
    a64_retab_shape(a64_operands(args, false, false, false, false, "retab"))
    a64_retab(a64_operands(args, false, false, true, false, "retab"))
}

macro rev(...args) {
    a64_rev_shape(a64_operands(args, false, false, false, false, "rev"))
    a64_rev(a64_operands(args, false, false, true, false, "rev"))
}

macro rev16(...args) {
    a64_rev16_shape(a64_operands(args, false, false, false, false, "rev16"))
    a64_rev16(a64_operands(args, false, false, true, false, "rev16"))
}

macro rev32(...args) {
    a64_rev32_shape(a64_operands(args, false, false, false, false, "rev32"))
    a64_rev32(a64_operands(args, false, false, true, false, "rev32"))
}

macro rev64(...args) {
    a64_rev64_shape(a64_operands(args, false, false, false, false, "rev64"))
    a64_rev64(a64_operands(args, false, false, true, false, "rev64"))
}

macro rmif(...args) {
    a64_rmif_shape(a64_operands(args, false, false, false, false, "rmif"))
    a64_rmif(a64_operands(args, false, false, true, false, "rmif"))
}

macro ror(...args) {
    a64_ror_shape(a64_operands(args, false, false, false, false, "ror"))
    a64_ror(a64_operands(args, false, false, true, false, "ror"))
}

macro rorv(...args) {
    a64_rorv_shape(a64_operands(args, false, false, false, false, "rorv"))
    a64_rorv(a64_operands(args, false, false, true, false, "rorv"))
}

macro rshrn(...args) {
    a64_rshrn_shape(a64_operands(args, false, false, false, false, "rshrn"))
    a64_rshrn(a64_operands(args, false, false, true, false, "rshrn"))
}

macro rshrn2(...args) {
    a64_rshrn2_shape(a64_operands(args, false, false, false, false, "rshrn2"))
    a64_rshrn2(a64_operands(args, false, false, true, false, "rshrn2"))
}

macro rsubhn(...args) {
    a64_rsubhn_shape(a64_operands(args, false, false, false, false, "rsubhn"))
    a64_rsubhn(a64_operands(args, false, false, true, false, "rsubhn"))
}

macro rsubhn2(...args) {
    a64_rsubhn2_shape(a64_operands(args, false, false, false, false, "rsubhn2"))
    a64_rsubhn2(a64_operands(args, false, false, true, false, "rsubhn2"))
}

macro saba(...args) {
    a64_saba_shape(a64_operands(args, false, false, false, false, "saba"))
    a64_saba(a64_operands(args, false, false, true, false, "saba"))
}

macro sabal(...args) {
    a64_sabal_shape(a64_operands(args, false, false, false, false, "sabal"))
    a64_sabal(a64_operands(args, false, false, true, false, "sabal"))
}

macro sabal2(...args) {
    a64_sabal2_shape(a64_operands(args, false, false, false, false, "sabal2"))
    a64_sabal2(a64_operands(args, false, false, true, false, "sabal2"))
}

macro sabd(...args) {
    a64_sabd_shape(a64_operands(args, false, false, false, false, "sabd"))
    a64_sabd(a64_operands(args, false, false, true, false, "sabd"))
}

macro sabdl(...args) {
    a64_sabdl_shape(a64_operands(args, false, false, false, false, "sabdl"))
    a64_sabdl(a64_operands(args, false, false, true, false, "sabdl"))
}

macro sabdl2(...args) {
    a64_sabdl2_shape(a64_operands(args, false, false, false, false, "sabdl2"))
    a64_sabdl2(a64_operands(args, false, false, true, false, "sabdl2"))
}

macro sadalp(...args) {
    a64_sadalp_shape(a64_operands(args, false, false, false, false, "sadalp"))
    a64_sadalp(a64_operands(args, false, false, true, false, "sadalp"))
}

macro saddl(...args) {
    a64_saddl_shape(a64_operands(args, false, false, false, false, "saddl"))
    a64_saddl(a64_operands(args, false, false, true, false, "saddl"))
}

macro saddl2(...args) {
    a64_saddl2_shape(a64_operands(args, false, false, false, false, "saddl2"))
    a64_saddl2(a64_operands(args, false, false, true, false, "saddl2"))
}

macro saddlp(...args) {
    a64_saddlp_shape(a64_operands(args, false, false, false, false, "saddlp"))
    a64_saddlp(a64_operands(args, false, false, true, false, "saddlp"))
}

macro saddlv(...args) {
    a64_saddlv_shape(a64_operands(args, false, false, false, false, "saddlv"))
    a64_saddlv(a64_operands(args, false, false, true, false, "saddlv"))
}

macro saddw(...args) {
    a64_saddw_shape(a64_operands(args, false, false, false, false, "saddw"))
    a64_saddw(a64_operands(args, false, false, true, false, "saddw"))
}

macro saddw2(...args) {
    a64_saddw2_shape(a64_operands(args, false, false, false, false, "saddw2"))
    a64_saddw2(a64_operands(args, false, false, true, false, "saddw2"))
}

macro sb(...args) {
    a64_sb_shape(a64_operands(args, false, false, false, false, "sb"))
    a64_sb(a64_operands(args, false, false, true, false, "sb"))
}

macro sbc(...args) {
    a64_sbc_shape(a64_operands(args, false, false, false, false, "sbc"))
    a64_sbc(a64_operands(args, false, false, true, false, "sbc"))
}

macro sbcs(...args) {
    a64_sbcs_shape(a64_operands(args, false, false, false, false, "sbcs"))
    a64_sbcs(a64_operands(args, false, false, true, false, "sbcs"))
}

macro sbfiz(...args) {
    a64_sbfiz_shape(a64_operands(args, false, false, false, false, "sbfiz"))
    a64_sbfiz(a64_operands(args, false, false, true, false, "sbfiz"))
}

macro sbfm(...args) {
    a64_sbfm_shape(a64_operands(args, false, false, false, false, "sbfm"))
    a64_sbfm(a64_operands(args, false, false, true, false, "sbfm"))
}

macro sbfx(...args) {
    a64_sbfx_shape(a64_operands(args, false, false, false, false, "sbfx"))
    a64_sbfx(a64_operands(args, false, false, true, false, "sbfx"))
}

macro scvtf(...args) {
    a64_scvtf_shape(a64_operands(args, false, false, false, false, "scvtf"))
    a64_scvtf(a64_operands(args, false, false, true, false, "scvtf"))
}

macro sdiv(...args) {
    a64_sdiv_shape(a64_operands(args, false, false, false, false, "sdiv"))
    a64_sdiv(a64_operands(args, false, false, true, false, "sdiv"))
}

macro sdot(...args) {
    a64_sdot_shape(a64_operands(args, false, false, false, false, "sdot"))
    a64_sdot(a64_operands(args, false, false, true, false, "sdot"))
}

macro setf16(...args) {
    a64_setf16_shape(a64_operands(args, false, false, false, false, "setf16"))
    a64_setf16(a64_operands(args, false, false, true, false, "setf16"))
}

macro setf8(...args) {
    a64_setf8_shape(a64_operands(args, false, false, false, false, "setf8"))
    a64_setf8(a64_operands(args, false, false, true, false, "setf8"))
}

macro sev(...args) {
    a64_sev_shape(a64_operands(args, false, false, false, false, "sev"))
    a64_sev(a64_operands(args, false, false, true, false, "sev"))
}

macro sevl(...args) {
    a64_sevl_shape(a64_operands(args, false, false, false, false, "sevl"))
    a64_sevl(a64_operands(args, false, false, true, false, "sevl"))
}

macro sha1c(...args) {
    a64_sha1c_shape(a64_operands(args, false, false, false, false, "sha1c"))
    a64_sha1c(a64_operands(args, false, false, true, false, "sha1c"))
}

macro sha1h(...args) {
    a64_sha1h_shape(a64_operands(args, false, false, false, false, "sha1h"))
    a64_sha1h(a64_operands(args, false, false, true, false, "sha1h"))
}

macro sha1m(...args) {
    a64_sha1m_shape(a64_operands(args, false, false, false, false, "sha1m"))
    a64_sha1m(a64_operands(args, false, false, true, false, "sha1m"))
}

macro sha1p(...args) {
    a64_sha1p_shape(a64_operands(args, false, false, false, false, "sha1p"))
    a64_sha1p(a64_operands(args, false, false, true, false, "sha1p"))
}

macro sha1su0(...args) {
    a64_sha1su0_shape(a64_operands(args, false, false, false, false, "sha1su0"))
    a64_sha1su0(a64_operands(args, false, false, true, false, "sha1su0"))
}

macro sha1su1(...args) {
    a64_sha1su1_shape(a64_operands(args, false, false, false, false, "sha1su1"))
    a64_sha1su1(a64_operands(args, false, false, true, false, "sha1su1"))
}

macro sha256h(...args) {
    a64_sha256h_shape(a64_operands(args, false, false, false, false, "sha256h"))
    a64_sha256h(a64_operands(args, false, false, true, false, "sha256h"))
}

macro sha256h2(...args) {
    a64_sha256h2_shape(a64_operands(args, false, false, false, false, "sha256h2"))
    a64_sha256h2(a64_operands(args, false, false, true, false, "sha256h2"))
}

macro sha256su0(...args) {
    a64_sha256su0_shape(a64_operands(args, false, false, false, false, "sha256su0"))
    a64_sha256su0(a64_operands(args, false, false, true, false, "sha256su0"))
}

macro sha256su1(...args) {
    a64_sha256su1_shape(a64_operands(args, false, false, false, false, "sha256su1"))
    a64_sha256su1(a64_operands(args, false, false, true, false, "sha256su1"))
}

macro sha512h(...args) {
    a64_sha512h_shape(a64_operands(args, false, false, false, false, "sha512h"))
    a64_sha512h(a64_operands(args, false, false, true, false, "sha512h"))
}

macro sha512h2(...args) {
    a64_sha512h2_shape(a64_operands(args, false, false, false, false, "sha512h2"))
    a64_sha512h2(a64_operands(args, false, false, true, false, "sha512h2"))
}

macro sha512su0(...args) {
    a64_sha512su0_shape(a64_operands(args, false, false, false, false, "sha512su0"))
    a64_sha512su0(a64_operands(args, false, false, true, false, "sha512su0"))
}

macro sha512su1(...args) {
    a64_sha512su1_shape(a64_operands(args, false, false, false, false, "sha512su1"))
    a64_sha512su1(a64_operands(args, false, false, true, false, "sha512su1"))
}

macro shadd(...args) {
    a64_shadd_shape(a64_operands(args, false, false, false, false, "shadd"))
    a64_shadd(a64_operands(args, false, false, true, false, "shadd"))
}

macro shl(...args) {
    a64_shl_shape(a64_operands(args, false, false, false, false, "shl"))
    a64_shl(a64_operands(args, false, false, true, false, "shl"))
}

macro shll(...args) {
    a64_shll_shape(a64_operands(args, false, false, false, false, "shll"))
    a64_shll(a64_operands(args, false, false, true, false, "shll"))
}

macro shll2(...args) {
    a64_shll2_shape(a64_operands(args, false, false, false, false, "shll2"))
    a64_shll2(a64_operands(args, false, false, true, false, "shll2"))
}

macro shrn(...args) {
    a64_shrn_shape(a64_operands(args, false, false, false, false, "shrn"))
    a64_shrn(a64_operands(args, false, false, true, false, "shrn"))
}

macro shrn2(...args) {
    a64_shrn2_shape(a64_operands(args, false, false, false, false, "shrn2"))
    a64_shrn2(a64_operands(args, false, false, true, false, "shrn2"))
}

macro shsub(...args) {
    a64_shsub_shape(a64_operands(args, false, false, false, false, "shsub"))
    a64_shsub(a64_operands(args, false, false, true, false, "shsub"))
}

macro sli(...args) {
    a64_sli_shape(a64_operands(args, false, false, false, false, "sli"))
    a64_sli(a64_operands(args, false, false, true, false, "sli"))
}

macro sm3partw1(...args) {
    a64_sm3partw1_shape(a64_operands(args, false, false, false, false, "sm3partw1"))
    a64_sm3partw1(a64_operands(args, false, false, true, false, "sm3partw1"))
}

macro sm3partw2(...args) {
    a64_sm3partw2_shape(a64_operands(args, false, false, false, false, "sm3partw2"))
    a64_sm3partw2(a64_operands(args, false, false, true, false, "sm3partw2"))
}

macro sm3ss1(...args) {
    a64_sm3ss1_shape(a64_operands(args, false, false, false, false, "sm3ss1"))
    a64_sm3ss1(a64_operands(args, false, false, true, false, "sm3ss1"))
}

macro sm3tt1a(...args) {
    a64_sm3tt1a_shape(a64_operands(args, false, false, false, false, "sm3tt1a"))
    a64_sm3tt1a(a64_operands(args, false, false, true, false, "sm3tt1a"))
}

macro sm3tt1b(...args) {
    a64_sm3tt1b_shape(a64_operands(args, false, false, false, false, "sm3tt1b"))
    a64_sm3tt1b(a64_operands(args, false, false, true, false, "sm3tt1b"))
}

macro sm3tt2a(...args) {
    a64_sm3tt2a_shape(a64_operands(args, false, false, false, false, "sm3tt2a"))
    a64_sm3tt2a(a64_operands(args, false, false, true, false, "sm3tt2a"))
}

macro sm3tt2b(...args) {
    a64_sm3tt2b_shape(a64_operands(args, false, false, false, false, "sm3tt2b"))
    a64_sm3tt2b(a64_operands(args, false, false, true, false, "sm3tt2b"))
}

macro sm4e(...args) {
    a64_sm4e_shape(a64_operands(args, false, false, false, false, "sm4e"))
    a64_sm4e(a64_operands(args, false, false, true, false, "sm4e"))
}

macro sm4ekey(...args) {
    a64_sm4ekey_shape(a64_operands(args, false, false, false, false, "sm4ekey"))
    a64_sm4ekey(a64_operands(args, false, false, true, false, "sm4ekey"))
}

macro smaddl(...args) {
    a64_smaddl_shape(a64_operands(args, false, false, false, false, "smaddl"))
    a64_smaddl(a64_operands(args, false, false, true, false, "smaddl"))
}

macro smax(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "smax")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 134743040 || key == 134743042 || key == 135005696 || key == 135005699 {
        a64_e5_smax_shape(shaped)
        a64_e5_smax(a64_operands(args, false, false, true, false, "smax"))
    } else {
        a64_smax_shape(shaped)
        a64_smax(a64_operands(args, false, false, true, false, "smax"))
    }
}

macro smaxp(...args) {
    a64_smaxp_shape(a64_operands(args, false, false, false, false, "smaxp"))
    a64_smaxp(a64_operands(args, false, false, true, false, "smaxp"))
}

macro smaxv(...args) {
    a64_smaxv_shape(a64_operands(args, false, false, false, false, "smaxv"))
    a64_smaxv(a64_operands(args, false, false, true, false, "smaxv"))
}

macro smc(...args) {
    a64_smc_shape(a64_operands(args, false, false, false, false, "smc"))
    a64_smc(a64_operands(args, false, false, true, false, "smc"))
}

macro smin(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "smin")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 134743040 || key == 134743042 || key == 135005696 || key == 135005699 {
        a64_e5_smin_shape(shaped)
        a64_e5_smin(a64_operands(args, false, false, true, false, "smin"))
    } else {
        a64_smin_shape(shaped)
        a64_smin(a64_operands(args, false, false, true, false, "smin"))
    }
}

macro sminp(...args) {
    a64_sminp_shape(a64_operands(args, false, false, false, false, "sminp"))
    a64_sminp(a64_operands(args, false, false, true, false, "sminp"))
}

macro sminv(...args) {
    a64_sminv_shape(a64_operands(args, false, false, false, false, "sminv"))
    a64_sminv(a64_operands(args, false, false, true, false, "sminv"))
}

macro smlal(...args) {
    a64_smlal_shape(a64_operands(args, false, false, false, false, "smlal"))
    a64_smlal(a64_operands(args, false, false, true, false, "smlal"))
}

macro smlal2(...args) {
    a64_smlal2_shape(a64_operands(args, false, false, false, false, "smlal2"))
    a64_smlal2(a64_operands(args, false, false, true, false, "smlal2"))
}

macro smlsl(...args) {
    a64_smlsl_shape(a64_operands(args, false, false, false, false, "smlsl"))
    a64_smlsl(a64_operands(args, false, false, true, false, "smlsl"))
}

macro smlsl2(...args) {
    a64_smlsl2_shape(a64_operands(args, false, false, false, false, "smlsl2"))
    a64_smlsl2(a64_operands(args, false, false, true, false, "smlsl2"))
}

macro smmla(...args) {
    a64_smmla_shape(a64_operands(args, false, false, false, false, "smmla"))
    a64_smmla(a64_operands(args, false, false, true, false, "smmla"))
}

macro smnegl(...args) {
    a64_smnegl_shape(a64_operands(args, false, false, false, false, "smnegl"))
    a64_smnegl(a64_operands(args, false, false, true, false, "smnegl"))
}

macro smov(...args) {
    a64_smov_shape(a64_operands(args, false, false, false, false, "smov"))
    a64_smov(a64_operands(args, false, false, true, false, "smov"))
}

macro smsubl(...args) {
    a64_smsubl_shape(a64_operands(args, false, false, false, false, "smsubl"))
    a64_smsubl(a64_operands(args, false, false, true, false, "smsubl"))
}

macro smulh(...args) {
    a64_smulh_shape(a64_operands(args, false, false, false, false, "smulh"))
    a64_smulh(a64_operands(args, false, false, true, false, "smulh"))
}

macro smull(...args) {
    a64_smull_shape(a64_operands(args, false, false, false, false, "smull"))
    a64_smull(a64_operands(args, false, false, true, false, "smull"))
}

macro smull2(...args) {
    a64_smull2_shape(a64_operands(args, false, false, false, false, "smull2"))
    a64_smull2(a64_operands(args, false, false, true, false, "smull2"))
}

macro sqabs(...args) {
    a64_sqabs_shape(a64_operands(args, false, false, false, false, "sqabs"))
    a64_sqabs(a64_operands(args, false, false, true, false, "sqabs"))
}

macro sqadd(...args) {
    a64_sqadd_shape(a64_operands(args, false, false, false, false, "sqadd"))
    a64_sqadd(a64_operands(args, false, false, true, false, "sqadd"))
}

macro sqdmlal(...args) {
    a64_sqdmlal_shape(a64_operands(args, false, false, false, false, "sqdmlal"))
    a64_sqdmlal(a64_operands(args, false, false, true, false, "sqdmlal"))
}

macro sqdmlal2(...args) {
    a64_sqdmlal2_shape(a64_operands(args, false, false, false, false, "sqdmlal2"))
    a64_sqdmlal2(a64_operands(args, false, false, true, false, "sqdmlal2"))
}

macro sqdmlsl(...args) {
    a64_sqdmlsl_shape(a64_operands(args, false, false, false, false, "sqdmlsl"))
    a64_sqdmlsl(a64_operands(args, false, false, true, false, "sqdmlsl"))
}

macro sqdmlsl2(...args) {
    a64_sqdmlsl2_shape(a64_operands(args, false, false, false, false, "sqdmlsl2"))
    a64_sqdmlsl2(a64_operands(args, false, false, true, false, "sqdmlsl2"))
}

macro sqdmulh(...args) {
    a64_sqdmulh_shape(a64_operands(args, false, false, false, false, "sqdmulh"))
    a64_sqdmulh(a64_operands(args, false, false, true, false, "sqdmulh"))
}

macro sqdmull(...args) {
    a64_sqdmull_shape(a64_operands(args, false, false, false, false, "sqdmull"))
    a64_sqdmull(a64_operands(args, false, false, true, false, "sqdmull"))
}

macro sqdmull2(...args) {
    a64_sqdmull2_shape(a64_operands(args, false, false, false, false, "sqdmull2"))
    a64_sqdmull2(a64_operands(args, false, false, true, false, "sqdmull2"))
}

macro sqneg(...args) {
    a64_sqneg_shape(a64_operands(args, false, false, false, false, "sqneg"))
    a64_sqneg(a64_operands(args, false, false, true, false, "sqneg"))
}

macro sqrdmlah(...args) {
    a64_sqrdmlah_shape(a64_operands(args, false, false, false, false, "sqrdmlah"))
    a64_sqrdmlah(a64_operands(args, false, false, true, false, "sqrdmlah"))
}

macro sqrdmlsh(...args) {
    a64_sqrdmlsh_shape(a64_operands(args, false, false, false, false, "sqrdmlsh"))
    a64_sqrdmlsh(a64_operands(args, false, false, true, false, "sqrdmlsh"))
}

macro sqrdmulh(...args) {
    a64_sqrdmulh_shape(a64_operands(args, false, false, false, false, "sqrdmulh"))
    a64_sqrdmulh(a64_operands(args, false, false, true, false, "sqrdmulh"))
}

macro sqrshl(...args) {
    a64_sqrshl_shape(a64_operands(args, false, false, false, false, "sqrshl"))
    a64_sqrshl(a64_operands(args, false, false, true, false, "sqrshl"))
}

macro sqrshrn(...args) {
    a64_sqrshrn_shape(a64_operands(args, false, false, false, false, "sqrshrn"))
    a64_sqrshrn(a64_operands(args, false, false, true, false, "sqrshrn"))
}

macro sqrshrn2(...args) {
    a64_sqrshrn2_shape(a64_operands(args, false, false, false, false, "sqrshrn2"))
    a64_sqrshrn2(a64_operands(args, false, false, true, false, "sqrshrn2"))
}

macro sqrshrun(...args) {
    a64_sqrshrun_shape(a64_operands(args, false, false, false, false, "sqrshrun"))
    a64_sqrshrun(a64_operands(args, false, false, true, false, "sqrshrun"))
}

macro sqrshrun2(...args) {
    a64_sqrshrun2_shape(a64_operands(args, false, false, false, false, "sqrshrun2"))
    a64_sqrshrun2(a64_operands(args, false, false, true, false, "sqrshrun2"))
}

macro sqshl(...args) {
    a64_sqshl_shape(a64_operands(args, false, false, false, false, "sqshl"))
    a64_sqshl(a64_operands(args, false, false, true, false, "sqshl"))
}

macro sqshlu(...args) {
    a64_sqshlu_shape(a64_operands(args, false, false, false, false, "sqshlu"))
    a64_sqshlu(a64_operands(args, false, false, true, false, "sqshlu"))
}

macro sqshrn(...args) {
    a64_sqshrn_shape(a64_operands(args, false, false, false, false, "sqshrn"))
    a64_sqshrn(a64_operands(args, false, false, true, false, "sqshrn"))
}

macro sqshrn2(...args) {
    a64_sqshrn2_shape(a64_operands(args, false, false, false, false, "sqshrn2"))
    a64_sqshrn2(a64_operands(args, false, false, true, false, "sqshrn2"))
}

macro sqshrun(...args) {
    a64_sqshrun_shape(a64_operands(args, false, false, false, false, "sqshrun"))
    a64_sqshrun(a64_operands(args, false, false, true, false, "sqshrun"))
}

macro sqshrun2(...args) {
    a64_sqshrun2_shape(a64_operands(args, false, false, false, false, "sqshrun2"))
    a64_sqshrun2(a64_operands(args, false, false, true, false, "sqshrun2"))
}

macro sqsub(...args) {
    a64_sqsub_shape(a64_operands(args, false, false, false, false, "sqsub"))
    a64_sqsub(a64_operands(args, false, false, true, false, "sqsub"))
}

macro sqxtn(...args) {
    a64_sqxtn_shape(a64_operands(args, false, false, false, false, "sqxtn"))
    a64_sqxtn(a64_operands(args, false, false, true, false, "sqxtn"))
}

macro sqxtn2(...args) {
    a64_sqxtn2_shape(a64_operands(args, false, false, false, false, "sqxtn2"))
    a64_sqxtn2(a64_operands(args, false, false, true, false, "sqxtn2"))
}

macro sqxtun(...args) {
    a64_sqxtun_shape(a64_operands(args, false, false, false, false, "sqxtun"))
    a64_sqxtun(a64_operands(args, false, false, true, false, "sqxtun"))
}

macro sqxtun2(...args) {
    a64_sqxtun2_shape(a64_operands(args, false, false, false, false, "sqxtun2"))
    a64_sqxtun2(a64_operands(args, false, false, true, false, "sqxtun2"))
}

macro srhadd(...args) {
    a64_srhadd_shape(a64_operands(args, false, false, false, false, "srhadd"))
    a64_srhadd(a64_operands(args, false, false, true, false, "srhadd"))
}

macro sri(...args) {
    a64_sri_shape(a64_operands(args, false, false, false, false, "sri"))
    a64_sri(a64_operands(args, false, false, true, false, "sri"))
}

macro srshl(...args) {
    a64_srshl_shape(a64_operands(args, false, false, false, false, "srshl"))
    a64_srshl(a64_operands(args, false, false, true, false, "srshl"))
}

macro srshr(...args) {
    a64_srshr_shape(a64_operands(args, false, false, false, false, "srshr"))
    a64_srshr(a64_operands(args, false, false, true, false, "srshr"))
}

macro srsra(...args) {
    a64_srsra_shape(a64_operands(args, false, false, false, false, "srsra"))
    a64_srsra(a64_operands(args, false, false, true, false, "srsra"))
}

macro ssbb(...args) {
    a64_ssbb_shape(a64_operands(args, false, false, false, false, "ssbb"))
    a64_ssbb(a64_operands(args, false, false, true, false, "ssbb"))
}

macro sshl(...args) {
    a64_sshl_shape(a64_operands(args, false, false, false, false, "sshl"))
    a64_sshl(a64_operands(args, false, false, true, false, "sshl"))
}

macro sshll(...args) {
    a64_sshll_shape(a64_operands(args, false, false, false, false, "sshll"))
    a64_sshll(a64_operands(args, false, false, true, false, "sshll"))
}

macro sshll2(...args) {
    a64_sshll2_shape(a64_operands(args, false, false, false, false, "sshll2"))
    a64_sshll2(a64_operands(args, false, false, true, false, "sshll2"))
}

macro sshr(...args) {
    a64_sshr_shape(a64_operands(args, false, false, false, false, "sshr"))
    a64_sshr(a64_operands(args, false, false, true, false, "sshr"))
}

macro ssra(...args) {
    a64_ssra_shape(a64_operands(args, false, false, false, false, "ssra"))
    a64_ssra(a64_operands(args, false, false, true, false, "ssra"))
}

macro ssubl(...args) {
    a64_ssubl_shape(a64_operands(args, false, false, false, false, "ssubl"))
    a64_ssubl(a64_operands(args, false, false, true, false, "ssubl"))
}

macro ssubl2(...args) {
    a64_ssubl2_shape(a64_operands(args, false, false, false, false, "ssubl2"))
    a64_ssubl2(a64_operands(args, false, false, true, false, "ssubl2"))
}

macro ssubw(...args) {
    a64_ssubw_shape(a64_operands(args, false, false, false, false, "ssubw"))
    a64_ssubw(a64_operands(args, false, false, true, false, "ssubw"))
}

macro ssubw2(...args) {
    a64_ssubw2_shape(a64_operands(args, false, false, false, false, "ssubw2"))
    a64_ssubw2(a64_operands(args, false, false, true, false, "ssubw2"))
}

macro st1(...args) {
    a64_st1_shape(a64_operands(args, false, false, false, false, "st1"))
    a64_st1(a64_operands(args, false, false, true, false, "st1"))
}

macro st2(...args) {
    a64_st2_shape(a64_operands(args, false, false, false, false, "st2"))
    a64_st2(a64_operands(args, false, false, true, false, "st2"))
}

macro st2g(...args) {
    a64_st2g_shape(a64_operands(args, false, false, false, false, "st2g"))
    a64_st2g(a64_operands(args, false, false, true, false, "st2g"))
}

macro st3(...args) {
    a64_st3_shape(a64_operands(args, false, false, false, false, "st3"))
    a64_st3(a64_operands(args, false, false, true, false, "st3"))
}

macro st4(...args) {
    a64_st4_shape(a64_operands(args, false, false, false, false, "st4"))
    a64_st4(a64_operands(args, false, false, true, false, "st4"))
}

macro stadd(...args) {
    a64_stadd_shape(a64_operands(args, false, false, false, false, "stadd"))
    a64_stadd(a64_operands(args, false, false, true, false, "stadd"))
}

macro staddb(...args) {
    a64_staddb_shape(a64_operands(args, false, false, false, false, "staddb"))
    a64_staddb(a64_operands(args, false, false, true, false, "staddb"))
}

macro staddh(...args) {
    a64_staddh_shape(a64_operands(args, false, false, false, false, "staddh"))
    a64_staddh(a64_operands(args, false, false, true, false, "staddh"))
}

macro staddl(...args) {
    a64_staddl_shape(a64_operands(args, false, false, false, false, "staddl"))
    a64_staddl(a64_operands(args, false, false, true, false, "staddl"))
}

macro staddlb(...args) {
    a64_staddlb_shape(a64_operands(args, false, false, false, false, "staddlb"))
    a64_staddlb(a64_operands(args, false, false, true, false, "staddlb"))
}

macro staddlh(...args) {
    a64_staddlh_shape(a64_operands(args, false, false, false, false, "staddlh"))
    a64_staddlh(a64_operands(args, false, false, true, false, "staddlh"))
}

macro stclr(...args) {
    a64_stclr_shape(a64_operands(args, false, false, false, false, "stclr"))
    a64_stclr(a64_operands(args, false, false, true, false, "stclr"))
}

macro stclrb(...args) {
    a64_stclrb_shape(a64_operands(args, false, false, false, false, "stclrb"))
    a64_stclrb(a64_operands(args, false, false, true, false, "stclrb"))
}

macro stclrh(...args) {
    a64_stclrh_shape(a64_operands(args, false, false, false, false, "stclrh"))
    a64_stclrh(a64_operands(args, false, false, true, false, "stclrh"))
}

macro stclrl(...args) {
    a64_stclrl_shape(a64_operands(args, false, false, false, false, "stclrl"))
    a64_stclrl(a64_operands(args, false, false, true, false, "stclrl"))
}

macro stclrlb(...args) {
    a64_stclrlb_shape(a64_operands(args, false, false, false, false, "stclrlb"))
    a64_stclrlb(a64_operands(args, false, false, true, false, "stclrlb"))
}

macro stclrlh(...args) {
    a64_stclrlh_shape(a64_operands(args, false, false, false, false, "stclrlh"))
    a64_stclrlh(a64_operands(args, false, false, true, false, "stclrlh"))
}

macro steor(...args) {
    a64_steor_shape(a64_operands(args, false, false, false, false, "steor"))
    a64_steor(a64_operands(args, false, false, true, false, "steor"))
}

macro steorb(...args) {
    a64_steorb_shape(a64_operands(args, false, false, false, false, "steorb"))
    a64_steorb(a64_operands(args, false, false, true, false, "steorb"))
}

macro steorh(...args) {
    a64_steorh_shape(a64_operands(args, false, false, false, false, "steorh"))
    a64_steorh(a64_operands(args, false, false, true, false, "steorh"))
}

macro steorl(...args) {
    a64_steorl_shape(a64_operands(args, false, false, false, false, "steorl"))
    a64_steorl(a64_operands(args, false, false, true, false, "steorl"))
}

macro steorlb(...args) {
    a64_steorlb_shape(a64_operands(args, false, false, false, false, "steorlb"))
    a64_steorlb(a64_operands(args, false, false, true, false, "steorlb"))
}

macro steorlh(...args) {
    a64_steorlh_shape(a64_operands(args, false, false, false, false, "steorlh"))
    a64_steorlh(a64_operands(args, false, false, true, false, "steorlh"))
}

macro stg(...args) {
    a64_stg_shape(a64_operands(args, false, false, false, false, "stg"))
    a64_stg(a64_operands(args, false, false, true, false, "stg"))
}

macro stgm(...args) {
    a64_stgm_shape(a64_operands(args, false, false, false, false, "stgm"))
    a64_stgm(a64_operands(args, false, false, true, false, "stgm"))
}

macro stgp(...args) {
    a64_stgp_shape(a64_operands(args, false, false, false, false, "stgp"))
    a64_stgp(a64_operands(args, false, false, true, false, "stgp"))
}

macro stllr(...args) {
    a64_stllr_shape(a64_operands(args, false, false, false, false, "stllr"))
    a64_stllr(a64_operands(args, false, false, true, false, "stllr"))
}

macro stllrb(...args) {
    a64_stllrb_shape(a64_operands(args, false, false, false, false, "stllrb"))
    a64_stllrb(a64_operands(args, false, false, true, false, "stllrb"))
}

macro stllrh(...args) {
    a64_stllrh_shape(a64_operands(args, false, false, false, false, "stllrh"))
    a64_stllrh(a64_operands(args, false, false, true, false, "stllrh"))
}

macro stlr(...args) {
    a64_stlr_shape(a64_operands(args, false, false, false, false, "stlr"))
    a64_stlr(a64_operands(args, false, false, true, false, "stlr"))
}

macro stlrb(...args) {
    a64_stlrb_shape(a64_operands(args, false, false, false, false, "stlrb"))
    a64_stlrb(a64_operands(args, false, false, true, false, "stlrb"))
}

macro stlrh(...args) {
    a64_stlrh_shape(a64_operands(args, false, false, false, false, "stlrh"))
    a64_stlrh(a64_operands(args, false, false, true, false, "stlrh"))
}

macro stlur(...args) {
    a64_stlur_shape(a64_operands(args, false, false, false, false, "stlur"))
    a64_stlur(a64_operands(args, false, false, true, false, "stlur"))
}

macro stlurb(...args) {
    a64_stlurb_shape(a64_operands(args, false, false, false, false, "stlurb"))
    a64_stlurb(a64_operands(args, false, false, true, false, "stlurb"))
}

macro stlurh(...args) {
    a64_stlurh_shape(a64_operands(args, false, false, false, false, "stlurh"))
    a64_stlurh(a64_operands(args, false, false, true, false, "stlurh"))
}

macro stlxp(...args) {
    a64_stlxp_shape(a64_operands(args, false, false, false, false, "stlxp"))
    a64_stlxp(a64_operands(args, false, false, true, false, "stlxp"))
}

macro stlxr(...args) {
    a64_stlxr_shape(a64_operands(args, false, false, false, false, "stlxr"))
    a64_stlxr(a64_operands(args, false, false, true, false, "stlxr"))
}

macro stlxrb(...args) {
    a64_stlxrb_shape(a64_operands(args, false, false, false, false, "stlxrb"))
    a64_stlxrb(a64_operands(args, false, false, true, false, "stlxrb"))
}

macro stlxrh(...args) {
    a64_stlxrh_shape(a64_operands(args, false, false, false, false, "stlxrh"))
    a64_stlxrh(a64_operands(args, false, false, true, false, "stlxrh"))
}

macro stnp(...args) {
    a64_stnp_shape(a64_operands(args, false, false, false, false, "stnp"))
    a64_stnp(a64_operands(args, false, false, true, false, "stnp"))
}

macro stp(...args) {
    a64_stp_shape(a64_operands(args, false, false, false, false, "stp"))
    a64_stp(a64_operands(args, false, false, true, false, "stp"))
}

macro str(...args) {
    a64_str_shape(a64_operands(args, false, false, false, false, "str"))
    a64_str(a64_operands(args, false, false, true, false, "str"))
}

macro strb(...args) {
    a64_strb_shape(a64_operands(args, false, false, false, false, "strb"))
    a64_strb(a64_operands(args, false, false, true, false, "strb"))
}

macro strh(...args) {
    a64_strh_shape(a64_operands(args, false, false, false, false, "strh"))
    a64_strh(a64_operands(args, false, false, true, false, "strh"))
}

macro stset(...args) {
    a64_stset_shape(a64_operands(args, false, false, false, false, "stset"))
    a64_stset(a64_operands(args, false, false, true, false, "stset"))
}

macro stsetb(...args) {
    a64_stsetb_shape(a64_operands(args, false, false, false, false, "stsetb"))
    a64_stsetb(a64_operands(args, false, false, true, false, "stsetb"))
}

macro stseth(...args) {
    a64_stseth_shape(a64_operands(args, false, false, false, false, "stseth"))
    a64_stseth(a64_operands(args, false, false, true, false, "stseth"))
}

macro stsetl(...args) {
    a64_stsetl_shape(a64_operands(args, false, false, false, false, "stsetl"))
    a64_stsetl(a64_operands(args, false, false, true, false, "stsetl"))
}

macro stsetlb(...args) {
    a64_stsetlb_shape(a64_operands(args, false, false, false, false, "stsetlb"))
    a64_stsetlb(a64_operands(args, false, false, true, false, "stsetlb"))
}

macro stsetlh(...args) {
    a64_stsetlh_shape(a64_operands(args, false, false, false, false, "stsetlh"))
    a64_stsetlh(a64_operands(args, false, false, true, false, "stsetlh"))
}

macro stsmax(...args) {
    a64_stsmax_shape(a64_operands(args, false, false, false, false, "stsmax"))
    a64_stsmax(a64_operands(args, false, false, true, false, "stsmax"))
}

macro stsmaxb(...args) {
    a64_stsmaxb_shape(a64_operands(args, false, false, false, false, "stsmaxb"))
    a64_stsmaxb(a64_operands(args, false, false, true, false, "stsmaxb"))
}

macro stsmaxh(...args) {
    a64_stsmaxh_shape(a64_operands(args, false, false, false, false, "stsmaxh"))
    a64_stsmaxh(a64_operands(args, false, false, true, false, "stsmaxh"))
}

macro stsmaxl(...args) {
    a64_stsmaxl_shape(a64_operands(args, false, false, false, false, "stsmaxl"))
    a64_stsmaxl(a64_operands(args, false, false, true, false, "stsmaxl"))
}

macro stsmaxlb(...args) {
    a64_stsmaxlb_shape(a64_operands(args, false, false, false, false, "stsmaxlb"))
    a64_stsmaxlb(a64_operands(args, false, false, true, false, "stsmaxlb"))
}

macro stsmaxlh(...args) {
    a64_stsmaxlh_shape(a64_operands(args, false, false, false, false, "stsmaxlh"))
    a64_stsmaxlh(a64_operands(args, false, false, true, false, "stsmaxlh"))
}

macro stsmin(...args) {
    a64_stsmin_shape(a64_operands(args, false, false, false, false, "stsmin"))
    a64_stsmin(a64_operands(args, false, false, true, false, "stsmin"))
}

macro stsminb(...args) {
    a64_stsminb_shape(a64_operands(args, false, false, false, false, "stsminb"))
    a64_stsminb(a64_operands(args, false, false, true, false, "stsminb"))
}

macro stsminh(...args) {
    a64_stsminh_shape(a64_operands(args, false, false, false, false, "stsminh"))
    a64_stsminh(a64_operands(args, false, false, true, false, "stsminh"))
}

macro stsminl(...args) {
    a64_stsminl_shape(a64_operands(args, false, false, false, false, "stsminl"))
    a64_stsminl(a64_operands(args, false, false, true, false, "stsminl"))
}

macro stsminlb(...args) {
    a64_stsminlb_shape(a64_operands(args, false, false, false, false, "stsminlb"))
    a64_stsminlb(a64_operands(args, false, false, true, false, "stsminlb"))
}

macro stsminlh(...args) {
    a64_stsminlh_shape(a64_operands(args, false, false, false, false, "stsminlh"))
    a64_stsminlh(a64_operands(args, false, false, true, false, "stsminlh"))
}

macro sttr(...args) {
    a64_sttr_shape(a64_operands(args, false, false, false, false, "sttr"))
    a64_sttr(a64_operands(args, false, false, true, false, "sttr"))
}

macro sttrb(...args) {
    a64_sttrb_shape(a64_operands(args, false, false, false, false, "sttrb"))
    a64_sttrb(a64_operands(args, false, false, true, false, "sttrb"))
}

macro sttrh(...args) {
    a64_sttrh_shape(a64_operands(args, false, false, false, false, "sttrh"))
    a64_sttrh(a64_operands(args, false, false, true, false, "sttrh"))
}

macro stumax(...args) {
    a64_stumax_shape(a64_operands(args, false, false, false, false, "stumax"))
    a64_stumax(a64_operands(args, false, false, true, false, "stumax"))
}

macro stumaxb(...args) {
    a64_stumaxb_shape(a64_operands(args, false, false, false, false, "stumaxb"))
    a64_stumaxb(a64_operands(args, false, false, true, false, "stumaxb"))
}

macro stumaxh(...args) {
    a64_stumaxh_shape(a64_operands(args, false, false, false, false, "stumaxh"))
    a64_stumaxh(a64_operands(args, false, false, true, false, "stumaxh"))
}

macro stumaxl(...args) {
    a64_stumaxl_shape(a64_operands(args, false, false, false, false, "stumaxl"))
    a64_stumaxl(a64_operands(args, false, false, true, false, "stumaxl"))
}

macro stumaxlb(...args) {
    a64_stumaxlb_shape(a64_operands(args, false, false, false, false, "stumaxlb"))
    a64_stumaxlb(a64_operands(args, false, false, true, false, "stumaxlb"))
}

macro stumaxlh(...args) {
    a64_stumaxlh_shape(a64_operands(args, false, false, false, false, "stumaxlh"))
    a64_stumaxlh(a64_operands(args, false, false, true, false, "stumaxlh"))
}

macro stumin(...args) {
    a64_stumin_shape(a64_operands(args, false, false, false, false, "stumin"))
    a64_stumin(a64_operands(args, false, false, true, false, "stumin"))
}

macro stuminb(...args) {
    a64_stuminb_shape(a64_operands(args, false, false, false, false, "stuminb"))
    a64_stuminb(a64_operands(args, false, false, true, false, "stuminb"))
}

macro stuminh(...args) {
    a64_stuminh_shape(a64_operands(args, false, false, false, false, "stuminh"))
    a64_stuminh(a64_operands(args, false, false, true, false, "stuminh"))
}

macro stuminl(...args) {
    a64_stuminl_shape(a64_operands(args, false, false, false, false, "stuminl"))
    a64_stuminl(a64_operands(args, false, false, true, false, "stuminl"))
}

macro stuminlb(...args) {
    a64_stuminlb_shape(a64_operands(args, false, false, false, false, "stuminlb"))
    a64_stuminlb(a64_operands(args, false, false, true, false, "stuminlb"))
}

macro stuminlh(...args) {
    a64_stuminlh_shape(a64_operands(args, false, false, false, false, "stuminlh"))
    a64_stuminlh(a64_operands(args, false, false, true, false, "stuminlh"))
}

macro stur(...args) {
    a64_stur_shape(a64_operands(args, false, false, false, false, "stur"))
    a64_stur(a64_operands(args, false, false, true, false, "stur"))
}

macro sturb(...args) {
    a64_sturb_shape(a64_operands(args, false, false, false, false, "sturb"))
    a64_sturb(a64_operands(args, false, false, true, false, "sturb"))
}

macro sturh(...args) {
    a64_sturh_shape(a64_operands(args, false, false, false, false, "sturh"))
    a64_sturh(a64_operands(args, false, false, true, false, "sturh"))
}

macro stxp(...args) {
    a64_stxp_shape(a64_operands(args, false, false, false, false, "stxp"))
    a64_stxp(a64_operands(args, false, false, true, false, "stxp"))
}

macro stxr(...args) {
    a64_stxr_shape(a64_operands(args, false, false, false, false, "stxr"))
    a64_stxr(a64_operands(args, false, false, true, false, "stxr"))
}

macro stxrb(...args) {
    a64_stxrb_shape(a64_operands(args, false, false, false, false, "stxrb"))
    a64_stxrb(a64_operands(args, false, false, true, false, "stxrb"))
}

macro stxrh(...args) {
    a64_stxrh_shape(a64_operands(args, false, false, false, false, "stxrh"))
    a64_stxrh(a64_operands(args, false, false, true, false, "stxrh"))
}

macro stz2g(...args) {
    a64_stz2g_shape(a64_operands(args, false, false, false, false, "stz2g"))
    a64_stz2g(a64_operands(args, false, false, true, false, "stz2g"))
}

macro stzg(...args) {
    a64_stzg_shape(a64_operands(args, false, false, false, false, "stzg"))
    a64_stzg(a64_operands(args, false, false, true, false, "stzg"))
}

macro stzgm(...args) {
    a64_stzgm_shape(a64_operands(args, false, false, false, false, "stzgm"))
    a64_stzgm(a64_operands(args, false, false, true, false, "stzgm"))
}

macro sub(...args) {
    a64_sub_shape(a64_operands(args, false, false, false, false, "sub"))
    a64_sub(a64_operands(args, false, false, true, false, "sub"))
}

macro subg(...args) {
    a64_subg_shape(a64_operands(args, false, false, false, false, "subg"))
    a64_subg(a64_operands(args, false, false, true, false, "subg"))
}

macro subhn(...args) {
    a64_subhn_shape(a64_operands(args, false, false, false, false, "subhn"))
    a64_subhn(a64_operands(args, false, false, true, false, "subhn"))
}

macro subhn2(...args) {
    a64_subhn2_shape(a64_operands(args, false, false, false, false, "subhn2"))
    a64_subhn2(a64_operands(args, false, false, true, false, "subhn2"))
}

macro subp(...args) {
    a64_subp_shape(a64_operands(args, false, false, false, false, "subp"))
    a64_subp(a64_operands(args, false, false, true, false, "subp"))
}

macro subps(...args) {
    a64_subps_shape(a64_operands(args, false, false, false, false, "subps"))
    a64_subps(a64_operands(args, false, false, true, false, "subps"))
}

macro subs(...args) {
    a64_subs_shape(a64_operands(args, false, false, false, false, "subs"))
    a64_subs(a64_operands(args, false, false, true, false, "subs"))
}

macro sudot(...args) {
    a64_sudot_shape(a64_operands(args, false, false, false, false, "sudot"))
    a64_sudot(a64_operands(args, false, false, true, false, "sudot"))
}

macro suqadd(...args) {
    a64_suqadd_shape(a64_operands(args, false, false, false, false, "suqadd"))
    a64_suqadd(a64_operands(args, false, false, true, false, "suqadd"))
}

macro svc(...args) {
    a64_svc_shape(a64_operands(args, false, false, false, false, "svc"))
    a64_svc(a64_operands(args, false, false, true, false, "svc"))
}

macro swp(...args) {
    a64_swp_shape(a64_operands(args, false, false, false, false, "swp"))
    a64_swp(a64_operands(args, false, false, true, false, "swp"))
}

macro swpa(...args) {
    a64_swpa_shape(a64_operands(args, false, false, false, false, "swpa"))
    a64_swpa(a64_operands(args, false, false, true, false, "swpa"))
}

macro swpab(...args) {
    a64_swpab_shape(a64_operands(args, false, false, false, false, "swpab"))
    a64_swpab(a64_operands(args, false, false, true, false, "swpab"))
}

macro swpah(...args) {
    a64_swpah_shape(a64_operands(args, false, false, false, false, "swpah"))
    a64_swpah(a64_operands(args, false, false, true, false, "swpah"))
}

macro swpal(...args) {
    a64_swpal_shape(a64_operands(args, false, false, false, false, "swpal"))
    a64_swpal(a64_operands(args, false, false, true, false, "swpal"))
}

macro swpalb(...args) {
    a64_swpalb_shape(a64_operands(args, false, false, false, false, "swpalb"))
    a64_swpalb(a64_operands(args, false, false, true, false, "swpalb"))
}

macro swpalh(...args) {
    a64_swpalh_shape(a64_operands(args, false, false, false, false, "swpalh"))
    a64_swpalh(a64_operands(args, false, false, true, false, "swpalh"))
}

macro swpb(...args) {
    a64_swpb_shape(a64_operands(args, false, false, false, false, "swpb"))
    a64_swpb(a64_operands(args, false, false, true, false, "swpb"))
}

macro swph(...args) {
    a64_swph_shape(a64_operands(args, false, false, false, false, "swph"))
    a64_swph(a64_operands(args, false, false, true, false, "swph"))
}

macro swpl(...args) {
    a64_swpl_shape(a64_operands(args, false, false, false, false, "swpl"))
    a64_swpl(a64_operands(args, false, false, true, false, "swpl"))
}

macro swplb(...args) {
    a64_swplb_shape(a64_operands(args, false, false, false, false, "swplb"))
    a64_swplb(a64_operands(args, false, false, true, false, "swplb"))
}

macro swplh(...args) {
    a64_swplh_shape(a64_operands(args, false, false, false, false, "swplh"))
    a64_swplh(a64_operands(args, false, false, true, false, "swplh"))
}

macro sxtb(...args) {
    a64_sxtb_shape(a64_operands(args, false, false, false, false, "sxtb"))
    a64_sxtb(a64_operands(args, false, false, true, false, "sxtb"))
}

macro sxth(...args) {
    a64_sxth_shape(a64_operands(args, false, false, false, false, "sxth"))
    a64_sxth(a64_operands(args, false, false, true, false, "sxth"))
}

macro sxtl(...args) {
    a64_sxtl_shape(a64_operands(args, false, false, false, false, "sxtl"))
    a64_sxtl(a64_operands(args, false, false, true, false, "sxtl"))
}

macro sxtl2(...args) {
    a64_sxtl2_shape(a64_operands(args, false, false, false, false, "sxtl2"))
    a64_sxtl2(a64_operands(args, false, false, true, false, "sxtl2"))
}

macro sxtw(...args) {
    a64_sxtw_shape(a64_operands(args, false, false, false, false, "sxtw"))
    a64_sxtw(a64_operands(args, false, false, true, false, "sxtw"))
}

macro sys(...args) {
    a64_sys_shape(a64_operands(args, false, false, false, false, "sys"))
    a64_sys(a64_operands(args, false, false, true, false, "sys"))
}

macro sysl(...args) {
    a64_sysl_shape(a64_operands(args, false, false, false, false, "sysl"))
    a64_sysl(a64_operands(args, false, false, true, false, "sysl"))
}

macro tbl(...args) {
    a64_tbl_shape(a64_operands(args, false, false, false, false, "tbl"))
    a64_tbl(a64_operands(args, false, false, true, false, "tbl"))
}

macro tbnz(...args) {
    a64_tbnz_shape(a64_operands(args, false, false, false, true, "tbnz"))
    a64_tbnz(a64_operands(args, false, false, true, true, "tbnz"))
}

macro tbx(...args) {
    a64_tbx_shape(a64_operands(args, false, false, false, false, "tbx"))
    a64_tbx(a64_operands(args, false, false, true, false, "tbx"))
}

macro tbz(...args) {
    a64_tbz_shape(a64_operands(args, false, false, false, true, "tbz"))
    a64_tbz(a64_operands(args, false, false, true, true, "tbz"))
}

macro tlbi(...args) {
    a64_tlbi_shape(a64_operands(args, false, false, false, false, "tlbi"))
    a64_tlbi(a64_operands(args, false, false, true, false, "tlbi"))
}

macro trn1(...args) {
    a64_trn1_shape(a64_operands(args, false, false, false, false, "trn1"))
    a64_trn1(a64_operands(args, false, false, true, false, "trn1"))
}

macro trn2(...args) {
    a64_trn2_shape(a64_operands(args, false, false, false, false, "trn2"))
    a64_trn2(a64_operands(args, false, false, true, false, "trn2"))
}

macro tst(...args) {
    a64_tst_shape(a64_operands(args, false, false, false, false, "tst"))
    a64_tst(a64_operands(args, false, false, true, false, "tst"))
}

macro uaba(...args) {
    a64_uaba_shape(a64_operands(args, false, false, false, false, "uaba"))
    a64_uaba(a64_operands(args, false, false, true, false, "uaba"))
}

macro uabal(...args) {
    a64_uabal_shape(a64_operands(args, false, false, false, false, "uabal"))
    a64_uabal(a64_operands(args, false, false, true, false, "uabal"))
}

macro uabal2(...args) {
    a64_uabal2_shape(a64_operands(args, false, false, false, false, "uabal2"))
    a64_uabal2(a64_operands(args, false, false, true, false, "uabal2"))
}

macro uabd(...args) {
    a64_uabd_shape(a64_operands(args, false, false, false, false, "uabd"))
    a64_uabd(a64_operands(args, false, false, true, false, "uabd"))
}

macro uabdl(...args) {
    a64_uabdl_shape(a64_operands(args, false, false, false, false, "uabdl"))
    a64_uabdl(a64_operands(args, false, false, true, false, "uabdl"))
}

macro uabdl2(...args) {
    a64_uabdl2_shape(a64_operands(args, false, false, false, false, "uabdl2"))
    a64_uabdl2(a64_operands(args, false, false, true, false, "uabdl2"))
}

macro uadalp(...args) {
    a64_uadalp_shape(a64_operands(args, false, false, false, false, "uadalp"))
    a64_uadalp(a64_operands(args, false, false, true, false, "uadalp"))
}

macro uaddl(...args) {
    a64_uaddl_shape(a64_operands(args, false, false, false, false, "uaddl"))
    a64_uaddl(a64_operands(args, false, false, true, false, "uaddl"))
}

macro uaddl2(...args) {
    a64_uaddl2_shape(a64_operands(args, false, false, false, false, "uaddl2"))
    a64_uaddl2(a64_operands(args, false, false, true, false, "uaddl2"))
}

macro uaddlp(...args) {
    a64_uaddlp_shape(a64_operands(args, false, false, false, false, "uaddlp"))
    a64_uaddlp(a64_operands(args, false, false, true, false, "uaddlp"))
}

macro uaddlv(...args) {
    a64_uaddlv_shape(a64_operands(args, false, false, false, false, "uaddlv"))
    a64_uaddlv(a64_operands(args, false, false, true, false, "uaddlv"))
}

macro uaddw(...args) {
    a64_uaddw_shape(a64_operands(args, false, false, false, false, "uaddw"))
    a64_uaddw(a64_operands(args, false, false, true, false, "uaddw"))
}

macro uaddw2(...args) {
    a64_uaddw2_shape(a64_operands(args, false, false, false, false, "uaddw2"))
    a64_uaddw2(a64_operands(args, false, false, true, false, "uaddw2"))
}

macro ubfiz(...args) {
    a64_ubfiz_shape(a64_operands(args, false, false, false, false, "ubfiz"))
    a64_ubfiz(a64_operands(args, false, false, true, false, "ubfiz"))
}

macro ubfm(...args) {
    a64_ubfm_shape(a64_operands(args, false, false, false, false, "ubfm"))
    a64_ubfm(a64_operands(args, false, false, true, false, "ubfm"))
}

macro ubfx(...args) {
    a64_ubfx_shape(a64_operands(args, false, false, false, false, "ubfx"))
    a64_ubfx(a64_operands(args, false, false, true, false, "ubfx"))
}

macro ucvtf(...args) {
    a64_ucvtf_shape(a64_operands(args, false, false, false, false, "ucvtf"))
    a64_ucvtf(a64_operands(args, false, false, true, false, "ucvtf"))
}

macro udf(...args) {
    a64_udf_shape(a64_operands(args, false, false, false, false, "udf"))
    a64_udf(a64_operands(args, false, false, true, false, "udf"))
}

macro udiv(...args) {
    a64_udiv_shape(a64_operands(args, false, false, false, false, "udiv"))
    a64_udiv(a64_operands(args, false, false, true, false, "udiv"))
}

macro udot(...args) {
    a64_udot_shape(a64_operands(args, false, false, false, false, "udot"))
    a64_udot(a64_operands(args, false, false, true, false, "udot"))
}

macro uhadd(...args) {
    a64_uhadd_shape(a64_operands(args, false, false, false, false, "uhadd"))
    a64_uhadd(a64_operands(args, false, false, true, false, "uhadd"))
}

macro uhsub(...args) {
    a64_uhsub_shape(a64_operands(args, false, false, false, false, "uhsub"))
    a64_uhsub(a64_operands(args, false, false, true, false, "uhsub"))
}

macro umaddl(...args) {
    a64_umaddl_shape(a64_operands(args, false, false, false, false, "umaddl"))
    a64_umaddl(a64_operands(args, false, false, true, false, "umaddl"))
}

macro umax(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "umax")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 134743040 || key == 134743042 || key == 135005696 || key == 135005699 {
        a64_e5_umax_shape(shaped)
        a64_e5_umax(a64_operands(args, false, false, true, false, "umax"))
    } else {
        a64_umax_shape(shaped)
        a64_umax(a64_operands(args, false, false, true, false, "umax"))
    }
}

macro umaxp(...args) {
    a64_umaxp_shape(a64_operands(args, false, false, false, false, "umaxp"))
    a64_umaxp(a64_operands(args, false, false, true, false, "umaxp"))
}

macro umaxv(...args) {
    a64_umaxv_shape(a64_operands(args, false, false, false, false, "umaxv"))
    a64_umaxv(a64_operands(args, false, false, true, false, "umaxv"))
}

macro umin(...args) {
    const shaped: list = a64_operands(args, false, false, false, false, "umin")
    const key: u64 = a64_signature(a64_flatten(shaped))
    if key == 134743040 || key == 134743042 || key == 135005696 || key == 135005699 {
        a64_e5_umin_shape(shaped)
        a64_e5_umin(a64_operands(args, false, false, true, false, "umin"))
    } else {
        a64_umin_shape(shaped)
        a64_umin(a64_operands(args, false, false, true, false, "umin"))
    }
}

macro uminp(...args) {
    a64_uminp_shape(a64_operands(args, false, false, false, false, "uminp"))
    a64_uminp(a64_operands(args, false, false, true, false, "uminp"))
}

macro uminv(...args) {
    a64_uminv_shape(a64_operands(args, false, false, false, false, "uminv"))
    a64_uminv(a64_operands(args, false, false, true, false, "uminv"))
}

macro umlal(...args) {
    a64_umlal_shape(a64_operands(args, false, false, false, false, "umlal"))
    a64_umlal(a64_operands(args, false, false, true, false, "umlal"))
}

macro umlal2(...args) {
    a64_umlal2_shape(a64_operands(args, false, false, false, false, "umlal2"))
    a64_umlal2(a64_operands(args, false, false, true, false, "umlal2"))
}

macro umlsl(...args) {
    a64_umlsl_shape(a64_operands(args, false, false, false, false, "umlsl"))
    a64_umlsl(a64_operands(args, false, false, true, false, "umlsl"))
}

macro umlsl2(...args) {
    a64_umlsl2_shape(a64_operands(args, false, false, false, false, "umlsl2"))
    a64_umlsl2(a64_operands(args, false, false, true, false, "umlsl2"))
}

macro ummla(...args) {
    a64_ummla_shape(a64_operands(args, false, false, false, false, "ummla"))
    a64_ummla(a64_operands(args, false, false, true, false, "ummla"))
}

macro umnegl(...args) {
    a64_umnegl_shape(a64_operands(args, false, false, false, false, "umnegl"))
    a64_umnegl(a64_operands(args, false, false, true, false, "umnegl"))
}

macro umov(...args) {
    a64_umov_shape(a64_operands(args, false, false, false, false, "umov"))
    a64_umov(a64_operands(args, false, false, true, false, "umov"))
}

macro umsubl(...args) {
    a64_umsubl_shape(a64_operands(args, false, false, false, false, "umsubl"))
    a64_umsubl(a64_operands(args, false, false, true, false, "umsubl"))
}

macro umulh(...args) {
    a64_umulh_shape(a64_operands(args, false, false, false, false, "umulh"))
    a64_umulh(a64_operands(args, false, false, true, false, "umulh"))
}

macro umull(...args) {
    a64_umull_shape(a64_operands(args, false, false, false, false, "umull"))
    a64_umull(a64_operands(args, false, false, true, false, "umull"))
}

macro umull2(...args) {
    a64_umull2_shape(a64_operands(args, false, false, false, false, "umull2"))
    a64_umull2(a64_operands(args, false, false, true, false, "umull2"))
}

macro uqadd(...args) {
    a64_uqadd_shape(a64_operands(args, false, false, false, false, "uqadd"))
    a64_uqadd(a64_operands(args, false, false, true, false, "uqadd"))
}

macro uqrshl(...args) {
    a64_uqrshl_shape(a64_operands(args, false, false, false, false, "uqrshl"))
    a64_uqrshl(a64_operands(args, false, false, true, false, "uqrshl"))
}

macro uqrshrn(...args) {
    a64_uqrshrn_shape(a64_operands(args, false, false, false, false, "uqrshrn"))
    a64_uqrshrn(a64_operands(args, false, false, true, false, "uqrshrn"))
}

macro uqrshrn2(...args) {
    a64_uqrshrn2_shape(a64_operands(args, false, false, false, false, "uqrshrn2"))
    a64_uqrshrn2(a64_operands(args, false, false, true, false, "uqrshrn2"))
}

macro uqshl(...args) {
    a64_uqshl_shape(a64_operands(args, false, false, false, false, "uqshl"))
    a64_uqshl(a64_operands(args, false, false, true, false, "uqshl"))
}

macro uqshrn(...args) {
    a64_uqshrn_shape(a64_operands(args, false, false, false, false, "uqshrn"))
    a64_uqshrn(a64_operands(args, false, false, true, false, "uqshrn"))
}

macro uqshrn2(...args) {
    a64_uqshrn2_shape(a64_operands(args, false, false, false, false, "uqshrn2"))
    a64_uqshrn2(a64_operands(args, false, false, true, false, "uqshrn2"))
}

macro uqsub(...args) {
    a64_uqsub_shape(a64_operands(args, false, false, false, false, "uqsub"))
    a64_uqsub(a64_operands(args, false, false, true, false, "uqsub"))
}

macro uqxtn(...args) {
    a64_uqxtn_shape(a64_operands(args, false, false, false, false, "uqxtn"))
    a64_uqxtn(a64_operands(args, false, false, true, false, "uqxtn"))
}

macro uqxtn2(...args) {
    a64_uqxtn2_shape(a64_operands(args, false, false, false, false, "uqxtn2"))
    a64_uqxtn2(a64_operands(args, false, false, true, false, "uqxtn2"))
}

macro urecpe(...args) {
    a64_urecpe_shape(a64_operands(args, false, false, false, false, "urecpe"))
    a64_urecpe(a64_operands(args, false, false, true, false, "urecpe"))
}

macro urhadd(...args) {
    a64_urhadd_shape(a64_operands(args, false, false, false, false, "urhadd"))
    a64_urhadd(a64_operands(args, false, false, true, false, "urhadd"))
}

macro urshl(...args) {
    a64_urshl_shape(a64_operands(args, false, false, false, false, "urshl"))
    a64_urshl(a64_operands(args, false, false, true, false, "urshl"))
}

macro urshr(...args) {
    a64_urshr_shape(a64_operands(args, false, false, false, false, "urshr"))
    a64_urshr(a64_operands(args, false, false, true, false, "urshr"))
}

macro ursqrte(...args) {
    a64_ursqrte_shape(a64_operands(args, false, false, false, false, "ursqrte"))
    a64_ursqrte(a64_operands(args, false, false, true, false, "ursqrte"))
}

macro ursra(...args) {
    a64_ursra_shape(a64_operands(args, false, false, false, false, "ursra"))
    a64_ursra(a64_operands(args, false, false, true, false, "ursra"))
}

macro usdot(...args) {
    a64_usdot_shape(a64_operands(args, false, false, false, false, "usdot"))
    a64_usdot(a64_operands(args, false, false, true, false, "usdot"))
}

macro ushl(...args) {
    a64_ushl_shape(a64_operands(args, false, false, false, false, "ushl"))
    a64_ushl(a64_operands(args, false, false, true, false, "ushl"))
}

macro ushll(...args) {
    a64_ushll_shape(a64_operands(args, false, false, false, false, "ushll"))
    a64_ushll(a64_operands(args, false, false, true, false, "ushll"))
}

macro ushll2(...args) {
    a64_ushll2_shape(a64_operands(args, false, false, false, false, "ushll2"))
    a64_ushll2(a64_operands(args, false, false, true, false, "ushll2"))
}

macro ushr(...args) {
    a64_ushr_shape(a64_operands(args, false, false, false, false, "ushr"))
    a64_ushr(a64_operands(args, false, false, true, false, "ushr"))
}

macro usmmla(...args) {
    a64_usmmla_shape(a64_operands(args, false, false, false, false, "usmmla"))
    a64_usmmla(a64_operands(args, false, false, true, false, "usmmla"))
}

macro usqadd(...args) {
    a64_usqadd_shape(a64_operands(args, false, false, false, false, "usqadd"))
    a64_usqadd(a64_operands(args, false, false, true, false, "usqadd"))
}

macro usra(...args) {
    a64_usra_shape(a64_operands(args, false, false, false, false, "usra"))
    a64_usra(a64_operands(args, false, false, true, false, "usra"))
}

macro usubl(...args) {
    a64_usubl_shape(a64_operands(args, false, false, false, false, "usubl"))
    a64_usubl(a64_operands(args, false, false, true, false, "usubl"))
}

macro usubl2(...args) {
    a64_usubl2_shape(a64_operands(args, false, false, false, false, "usubl2"))
    a64_usubl2(a64_operands(args, false, false, true, false, "usubl2"))
}

macro usubw(...args) {
    a64_usubw_shape(a64_operands(args, false, false, false, false, "usubw"))
    a64_usubw(a64_operands(args, false, false, true, false, "usubw"))
}

macro usubw2(...args) {
    a64_usubw2_shape(a64_operands(args, false, false, false, false, "usubw2"))
    a64_usubw2(a64_operands(args, false, false, true, false, "usubw2"))
}

macro uxtb(...args) {
    a64_uxtb_shape(a64_operands(args, false, false, false, false, "uxtb"))
    a64_uxtb(a64_operands(args, false, false, true, false, "uxtb"))
}

macro uxth(...args) {
    a64_uxth_shape(a64_operands(args, false, false, false, false, "uxth"))
    a64_uxth(a64_operands(args, false, false, true, false, "uxth"))
}

macro uxtl(...args) {
    a64_uxtl_shape(a64_operands(args, false, false, false, false, "uxtl"))
    a64_uxtl(a64_operands(args, false, false, true, false, "uxtl"))
}

macro uxtl2(...args) {
    a64_uxtl2_shape(a64_operands(args, false, false, false, false, "uxtl2"))
    a64_uxtl2(a64_operands(args, false, false, true, false, "uxtl2"))
}

macro uzp1(...args) {
    a64_uzp1_shape(a64_operands(args, false, false, false, false, "uzp1"))
    a64_uzp1(a64_operands(args, false, false, true, false, "uzp1"))
}

macro uzp2(...args) {
    a64_uzp2_shape(a64_operands(args, false, false, false, false, "uzp2"))
    a64_uzp2(a64_operands(args, false, false, true, false, "uzp2"))
}

macro wfe(...args) {
    a64_wfe_shape(a64_operands(args, false, false, false, false, "wfe"))
    a64_wfe(a64_operands(args, false, false, true, false, "wfe"))
}

macro wfi(...args) {
    a64_wfi_shape(a64_operands(args, false, false, false, false, "wfi"))
    a64_wfi(a64_operands(args, false, false, true, false, "wfi"))
}

macro xaflag(...args) {
    a64_xaflag_shape(a64_operands(args, false, false, false, false, "xaflag"))
    a64_xaflag(a64_operands(args, false, false, true, false, "xaflag"))
}

macro xar(...args) {
    a64_xar_shape(a64_operands(args, false, false, false, false, "xar"))
    a64_xar(a64_operands(args, false, false, true, false, "xar"))
}

macro xpacd(...args) {
    a64_xpacd_shape(a64_operands(args, false, false, false, false, "xpacd"))
    a64_xpacd(a64_operands(args, false, false, true, false, "xpacd"))
}

macro xpaci(...args) {
    a64_xpaci_shape(a64_operands(args, false, false, false, false, "xpaci"))
    a64_xpaci(a64_operands(args, false, false, true, false, "xpaci"))
}

macro xpaclri(...args) {
    a64_xpaclri_shape(a64_operands(args, false, false, false, false, "xpaclri"))
    a64_xpaclri(a64_operands(args, false, false, true, false, "xpaclri"))
}

macro xtn(...args) {
    a64_xtn_shape(a64_operands(args, false, false, false, false, "xtn"))
    a64_xtn(a64_operands(args, false, false, true, false, "xtn"))
}

macro xtn2(...args) {
    a64_xtn2_shape(a64_operands(args, false, false, false, false, "xtn2"))
    a64_xtn2(a64_operands(args, false, false, true, false, "xtn2"))
}

macro yield(...args) {
    a64_yield_shape(a64_operands(args, false, false, false, false, "yield"))
    a64_yield(a64_operands(args, false, false, true, false, "yield"))
}

macro zip1(...args) {
    a64_zip1_shape(a64_operands(args, false, false, false, false, "zip1"))
    a64_zip1(a64_operands(args, false, false, true, false, "zip1"))
}

macro zip2(...args) {
    a64_zip2_shape(a64_operands(args, false, false, false, false, "zip2"))
    a64_zip2(a64_operands(args, false, false, true, false, "zip2"))
}
