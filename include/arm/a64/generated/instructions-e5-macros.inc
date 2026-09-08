// Generated statement macros for FEAT_MOPS/FEAT_CSSC.
// Shared macro owners dispatch standard abs/cnt/smax/smin/umax/umin syntax;
// this file retains cssc_ aliases for compatibility. Other E5 mnemonics use
// their standard names.

macro cssc_abs(...args) {
    a64_e5_abs_shape(a64_operands(args, false, false, false, false, "abs"))
    a64_e5_abs(a64_operands(args, false, false, true, false, "abs"))
}

macro cssc_cnt(...args) {
    a64_e5_cnt_shape(a64_operands(args, false, false, false, false, "cnt"))
    a64_e5_cnt(a64_operands(args, false, false, true, false, "cnt"))
}

macro cpye(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpye_shape(parsed)
    a64_e5_cpye(parsed)
}

macro cpyen(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyen_shape(parsed)
    a64_e5_cpyen(parsed)
}

macro cpyern(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyern_shape(parsed)
    a64_e5_cpyern(parsed)
}

macro cpyert(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyert_shape(parsed)
    a64_e5_cpyert(parsed)
}

macro cpyertn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyertn_shape(parsed)
    a64_e5_cpyertn(parsed)
}

macro cpyertrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyertrn_shape(parsed)
    a64_e5_cpyertrn(parsed)
}

macro cpyertwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyertwn_shape(parsed)
    a64_e5_cpyertwn(parsed)
}

macro cpyet(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyet_shape(parsed)
    a64_e5_cpyet(parsed)
}

macro cpyetn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyetn_shape(parsed)
    a64_e5_cpyetn(parsed)
}

macro cpyetrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyetrn_shape(parsed)
    a64_e5_cpyetrn(parsed)
}

macro cpyetwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyetwn_shape(parsed)
    a64_e5_cpyetwn(parsed)
}

macro cpyewn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyewn_shape(parsed)
    a64_e5_cpyewn(parsed)
}

macro cpyewt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyewt_shape(parsed)
    a64_e5_cpyewt(parsed)
}

macro cpyewtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyewtn_shape(parsed)
    a64_e5_cpyewtn(parsed)
}

macro cpyewtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyewtrn_shape(parsed)
    a64_e5_cpyewtrn(parsed)
}

macro cpyewtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyewtwn_shape(parsed)
    a64_e5_cpyewtwn(parsed)
}

macro cpyfe(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfe_shape(parsed)
    a64_e5_cpyfe(parsed)
}

macro cpyfen(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfen_shape(parsed)
    a64_e5_cpyfen(parsed)
}

macro cpyfern(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfern_shape(parsed)
    a64_e5_cpyfern(parsed)
}

macro cpyfert(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfert_shape(parsed)
    a64_e5_cpyfert(parsed)
}

macro cpyfertn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfertn_shape(parsed)
    a64_e5_cpyfertn(parsed)
}

macro cpyfertrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfertrn_shape(parsed)
    a64_e5_cpyfertrn(parsed)
}

macro cpyfertwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfertwn_shape(parsed)
    a64_e5_cpyfertwn(parsed)
}

macro cpyfet(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfet_shape(parsed)
    a64_e5_cpyfet(parsed)
}

macro cpyfetn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfetn_shape(parsed)
    a64_e5_cpyfetn(parsed)
}

macro cpyfetrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfetrn_shape(parsed)
    a64_e5_cpyfetrn(parsed)
}

macro cpyfetwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfetwn_shape(parsed)
    a64_e5_cpyfetwn(parsed)
}

macro cpyfewn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfewn_shape(parsed)
    a64_e5_cpyfewn(parsed)
}

macro cpyfewt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfewt_shape(parsed)
    a64_e5_cpyfewt(parsed)
}

macro cpyfewtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfewtn_shape(parsed)
    a64_e5_cpyfewtn(parsed)
}

