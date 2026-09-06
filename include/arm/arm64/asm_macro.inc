// Natural A64 statements. Encoding remains in the DSL helpers.
import("macro_operands.inc")

macro nop() {
    arm64_nop()
}

macro ret() {
    arm64_ret()
}

macro b(target) {
    arm64_b(operand.text(target))
}

macro bl(target) {
    arm64_bl(operand.text(target))
}

macro b.eq(target) {
    arm64_b_cond(arm64_cond_eq, operand.text(target))
}

macro b.ne(target) {
    arm64_b_cond(arm64_cond_ne, operand.text(target))
}

macro b.cs(target) {
    arm64_b_cond(arm64_cond_cs, operand.text(target))
}

macro b.cc(target) {
    arm64_b_cond(arm64_cond_cc, operand.text(target))
}

macro b.mi(target) {
    arm64_b_cond(arm64_cond_mi, operand.text(target))
}

macro b.pl(target) {
    arm64_b_cond(arm64_cond_pl, operand.text(target))
}

macro b.vs(target) {
    arm64_b_cond(arm64_cond_vs, operand.text(target))
}

macro b.vc(target) {
    arm64_b_cond(arm64_cond_vc, operand.text(target))
}

macro b.hi(target) {
    arm64_b_cond(arm64_cond_hi, operand.text(target))
}

macro b.ls(target) {
    arm64_b_cond(arm64_cond_ls, operand.text(target))
}

macro b.ge(target) {
    arm64_b_cond(arm64_cond_ge, operand.text(target))
}

macro b.lt(target) {
    arm64_b_cond(arm64_cond_lt, operand.text(target))
}

macro b.gt(target) {
    arm64_b_cond(arm64_cond_gt, operand.text(target))
}

macro b.le(target) {
    arm64_b_cond(arm64_cond_le, operand.text(target))
}

macro b.hs(target) {
    arm64_b_cond(arm64_cond_hs, operand.text(target))
}

macro b.lo(target) {
    arm64_b_cond(arm64_cond_lo, operand.text(target))
}

macro br(target) {
    arm64_br(arm64_parse_reg(operand.text(target)))
}

macro blr(target) {
    arm64_blr(arm64_parse_reg(operand.text(target)))
}

macro cbz(src, target) {
    arm64_cbz(arm64_parse_reg(operand.text(src)), operand.text(target))
}

macro cbnz(src, target) {
    arm64_cbnz(arm64_parse_reg(operand.text(src)), operand.text(target))
}

macro tbz(src, bit, target) {
    arm64_tbz(arm64_parse_reg(operand.text(src)), arm64_macro_number(bit), operand.text(target))
}

macro tbnz(src, bit, target) {
    arm64_tbnz(arm64_parse_reg(operand.text(src)), arm64_macro_number(bit), operand.text(target))
}

macro adr(dst, target) {
    arm64_adr(arm64_parse_reg(operand.text(dst)), operand.text(target))
}

macro adrp(dst, target) {
    arm64_adrp(arm64_parse_reg(operand.text(dst)), operand.text(target))
}

macro mov(dst, src) {
    arm64_macro_move("mov", dst, src, list.new())
}

macro movz(dst, src) {
    arm64_macro_move("movz", dst, src, list.new())
}

macro movz(dst, src, option) {
    arm64_macro_move("movz", dst, src, list.of(option))
}

macro movk(dst, src) {
    arm64_macro_move("movk", dst, src, list.new())
}

macro movk(dst, src, option) {
    arm64_macro_move("movk", dst, src, list.of(option))
}

macro movn(dst, src) {
    arm64_macro_move("movn", dst, src, list.new())
}

macro movn(dst, src, option) {
    arm64_macro_move("movn", dst, src, list.of(option))
}

macro add(dst, lhs, rhs) {
    arm64_macro_alu("add", dst, lhs, rhs, list.new())
}

macro add(dst, lhs, rhs, option) {
    arm64_macro_alu("add", dst, lhs, rhs, list.of(option))
}

macro adds(dst, lhs, rhs) {
    arm64_macro_alu("adds", dst, lhs, rhs, list.new())
}

macro adds(dst, lhs, rhs, option) {
    arm64_macro_alu("adds", dst, lhs, rhs, list.of(option))
}

