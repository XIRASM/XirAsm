// arm64_asm: text adapter over the emitter procedures.
//
// This is string parsing via match.tokens, not a frontend macro — the
// instruction is a quoted string. Grammar notes:
//   - immediates are written WITHOUT the '#' prefix (Meta has no
//     string-to-integer parse, so '#42' cannot be captured as a number);
//   - numeric operands flow through match.tokens int captures;
//   - register names are resolved through arm64_reg_table (arm64/regs.inc);
//   - B.cond is spelled "b.eq"/"b.lt"/... (three tokens: b, ., cond).
//
//   arm64_asm("nop")
//   arm64_asm("ret")
//   arm64_asm("movz x0, 42")
//   arm64_asm("movz x0, 42, lsl 16")
//   arm64_asm("mov x1, x2")
//   arm64_asm("add x0, x1, 42")
//   arm64_asm("add x0, x1, 42, lsl 12")
//   arm64_asm("add x0, x1, x2, lsl 3")
//   arm64_asm("add x0, x1, w2, uxtb 2")
//   arm64_asm("orr x0, x1, 0xff00")
//   arm64_asm("cbz x5, done")
//   arm64_asm("tbz x5, 45, done")
//   arm64_asm("b.eq done")
//   arm64_asm("b done")
//   arm64_asm("bl init")
//   arm64_asm("br x16")
//   arm64_asm("blr x30")
//   arm64_asm("adc x0, x1, x2")
//   arm64_asm("ngc x0, x1")
//   arm64_asm("cset x0, eq")
//   arm64_asm("csetm x0, ne")
//   arm64_asm("cinc x0, x1, gt")
//   arm64_asm("csel x0, x1, x2, le")
//   arm64_asm("ccmp x0, 12, 3, ne")
//   arm64_asm("ccmp x0, x1, 3, ne")
//   arm64_asm("tst x0, x1")

let arm64_cond_table: map = map.new()
map.set_mut(arm64_cond_table, "eq", arm64_cond_eq);
map.set_mut(arm64_cond_table, "ne", arm64_cond_ne);
map.set_mut(arm64_cond_table, "cs", arm64_cond_cs);
map.set_mut(arm64_cond_table, "hs", arm64_cond_hs);
map.set_mut(arm64_cond_table, "cc", arm64_cond_cc);
map.set_mut(arm64_cond_table, "lo", arm64_cond_lo);
map.set_mut(arm64_cond_table, "mi", arm64_cond_mi);
map.set_mut(arm64_cond_table, "pl", arm64_cond_pl);
map.set_mut(arm64_cond_table, "vs", arm64_cond_vs);
map.set_mut(arm64_cond_table, "vc", arm64_cond_vc);
map.set_mut(arm64_cond_table, "hi", arm64_cond_hi);
map.set_mut(arm64_cond_table, "ls", arm64_cond_ls);
map.set_mut(arm64_cond_table, "ge", arm64_cond_ge);
map.set_mut(arm64_cond_table, "lt", arm64_cond_lt);
map.set_mut(arm64_cond_table, "gt", arm64_cond_gt);
map.set_mut(arm64_cond_table, "le", arm64_cond_le);

let arm64_shift_table: map = map.new()
map.set_mut(arm64_shift_table, "lsl", 0);
map.set_mut(arm64_shift_table, "lsr", 1);
map.set_mut(arm64_shift_table, "asr", 2);
map.set_mut(arm64_shift_table, "ror", 3);

let arm64_ext_table: map = map.new()
map.set_mut(arm64_ext_table, "uxtb", arm64_uxtb);
map.set_mut(arm64_ext_table, "uxth", arm64_uxth);
map.set_mut(arm64_ext_table, "uxtw", arm64_uxtw);
map.set_mut(arm64_ext_table, "uxtx", arm64_uxtx);
map.set_mut(arm64_ext_table, "sxtb", arm64_sxtb);
map.set_mut(arm64_ext_table, "sxth", arm64_sxth);
map.set_mut(arm64_ext_table, "sxtw", arm64_sxtw);
map.set_mut(arm64_ext_table, "sxtx", arm64_sxtx);