macro cpyfewtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfewtrn_shape(parsed)
    a64_e5_cpyfewtrn(parsed)
}

macro cpyfewtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfewtwn_shape(parsed)
    a64_e5_cpyfewtwn(parsed)
}

macro cpyfm(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfm_shape(parsed)
    a64_e5_cpyfm(parsed)
}

macro cpyfmn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmn_shape(parsed)
    a64_e5_cpyfmn(parsed)
}

macro cpyfmrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmrn_shape(parsed)
    a64_e5_cpyfmrn(parsed)
}

macro cpyfmrt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmrt_shape(parsed)
    a64_e5_cpyfmrt(parsed)
}

macro cpyfmrtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmrtn_shape(parsed)
    a64_e5_cpyfmrtn(parsed)
}

macro cpyfmrtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmrtrn_shape(parsed)
    a64_e5_cpyfmrtrn(parsed)
}

macro cpyfmrtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmrtwn_shape(parsed)
    a64_e5_cpyfmrtwn(parsed)
}

macro cpyfmt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmt_shape(parsed)
    a64_e5_cpyfmt(parsed)
}

macro cpyfmtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmtn_shape(parsed)
    a64_e5_cpyfmtn(parsed)
}

macro cpyfmtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmtrn_shape(parsed)
    a64_e5_cpyfmtrn(parsed)
}

macro cpyfmtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmtwn_shape(parsed)
    a64_e5_cpyfmtwn(parsed)
}

macro cpyfmwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmwn_shape(parsed)
    a64_e5_cpyfmwn(parsed)
}

macro cpyfmwt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmwt_shape(parsed)
    a64_e5_cpyfmwt(parsed)
}

macro cpyfmwtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmwtn_shape(parsed)
    a64_e5_cpyfmwtn(parsed)
}

macro cpyfmwtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmwtrn_shape(parsed)
    a64_e5_cpyfmwtrn(parsed)
}

macro cpyfmwtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfmwtwn_shape(parsed)
    a64_e5_cpyfmwtwn(parsed)
}

macro cpyfp(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfp_shape(parsed)
    a64_e5_cpyfp(parsed)
}

macro cpyfpn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpn_shape(parsed)
    a64_e5_cpyfpn(parsed)
}

macro cpyfprn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfprn_shape(parsed)
    a64_e5_cpyfprn(parsed)
}

macro cpyfprt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfprt_shape(parsed)
    a64_e5_cpyfprt(parsed)
}

macro cpyfprtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfprtn_shape(parsed)
    a64_e5_cpyfprtn(parsed)
}

macro cpyfprtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfprtrn_shape(parsed)
    a64_e5_cpyfprtrn(parsed)
}

macro cpyfprtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfprtwn_shape(parsed)
    a64_e5_cpyfprtwn(parsed)
}

macro cpyfpt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpt_shape(parsed)
    a64_e5_cpyfpt(parsed)
}

macro cpyfptn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfptn_shape(parsed)
    a64_e5_cpyfptn(parsed)
}

macro cpyfptrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfptrn_shape(parsed)
    a64_e5_cpyfptrn(parsed)
}

macro cpyfptwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfptwn_shape(parsed)
    a64_e5_cpyfptwn(parsed)
}

macro cpyfpwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpwn_shape(parsed)
    a64_e5_cpyfpwn(parsed)
}

macro cpyfpwt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpwt_shape(parsed)
    a64_e5_cpyfpwt(parsed)
}

macro cpyfpwtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpwtn_shape(parsed)
    a64_e5_cpyfpwtn(parsed)
}

macro cpyfpwtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpwtrn_shape(parsed)
    a64_e5_cpyfpwtrn(parsed)
}

macro cpyfpwtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyfpwtwn_shape(parsed)
    a64_e5_cpyfpwtwn(parsed)
}

macro cpym(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpym_shape(parsed)
    a64_e5_cpym(parsed)
}

macro cpymn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymn_shape(parsed)
    a64_e5_cpymn(parsed)
}