macro sub(dst, lhs, rhs) {
    arm64_macro_alu("sub", dst, lhs, rhs, list.new())
}

macro sub(dst, lhs, rhs, option) {
    arm64_macro_alu("sub", dst, lhs, rhs, list.of(option))
}

macro subs(dst, lhs, rhs) {
    arm64_macro_alu("subs", dst, lhs, rhs, list.new())
}

macro subs(dst, lhs, rhs, option) {
    arm64_macro_alu("subs", dst, lhs, rhs, list.of(option))
}

macro and(dst, lhs, rhs) {
    arm64_macro_alu("and", dst, lhs, rhs, list.new())
}

macro and(dst, lhs, rhs, option) {
    arm64_macro_alu("and", dst, lhs, rhs, list.of(option))
}

macro orr(dst, lhs, rhs) {
    arm64_macro_alu("orr", dst, lhs, rhs, list.new())
}

macro orr(dst, lhs, rhs, option) {
    arm64_macro_alu("orr", dst, lhs, rhs, list.of(option))
}

macro eor(dst, lhs, rhs) {
    arm64_macro_alu("eor", dst, lhs, rhs, list.new())
}

macro eor(dst, lhs, rhs, option) {
    arm64_macro_alu("eor", dst, lhs, rhs, list.of(option))
}

macro ands(dst, lhs, rhs) {
    arm64_macro_alu("ands", dst, lhs, rhs, list.new())
}

macro ands(dst, lhs, rhs, option) {
    arm64_macro_alu("ands", dst, lhs, rhs, list.of(option))
}

macro bic(dst, lhs, rhs) {
    arm64_macro_alu("bic", dst, lhs, rhs, list.new())
}

macro bic(dst, lhs, rhs, option) {
    arm64_macro_alu("bic", dst, lhs, rhs, list.of(option))
}

macro orn(dst, lhs, rhs) {
    arm64_macro_alu("orn", dst, lhs, rhs, list.new())
}

macro orn(dst, lhs, rhs, option) {
    arm64_macro_alu("orn", dst, lhs, rhs, list.of(option))
}

macro eon(dst, lhs, rhs) {
    arm64_macro_alu("eon", dst, lhs, rhs, list.new())
}

macro eon(dst, lhs, rhs, option) {
    arm64_macro_alu("eon", dst, lhs, rhs, list.of(option))
}

macro bics(dst, lhs, rhs) {
    arm64_macro_alu("bics", dst, lhs, rhs, list.new())
}

macro bics(dst, lhs, rhs, option) {
    arm64_macro_alu("bics", dst, lhs, rhs, list.of(option))
}

macro adc(dst, lhs, rhs) {
    arm64_macro_alu("adc", dst, lhs, rhs, list.new())
}

macro adcs(dst, lhs, rhs) {
    arm64_macro_alu("adcs", dst, lhs, rhs, list.new())
}

macro sbc(dst, lhs, rhs) {
    arm64_macro_alu("sbc", dst, lhs, rhs, list.new())
}

macro sbcs(dst, lhs, rhs) {
    arm64_macro_alu("sbcs", dst, lhs, rhs, list.new())
}

macro lsl(dst, lhs, rhs) {
    arm64_macro_alu("lsl", dst, lhs, rhs, list.new())
}

macro lsr(dst, lhs, rhs) {
    arm64_macro_alu("lsr", dst, lhs, rhs, list.new())
}

macro asr(dst, lhs, rhs) {
    arm64_macro_alu("asr", dst, lhs, rhs, list.new())
}

macro ror(dst, lhs, rhs) {
    arm64_macro_alu("ror", dst, lhs, rhs, list.new())
}

macro cinc(dst, lhs, rhs) {
    arm64_macro_alu("cinc", dst, lhs, rhs, list.new())
}

macro cinv(dst, lhs, rhs) {
    arm64_macro_alu("cinv", dst, lhs, rhs, list.new())
}

macro cneg(dst, lhs, rhs) {
    arm64_macro_alu("cneg", dst, lhs, rhs, list.new())
}

macro ngc(dst, src) {
    arm64_ngc(arm64_parse_reg(operand.text(dst)), arm64_parse_reg(operand.text(src)))
}