fn arm64_parse_cond(name: string) -> u64 {
    assert(map.has(arm64_cond_table, name), sym.join("arm64_asm: unknown condition ", name));
    return map.get(arm64_cond_table, name);
}

// Per-family dispatch procedures take the captures map and pass values
// directly into the emitters.

fn arm64_asm_move_wide_lsl(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    if mn == "movz" {
        arm64_movz(rd, map.get(caps, "imm"), map.get(caps, "shift"));
    } else if mn == "movk" {
        arm64_movk(rd, map.get(caps, "imm"), map.get(caps, "shift"));
    } else if mn == "movn" {
        arm64_movn(rd, map.get(caps, "imm"), map.get(caps, "shift"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, imm, lsl) form", mn);
    }
}

fn arm64_asm_move_wide(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    if mn == "mov" {
        arm64_mov_imm(rd, map.get(caps, "imm"));
    } else if mn == "movz" {
        arm64_movz(rd, map.get(caps, "imm"), 0);
    } else if mn == "movk" {
        arm64_movk(rd, map.get(caps, "imm"), 0);
    } else if mn == "movn" {
        arm64_movn(rd, map.get(caps, "imm"), 0);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, imm) form", mn);
    }
}

fn arm64_asm_reg_target(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    if mn == "cbz" {
        arm64_cbz(rd, map.get(caps, "target"));
    } else if mn == "cbnz" {
        arm64_cbnz(rd, map.get(caps, "target"));
    } else if mn == "mov" {
        arm64_mov_reg(rd, arm64_parse_reg(map.get(caps, "target")));
    } else if mn == "ngc" {
        arm64_ngc(rd, arm64_parse_reg(map.get(caps, "target")));
    } else if mn == "ngcs" {
        arm64_ngcs(rd, arm64_parse_reg(map.get(caps, "target")));
    } else if mn == "cset" {
        arm64_cset(rd, arm64_parse_cond(map.get(caps, "target")));
    } else if mn == "csetm" {
        arm64_csetm(rd, arm64_parse_cond(map.get(caps, "target")));
    } else if mn == "tst" {
        arm64_tst_reg(rd, arm64_parse_reg(map.get(caps, "target")), 0, 0);
    } else if mn == "adr" {
        arm64_adr(rd, map.get(caps, "target"));
    } else if mn == "adrp" {
        arm64_adrp(rd, map.get(caps, "target"));
    } else if mn == "ldr" {
        // Literal loads are width-specific: opc=01 needs an X target, the W
        // form (opc=00) is a separate API.
        if arm64_reg_is64(rd) {
            arm64_ldr_lit(rd, map.get(caps, "target"));
        } else {
            arm64_ldrw_lit(rd, map.get(caps, "target"));
        }
    } else if mn == "ldrsw" {
        arm64_ldrsw_lit(rd, map.get(caps, "target"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, name) form", mn);
    }
}

fn arm64_asm_test_bit(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    if mn == "tbz" {
        arm64_tbz(rd, map.get(caps, "bit"), map.get(caps, "target"));
    } else if mn == "tbnz" {
        arm64_tbnz(rd, map.get(caps, "bit"), map.get(caps, "target"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, bit, name) form", mn);
    }
}

fn arm64_asm_3op_imm(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "add" {
        arm64_add_imm(rd, rn, map.get(caps, "imm"), 0);
    } else if mn == "adds" {
        arm64_adds_imm(rd, rn, map.get(caps, "imm"), 0);
    } else if mn == "sub" {
        arm64_sub_imm(rd, rn, map.get(caps, "imm"), 0);
    } else if mn == "subs" {
        arm64_subs_imm(rd, rn, map.get(caps, "imm"), 0);
    } else if mn == "and" {
        arm64_and_imm(rd, rn, map.get(caps, "imm"));
    } else if mn == "orr" {
        arm64_orr_imm(rd, rn, map.get(caps, "imm"));
    } else if mn == "eor" {
        arm64_eor_imm(rd, rn, map.get(caps, "imm"));
    } else if mn == "ands" {
        arm64_ands_imm(rd, rn, map.get(caps, "imm"));
    } else if mn == "bic" {
        arm64_bic_imm(rd, rn, map.get(caps, "imm"));
    } else if mn == "lsl" {
        arm64_lsl(rd, rn, map.get(caps, "imm"));
    } else if mn == "lsr" {
        arm64_lsr(rd, rn, map.get(caps, "imm"));
    } else if mn == "asr" {
        arm64_asr(rd, rn, map.get(caps, "imm"));
    } else if mn == "ror" {
        arm64_ror(rd, rn, map.get(caps, "imm"));
    } else if mn == "tst" {
        arm64_tst_imm(rn, map.get(caps, "imm"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, imm) form", mn);
    }
}

fn arm64_asm_addsub_imm_lsl(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "add" {
        arm64_add_imm(rd, rn, map.get(caps, "imm"), map.get(caps, "shift"));
    } else if mn == "adds" {
        arm64_adds_imm(rd, rn, map.get(caps, "imm"), map.get(caps, "shift"));
    } else if mn == "sub" {
        arm64_sub_imm(rd, rn, map.get(caps, "imm"), map.get(caps, "shift"));
    } else if mn == "subs" {
        arm64_subs_imm(rd, rn, map.get(caps, "imm"), map.get(caps, "shift"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, imm, lsl) form", mn);
    }
}

fn arm64_asm_3op_reg(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    // The third operand is a register for the arithmetic/logical families and
    // a condition code for CINC/CINV/CNEG, so it is dispatched by mnemonic.
    if mn == "cinc" {
        arm64_cinc(rd, rn, arm64_parse_cond(map.get(caps, "rm")));
    } else if mn == "cinv" {
        arm64_cinv(rd, rn, arm64_parse_cond(map.get(caps, "rm")));
    } else if mn == "cneg" {
        arm64_cneg(rd, rn, arm64_parse_cond(map.get(caps, "rm")));
    } else {
        const rm: u64 = arm64_parse_reg(map.get(caps, "rm"))
        if mn == "add" {
            arm64_add_reg(rd, rn, rm, 0, 0);
        } else if mn == "adds" {
            arm64_adds_reg(rd, rn, rm, 0, 0);
        } else if mn == "sub" {
            arm64_sub_reg(rd, rn, rm, 0, 0);
        } else if mn == "subs" {
            arm64_subs_reg(rd, rn, rm, 0, 0);
        } else if mn == "adc" {
            arm64_adc(rd, rn, rm);
        } else if mn == "adcs" {
            arm64_adcs(rd, rn, rm);
        } else if mn == "sbc" {
            arm64_sbc(rd, rn, rm);
        } else if mn == "sbcs" {
            arm64_sbcs(rd, rn, rm);
        } else if mn == "and" {
            arm64_and_reg(rd, rn, rm, 0, 0);
        } else if mn == "bic" {
            arm64_bic_reg(rd, rn, rm, 0, 0);
        } else if mn == "orr" {
            arm64_orr_reg(rd, rn, rm, 0, 0);
        } else if mn == "orn" {
            arm64_orn_reg(rd, rn, rm, 0, 0);
        } else if mn == "eor" {
            arm64_eor_reg(rd, rn, rm, 0, 0);
        } else if mn == "eon" {
            arm64_eon_reg(rd, rn, rm, 0, 0);
        } else if mn == "ands" {
            arm64_ands_reg(rd, rn, rm, 0, 0);
        } else if mn == "bics" {
            arm64_bics_reg(rd, rn, rm, 0, 0);
        } else {
            err("arm64_asm: unknown mnemonic for (reg, reg, reg) form", mn);
        }
    }
}

fn arm64_asm_4op_option(caps: map) {
    const mn: string = map.get(caps, "mn")
    const optw: string = map.get(caps, "optw")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    const rm: u64 = arm64_parse_reg(map.get(caps, "rm"))
    if map.has(arm64_shift_table, optw) {
        const shift: u64 = map.get(arm64_shift_table, optw)
        if mn == "add" {
            arm64_add_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "adds" {
            arm64_adds_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "sub" {
            arm64_sub_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "subs" {
            arm64_subs_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "and" {
            arm64_and_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "bic" {
            arm64_bic_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "orr" {
            arm64_orr_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "orn" {
            arm64_orn_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "eor" {
            arm64_eor_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "eon" {
            arm64_eon_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "ands" {
            arm64_ands_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else if mn == "bics" {
            arm64_bics_reg(rd, rn, rm, shift, map.get(caps, "amount"));
        } else {
            err("arm64_asm: unknown mnemonic for (reg, reg, reg, shift, amount) form", mn);
        }
    } else if map.has(arm64_ext_table, optw) {
        assert(mn == "add" || mn == "adds" || mn == "sub" || mn == "subs",
            sym.join("arm64_asm: ", mn, " does not take an extend option"));
        const option: u64 = map.get(arm64_ext_table, optw)
        if mn == "add" {
            arm64_add_ext(rd, rn, rm, option, map.get(caps, "amount"));
        } else if mn == "adds" {
            arm64_adds_ext(rd, rn, rm, option, map.get(caps, "amount"));
        } else if mn == "sub" {
            arm64_sub_ext(rd, rn, rm, option, map.get(caps, "amount"));
        } else {
            arm64_subs_ext(rd, rn, rm, option, map.get(caps, "amount"));
        }
    } else {
        err("arm64_asm: unknown shift or extend option", optw);
    }
}

fn arm64_asm_csel(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    const rm: u64 = arm64_parse_reg(map.get(caps, "rm"))
    const cond: u64 = arm64_parse_cond(map.get(caps, "optw"))
    if mn == "csel" {
        arm64_csel(rd, rn, rm, cond);
    } else if mn == "csinc" {
        arm64_csinc(rd, rn, rm, cond);
    } else if mn == "csinv" {
        arm64_csinv(rd, rn, rm, cond);
    } else if mn == "csneg" {
        arm64_csneg(rd, rn, rm, cond);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, reg, cond) form", mn);
    }
}

fn arm64_asm_ccmp_imm(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    const cond: u64 = arm64_parse_cond(map.get(caps, "cond"))
    if mn == "ccmp" {
        arm64_ccmp_imm(rn, map.get(caps, "imm"), map.get(caps, "nzcv"), cond);
    } else if mn == "ccmn" {
        arm64_ccmn_imm(rn, map.get(caps, "imm"), map.get(caps, "nzcv"), cond);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, imm, nzcv, cond) form", mn);
    }
}

fn arm64_asm_ccmp_reg(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    const cond: u64 = arm64_parse_cond(map.get(caps, "cond"))
    if mn == "ccmp" {
        arm64_ccmp_reg(rn, arm64_parse_reg(map.get(caps, "rm")), map.get(caps, "nzcv"), cond);
    } else if mn == "ccmn" {
        arm64_ccmn_reg(rn, arm64_parse_reg(map.get(caps, "rm")), map.get(caps, "nzcv"), cond);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, nzcv, cond) form", mn);
    }
}

fn arm64_asm_ext_default(caps: map) {
    const mn: string = map.get(caps, "mn")
    const optw: string = map.get(caps, "optw")
    // The bare trailing word is either a condition code (CSEL family) or an
    // extend option (ADD/SUB extended with the default shift 0).
    if map.has(arm64_cond_table, optw) {
        arm64_asm_csel(caps);
    } else {
        const rd: u64 = arm64_parse_reg(map.get(caps, "rd"))
        const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
        const rm: u64 = arm64_parse_reg(map.get(caps, "rm"))
        assert(map.has(arm64_ext_table, optw),
            sym.join("arm64_asm: ", optw, " is not a condition or extend option"));
        assert(mn == "add" || mn == "adds" || mn == "sub" || mn == "subs",
            sym.join("arm64_asm: ", mn, " does not take an extend option"));
        const option: u64 = map.get(arm64_ext_table, optw)
        if mn == "add" {
            arm64_add_ext(rd, rn, rm, option, 0);
        } else if mn == "adds" {
            arm64_adds_ext(rd, rn, rm, option, 0);
        } else if mn == "sub" {
            arm64_sub_ext(rd, rn, rm, option, 0);
        } else {
            arm64_subs_ext(rd, rn, rm, option, 0);
        }
    }
}

fn arm64_asm_mem0(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldr" {
        arm64_ldr_imm(rt, rn, 0);
    } else if mn == "str" {
        arm64_str_imm(rt, rn, 0);
    } else if mn == "ldrb" {
        arm64_ldrb_imm(rt, rn, 0);
    } else if mn == "strb" {
        arm64_strb_imm(rt, rn, 0);
    } else if mn == "ldrh" {
        arm64_ldrh_imm(rt, rn, 0);
    } else if mn == "strh" {
        arm64_strh_imm(rt, rn, 0);
    } else if mn == "ldrsw" {
        arm64_ldrsw_imm(rt, rn, 0);
    } else if mn == "ldrsb" {
        arm64_ldrsb_imm(rt, rn, 0);
    } else if mn == "ldrsh" {
        arm64_ldrsh_imm(rt, rn, 0);
    } else if mn == "ldur" {
        arm64_ldur_imm(rt, rn, 0);
    } else if mn == "stur" {
        arm64_stur_imm(rt, rn, 0);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, [reg]) form", mn);
    }
}

fn arm64_asm_mem_off(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldr" {
        arm64_ldr_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "str" {
        arm64_str_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrb" {
        arm64_ldrb_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "strb" {
        arm64_strb_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrh" {
        arm64_ldrh_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "strh" {
        arm64_strh_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsw" {
        arm64_ldrsw_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsb" {
        arm64_ldrsb_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsh" {
        arm64_ldrsh_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldur" {
        arm64_ldur_imm(rt, rn, map.get(caps, "imm"));
    } else if mn == "stur" {
        arm64_stur_imm(rt, rn, map.get(caps, "imm"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, [reg, imm]) form", mn);
    }
}

fn arm64_asm_pair0(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rt2: u64 = arm64_parse_reg(map.get(caps, "rt2"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldp" {
        arm64_ldp(rt, rt2, rn, 0);
    } else if mn == "stp" {
        arm64_stp(rt, rt2, rn, 0);
    } else if mn == "ldpsw" {
        arm64_ldpsw(rt, rt2, rn, 0);
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, [reg]) pair form", mn);
    }
}

fn arm64_asm_pair_off(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rt2: u64 = arm64_parse_reg(map.get(caps, "rt2"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldp" {
        arm64_ldp(rt, rt2, rn, map.get(caps, "imm"));
    } else if mn == "stp" {
        arm64_stp(rt, rt2, rn, map.get(caps, "imm"));
    } else if mn == "ldpsw" {
        arm64_ldpsw(rt, rt2, rn, map.get(caps, "imm"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, reg, [reg, imm]) pair form", mn);
    }
}

fn arm64_asm_mem_reg0(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    const rm: u64 = arm64_parse_reg(map.get(caps, "rm"))
    if mn == "ldr" {
        arm64_ldr_reg(rt, rn, rm, false);
    } else if mn == "str" {
        arm64_str_reg(rt, rn, rm, false);
    } else if mn == "ldrb" {
        arm64_ldrb_reg(rt, rn, rm, false);
    } else if mn == "strb" {
        arm64_strb_reg(rt, rn, rm, false);
    } else if mn == "ldrh" {
        arm64_ldrh_reg(rt, rn, rm, false);
    } else if mn == "strh" {
        arm64_strh_reg(rt, rn, rm, false);
    } else if mn == "ldrsw" || mn == "ldrsb" || mn == "ldrsh" {
        // LLVM rule for bare register offsets on sign-extending loads: a bare
        // X index is LSL #0; a bare W index is rejected (the extension must be
        // spelled out, e.g. [x1, w2, sxtw]).
        let option: u64 = 0
        if arm64_reg_is64(rm) {
            option = arm64_ldst_opt_lsl
        } else {
            err(sym.join("arm64_asm: ", mn, ": bare W index needs an explicit uxtw/sxtw option"));
        }
        if mn == "ldrsw" {
            arm64_ldrsw_reg(rt, rn, rm, option, false);
        } else if mn == "ldrsb" {
            arm64_ldrsb_reg(rt, rn, rm, option, false);
        } else {
            arm64_ldrsh_reg(rt, rn, rm, option, false);
        }
    } else {
        err("arm64_asm: unknown mnemonic for (reg, [reg, reg]) form", mn);
    }
}

fn arm64_asm_post(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldr" {
        arm64_ldr_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "str" {
        arm64_str_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrb" {
        arm64_ldrb_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "strb" {
        arm64_strb_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrh" {
        arm64_ldrh_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "strh" {
        arm64_strh_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsw" {
        arm64_ldrsw_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsb" {
        arm64_ldrsb_post(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsh" {
        arm64_ldrsh_post(rt, rn, map.get(caps, "imm"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, [reg], imm) post form", mn);
    }
}

fn arm64_asm_pre(caps: map) {
    const mn: string = map.get(caps, "mn")
    const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
    const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
    if mn == "ldr" {
        arm64_ldr_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "str" {
        arm64_str_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrb" {
        arm64_ldrb_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "strb" {
        arm64_strb_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrh" {
        arm64_ldrh_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "strh" {
        arm64_strh_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsw" {
        arm64_ldrsw_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsb" {
        arm64_ldrsb_pre(rt, rn, map.get(caps, "imm"));
    } else if mn == "ldrsh" {
        arm64_ldrsh_pre(rt, rn, map.get(caps, "imm"));
    } else {
        err("arm64_asm: unknown mnemonic for (reg, [reg, imm]!) pre form", mn);
    }
}

fn arm64_asm(text: string) {
    // First-match-wins dispatch: patterns are tried in priority order and the
    // done flag stops the remaining attempts once one matches. The flag is
    // load-bearing — shapes overlap (e.g. "cinc x0, x1, eq" also matches the
    // (reg, reg, reg) pattern), and Meta procedures have no early return, so
    // the guarded sequence is the language-level equivalent of a switch.
    let done: u64 = 0

    const p_nop: map = match.tokens("=nop", text)
    if map.get(p_nop, "ok") {
        arm64_nop();
        done = 1
    }

    if done == 0 {
        const p: map = match.tokens("=ret", text)
        if map.get(p, "ok") {
            arm64_ret();
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("=b =. cond:name target:name", text)
        if map.get(p, "ok") {
            arm64_b_cond(arm64_parse_cond(map.get(map.get(p, "captures"), "cond")),
                map.get(map.get(p, "captures"), "target"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("=b target:name", text)
        if map.get(p, "ok") {
            arm64_b(map.get(map.get(p, "captures"), "target"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("=bl target:name", text)
        if map.get(p, "ok") {
            arm64_bl(map.get(map.get(p, "captures"), "target"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("=br rd:name", text)
        if map.get(p, "ok") {
            arm64_br(arm64_parse_reg(map.get(map.get(p, "captures"), "rd")));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("=blr rd:name", text)
        if map.get(p, "ok") {
            arm64_blr(arm64_parse_reg(map.get(map.get(p, "captures"), "rd")));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, imm:int =, =lsl shift:int", text)
        if map.get(p, "ok") {
            arm64_asm_move_wide_lsl(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, imm:int", text)
        if map.get(p, "ok") {
            arm64_asm_move_wide(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, target:name", text)
        if map.get(p, "ok") {
            arm64_asm_reg_target(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, bit:int =, target:name", text)
        if map.get(p, "ok") {
            arm64_asm_test_bit(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, rn:name =, imm:int", text)
        if map.get(p, "ok") {
            arm64_asm_3op_imm(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, rn:name =, imm:int =, =lsl shift:int", text)
        if map.get(p, "ok") {
            arm64_asm_addsub_imm_lsl(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, rn:name =, rm:name", text)
        if map.get(p, "ok") {
            arm64_asm_3op_reg(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, rn:name =, rm:name =, optw:name amount:int", text)
        if map.get(p, "ok") {
            arm64_asm_4op_option(map.get(p, "captures"));
            done = 1
        }
    }

    // The bare trailing word is a condition code (CSEL family) or an extend
    // option (ADD/SUB extended with the default shift 0).
    if done == 0 {
        const p: map = match.tokens("mn:name rd:name =, rn:name =, rm:name =, optw:name", text)
        if map.get(p, "ok") {
            arm64_asm_ext_default(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rn:name =, imm:int =, nzcv:int =, cond:name", text)
        if map.get(p, "ok") {
            arm64_asm_ccmp_imm(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rn:name =, rm:name =, nzcv:int =, cond:name", text)
        if map.get(p, "ok") {
            arm64_asm_ccmp_reg(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =]", text)
        if map.get(p, "ok") {
            arm64_asm_mem0(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =, imm:int =]", text)
        if map.get(p, "ok") {
            arm64_asm_mem_off(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, rt2:name =, =[ rn:name =]", text)
        if map.get(p, "ok") {
            arm64_asm_pair0(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, rt2:name =, =[ rn:name =, imm:int =]", text)
        if map.get(p, "ok") {
            arm64_asm_pair_off(map.get(p, "captures"));
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =, rm:name =]", text)
        if map.get(p, "ok") {
            arm64_asm_mem_reg0(map.get(p, "captures"));
            done = 1
        }
    }

    // Post-index: [base], #imm.
    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =] =, imm:int", text)
        if map.get(p, "ok") {
            arm64_asm_post(map.get(p, "captures"));
            done = 1
        }
    }

    // Pre-index with writeback marker: [base, #imm]!
    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =, imm:int =] =!", text)
        if map.get(p, "ok") {
            arm64_asm_pre(map.get(p, "captures"));
            done = 1
        }
    }

    // Negative-offset variants: the literal '-' is matched explicitly and the
    // captured magnitude is negated at dispatch (unary minus yields the
    // two's-complement u64 the emitters expect).
    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =, =- imm:int =]", text)
        if map.get(p, "ok") {
            const caps: map = map.get(p, "captures")
            const mn: string = map.get(caps, "mn")
            const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
            const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
            const neg: u64 = -map.get(caps, "imm")
            if mn == "ldur" {
                arm64_ldur_imm(rt, rn, neg);
            } else if mn == "stur" {
                arm64_stur_imm(rt, rn, neg);
            } else {
                err("arm64_asm: unknown mnemonic for (reg, [reg, -imm]) form", mn);
            }
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =] =, =- imm:int", text)
        if map.get(p, "ok") {
            const caps: map = map.get(p, "captures")
            const mn: string = map.get(caps, "mn")
            const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
            const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
            const neg: u64 = -map.get(caps, "imm")
            if mn == "ldr" {
                arm64_ldr_post(rt, rn, neg);
            } else if mn == "str" {
                arm64_str_post(rt, rn, neg);
            } else if mn == "ldrb" {
                arm64_ldrb_post(rt, rn, neg);
            } else if mn == "strb" {
                arm64_strb_post(rt, rn, neg);
            } else if mn == "ldrh" {
                arm64_ldrh_post(rt, rn, neg);
            } else if mn == "strh" {
                arm64_strh_post(rt, rn, neg);
            } else {
                err("arm64_asm: unknown mnemonic for (reg, [reg], -imm) post form", mn);
            }
            done = 1
        }
    }

    if done == 0 {
        const p: map = match.tokens("mn:name rt:name =, =[ rn:name =, =- imm:int =] =!", text)
        if map.get(p, "ok") {
            const caps: map = map.get(p, "captures")
            const mn: string = map.get(caps, "mn")
            const rt: u64 = arm64_parse_reg(map.get(caps, "rt"))
            const rn: u64 = arm64_parse_reg(map.get(caps, "rn"))
            const neg: u64 = -map.get(caps, "imm")
            if mn == "ldr" {
                arm64_ldr_pre(rt, rn, neg);
            } else if mn == "str" {
                arm64_str_pre(rt, rn, neg);
            } else {
                err("arm64_asm: unknown mnemonic for (reg, [reg, -imm]!) pre form", mn);
            }
            done = 1
        }
    }

    if done == 0 {
        err("arm64_asm: unrecognized instruction", text);
    }
}