macro cpymrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymrn_shape(parsed)
    a64_e5_cpymrn(parsed)
}

macro cpymrt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymrt_shape(parsed)
    a64_e5_cpymrt(parsed)
}

macro cpymrtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymrtn_shape(parsed)
    a64_e5_cpymrtn(parsed)
}

macro cpymrtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymrtrn_shape(parsed)
    a64_e5_cpymrtrn(parsed)
}

macro cpymrtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymrtwn_shape(parsed)
    a64_e5_cpymrtwn(parsed)
}

macro cpymt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymt_shape(parsed)
    a64_e5_cpymt(parsed)
}

macro cpymtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymtn_shape(parsed)
    a64_e5_cpymtn(parsed)
}

macro cpymtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymtrn_shape(parsed)
    a64_e5_cpymtrn(parsed)
}

macro cpymtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymtwn_shape(parsed)
    a64_e5_cpymtwn(parsed)
}

macro cpymwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymwn_shape(parsed)
    a64_e5_cpymwn(parsed)
}

macro cpymwt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymwt_shape(parsed)
    a64_e5_cpymwt(parsed)
}

macro cpymwtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymwtn_shape(parsed)
    a64_e5_cpymwtn(parsed)
}

macro cpymwtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymwtrn_shape(parsed)
    a64_e5_cpymwtrn(parsed)
}

macro cpymwtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpymwtwn_shape(parsed)
    a64_e5_cpymwtwn(parsed)
}

macro cpyp(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyp_shape(parsed)
    a64_e5_cpyp(parsed)
}

macro cpypn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypn_shape(parsed)
    a64_e5_cpypn(parsed)
}

macro cpyprn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyprn_shape(parsed)
    a64_e5_cpyprn(parsed)
}

macro cpyprt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyprt_shape(parsed)
    a64_e5_cpyprt(parsed)
}

macro cpyprtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyprtn_shape(parsed)
    a64_e5_cpyprtn(parsed)
}

macro cpyprtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyprtrn_shape(parsed)
    a64_e5_cpyprtrn(parsed)
}

macro cpyprtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyprtwn_shape(parsed)
    a64_e5_cpyprtwn(parsed)
}

macro cpypt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypt_shape(parsed)
    a64_e5_cpypt(parsed)
}

macro cpyptn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyptn_shape(parsed)
    a64_e5_cpyptn(parsed)
}

macro cpyptrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyptrn_shape(parsed)
    a64_e5_cpyptrn(parsed)
}

macro cpyptwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpyptwn_shape(parsed)
    a64_e5_cpyptwn(parsed)
}

macro cpypwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypwn_shape(parsed)
    a64_e5_cpypwn(parsed)
}

macro cpypwt(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypwt_shape(parsed)
    a64_e5_cpypwt(parsed)
}

macro cpypwtn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypwtn_shape(parsed)
    a64_e5_cpypwtn(parsed)
}

macro cpypwtrn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypwtrn_shape(parsed)
    a64_e5_cpypwtrn(parsed)
}

macro cpypwtwn(...args) {
    const parsed: list = a64_mops_operands(args, "cpy")
    a64_e5_cpypwtwn_shape(parsed)
    a64_e5_cpypwtwn(parsed)
}

macro ctz(...args) {
    a64_e5_ctz_shape(a64_operands(args, false, false, false, false, "ctz"))
    a64_e5_ctz(a64_operands(args, false, false, true, false, "ctz"))
}

macro sete(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_sete_shape(parsed)
    a64_e5_sete(parsed)
}

macro seten(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_seten_shape(parsed)
    a64_e5_seten(parsed)
}

macro setet(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setet_shape(parsed)
    a64_e5_setet(parsed)
}

macro setetn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setetn_shape(parsed)
    a64_e5_setetn(parsed)
}

macro setge(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setge_shape(parsed)
    a64_e5_setge(parsed)
}