macro ngcs(dst, src) {
    arm64_ngcs(arm64_parse_reg(operand.text(dst)), arm64_parse_reg(operand.text(src)))
}

macro cset(dst, cond) {
    arm64_cset(arm64_parse_reg(operand.text(dst)), arm64_parse_cond(operand.text(cond)))
}

macro csetm(dst, cond) {
    arm64_csetm(arm64_parse_reg(operand.text(dst)), arm64_parse_cond(operand.text(cond)))
}

macro csel(dst, lhs, rhs, cond) {
    arm64_macro_select("csel", dst, lhs, rhs, cond)
}

macro csinc(dst, lhs, rhs, cond) {
    arm64_macro_select("csinc", dst, lhs, rhs, cond)
}

macro csinv(dst, lhs, rhs, cond) {
    arm64_macro_select("csinv", dst, lhs, rhs, cond)
}

macro csneg(dst, lhs, rhs, cond) {
    arm64_macro_select("csneg", dst, lhs, rhs, cond)
}

macro ccmp(lhs, rhs, nzcv, cond) {
    arm64_macro_compare("ccmp", lhs, rhs, nzcv, cond)
}

macro ccmn(lhs, rhs, nzcv, cond) {
    arm64_macro_compare("ccmn", lhs, rhs, nzcv, cond)
}

macro tst(lhs, rhs) {
    if map.has(arm64_reg_table, operand.text(rhs)) {
        arm64_tst_reg(arm64_parse_reg(operand.text(lhs)), arm64_parse_reg(operand.text(rhs)), 0, 0)
    } else {
        arm64_tst_imm(arm64_parse_reg(operand.text(lhs)), arm64_macro_number(rhs))
    }
}

macro ldr(reg, address) {
    arm64_macro_memory("ldr", reg, address, list.new())
}

macro ldr(reg, address, offset) {
    arm64_macro_memory("ldr", reg, address, list.of(offset))
}

macro str(reg, address) {
    arm64_macro_memory("str", reg, address, list.new())
}

macro str(reg, address, offset) {
    arm64_macro_memory("str", reg, address, list.of(offset))
}

macro ldrb(reg, address) {
    arm64_macro_memory("ldrb", reg, address, list.new())
}

macro ldrb(reg, address, offset) {
    arm64_macro_memory("ldrb", reg, address, list.of(offset))
}

macro strb(reg, address) {
    arm64_macro_memory("strb", reg, address, list.new())
}

macro strb(reg, address, offset) {
    arm64_macro_memory("strb", reg, address, list.of(offset))
}

macro ldrh(reg, address) {
    arm64_macro_memory("ldrh", reg, address, list.new())
}

macro ldrh(reg, address, offset) {
    arm64_macro_memory("ldrh", reg, address, list.of(offset))
}

macro strh(reg, address) {
    arm64_macro_memory("strh", reg, address, list.new())
}

macro strh(reg, address, offset) {
    arm64_macro_memory("strh", reg, address, list.of(offset))
}

macro ldrsw(reg, address) {
    arm64_macro_memory("ldrsw", reg, address, list.new())
}

macro ldrsw(reg, address, offset) {
    arm64_macro_memory("ldrsw", reg, address, list.of(offset))
}

macro ldrsb(reg, address) {
    arm64_macro_memory("ldrsb", reg, address, list.new())
}

macro ldrsb(reg, address, offset) {
    arm64_macro_memory("ldrsb", reg, address, list.of(offset))
}

macro ldrsh(reg, address) {
    arm64_macro_memory("ldrsh", reg, address, list.new())
}

macro ldrsh(reg, address, offset) {
    arm64_macro_memory("ldrsh", reg, address, list.of(offset))
}

macro ldur(reg, address) {
    arm64_macro_memory("ldur", reg, address, list.new())
}

macro stur(reg, address) {
    arm64_macro_memory("stur", reg, address, list.new())
}

macro ldp(first, second, address) {
    arm64_macro_pair("ldp", first, second, address)
}

macro stp(first, second, address) {
    arm64_macro_pair("stp", first, second, address)
}

macro ldpsw(first, second, address) {
    arm64_macro_pair("ldpsw", first, second, address)
}