macro setgen(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgen_shape(parsed)
    a64_e5_setgen(parsed)
}

macro setget(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setget_shape(parsed)
    a64_e5_setget(parsed)
}

macro setgetn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgetn_shape(parsed)
    a64_e5_setgetn(parsed)
}

macro setgm(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgm_shape(parsed)
    a64_e5_setgm(parsed)
}

macro setgmn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgmn_shape(parsed)
    a64_e5_setgmn(parsed)
}

macro setgmt(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgmt_shape(parsed)
    a64_e5_setgmt(parsed)
}

macro setgmtn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgmtn_shape(parsed)
    a64_e5_setgmtn(parsed)
}

macro setgoe(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgoe_shape(parsed)
    a64_e5_setgoe(parsed)
}

macro setgoen(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgoen_shape(parsed)
    a64_e5_setgoen(parsed)
}

macro setgoet(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgoet_shape(parsed)
    a64_e5_setgoet(parsed)
}

macro setgoetn(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgoetn_shape(parsed)
    a64_e5_setgoetn(parsed)
}

macro setgom(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgom_shape(parsed)
    a64_e5_setgom(parsed)
}

macro setgomn(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgomn_shape(parsed)
    a64_e5_setgomn(parsed)
}

macro setgomt(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgomt_shape(parsed)
    a64_e5_setgomt(parsed)
}

macro setgomtn(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgomtn_shape(parsed)
    a64_e5_setgomtn(parsed)
}

macro setgop(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgop_shape(parsed)
    a64_e5_setgop(parsed)
}

macro setgopn(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgopn_shape(parsed)
    a64_e5_setgopn(parsed)
}

macro setgopt(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgopt_shape(parsed)
    a64_e5_setgopt(parsed)
}

macro setgoptn(...args) {
    const parsed: list = a64_mops_operands(args, "setgo")
    a64_e5_setgoptn_shape(parsed)
    a64_e5_setgoptn(parsed)
}

macro setgp(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgp_shape(parsed)
    a64_e5_setgp(parsed)
}

macro setgpn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgpn_shape(parsed)
    a64_e5_setgpn(parsed)
}

macro setgpt(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgpt_shape(parsed)
    a64_e5_setgpt(parsed)
}

macro setgptn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setgptn_shape(parsed)
    a64_e5_setgptn(parsed)
}

macro setm(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setm_shape(parsed)
    a64_e5_setm(parsed)
}

macro setmn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setmn_shape(parsed)
    a64_e5_setmn(parsed)
}

macro setmt(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setmt_shape(parsed)
    a64_e5_setmt(parsed)
}

macro setmtn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setmtn_shape(parsed)
    a64_e5_setmtn(parsed)
}

macro setp(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setp_shape(parsed)
    a64_e5_setp(parsed)
}

macro setpn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setpn_shape(parsed)
    a64_e5_setpn(parsed)
}

macro setpt(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setpt_shape(parsed)
    a64_e5_setpt(parsed)
}

macro setptn(...args) {
    const parsed: list = a64_mops_operands(args, "set")
    a64_e5_setptn_shape(parsed)
    a64_e5_setptn(parsed)
}

macro cssc_smax(...args) {
    a64_e5_smax_shape(a64_operands(args, false, false, false, false, "smax"))
    a64_e5_smax(a64_operands(args, false, false, true, false, "smax"))
}

macro cssc_smin(...args) {
    a64_e5_smin_shape(a64_operands(args, false, false, false, false, "smin"))
    a64_e5_smin(a64_operands(args, false, false, true, false, "smin"))
}

macro cssc_umax(...args) {
    a64_e5_umax_shape(a64_operands(args, false, false, false, false, "umax"))
    a64_e5_umax(a64_operands(args, false, false, true, false, "umax"))
}

macro cssc_umin(...args) {
    a64_e5_umin_shape(a64_operands(args, false, false, false, false, "umin"))
    a64_e5_umin(a64_operands(args, false, false, true, false, "umin"))
}
