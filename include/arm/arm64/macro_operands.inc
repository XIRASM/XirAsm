// Operand parsing is kept separate from instruction encoding.
fn arm64_macro_number(arg: operand) -> u64 {
    const text: string = operand.text(arg)
    const clean: string = trim(text)
    let start: u64 = 0
    while start < len(text) && trim(operand.text(operand.slice(arg, start, start + 1))) == "" {
        start = start + 1
    }
    if starts_with(clean, "#") {
        start = start + 1
    }
    const value: operand = operand.slice(arg, start, len(text))
    return operand.eval(value)
}

fn arm64_macro_option(arg: operand) -> map {
    const text: string = operand.text(arg)
    const words: list = tokens.of(text)
    assert(len(words) > 0, "missing shift or extend option")
    const word: string = list.get(words, 0)
    assert(map.has(arm64_shift_table, word) || map.has(arm64_ext_table, word), "invalid shift or extend option")
    let result: map = map.set(map.new(), "optw", word)
    if len(words) == 1 {
        map.set_mut(result, "amount", 0)
    } else {
        map.set_mut(result, "amount", arm64_macro_number(operand.slice(arg, len(word), len(text))))
    }
    return result
}

fn arm64_macro_move(mn: string, dst: operand, src: operand, options: list) {
    const rd: u64 = arm64_parse_reg(operand.text(dst))
    const text: string = operand.text(src)
    if mn == "mov" && map.has(arm64_reg_table, text) {
        assert(len(options) == 0, "register mov does not take a shift option")
        arm64_mov_reg(rd, arm64_parse_reg(text))
    } else {
        const immediate: u64 = arm64_macro_number(src)
        let shift: u64 = 0
        assert(len(options) <= 1, "too many move-wide options")
        if len(options) == 1 {
            const option: map = arm64_macro_option(list.get(options, 0))
            assert(map.get(option, "optw") == "lsl", "move-wide requires lsl")
            shift = map.get(option, "amount")
        }
        if mn == "mov" {
            assert(len(options) == 0, "mov immediate does not take a shift option")
            arm64_mov_imm(rd, immediate)
        } else if mn == "movz" {
            arm64_movz(rd, immediate, shift)
        } else if mn == "movk" {
            arm64_movk(rd, immediate, shift)
        } else {
            assert(mn == "movn", "invalid move-wide mnemonic")
            arm64_movn(rd, immediate, shift)
        }
    }
}

fn arm64_macro_alu(mn: string, dst: operand, lhs: operand, rhs: operand, options: list) {
    let caps: map = map.set(map.new(), "mn", mn)
    map.set_mut(caps, "rd", operand.text(dst))
    map.set_mut(caps, "rn", operand.text(lhs))
    const right: string = operand.text(rhs)
    assert(len(options) <= 1, "too many arithmetic options")
    if map.has(arm64_reg_table, right) || mn == "cinc" || mn == "cinv" || mn == "cneg" {
        map.set_mut(caps, "rm", right)
        if len(options) == 0 {
            arm64_asm_3op_reg(caps)
        } else {
            const option: map = arm64_macro_option(list.get(options, 0))
            map.set_mut(caps, "optw", map.get(option, "optw"))
            map.set_mut(caps, "amount", map.get(option, "amount"))
            arm64_asm_4op_option(caps)
        }
    } else {
        map.set_mut(caps, "imm", arm64_macro_number(rhs))
        if len(options) == 0 {
            arm64_asm_3op_imm(caps)
        } else {
            const option: map = arm64_macro_option(list.get(options, 0))
            assert(map.get(option, "optw") == "lsl", "immediate arithmetic requires lsl")
            map.set_mut(caps, "shift", map.get(option, "amount"))
            arm64_asm_addsub_imm_lsl(caps)
        }
    }
}

fn arm64_macro_select(mn: string, dst: operand, lhs: operand, rhs: operand, cond: operand) {
    let caps: map = map.set(map.new(), "mn", mn)
    map.set_mut(caps, "rd", operand.text(dst))
    map.set_mut(caps, "rn", operand.text(lhs))
    map.set_mut(caps, "rm", operand.text(rhs))
    map.set_mut(caps, "optw", operand.text(cond))
    arm64_asm_csel(caps)
}

fn arm64_macro_compare(mn: string, lhs: operand, rhs: operand, nzcv: operand, cond: operand) {
    let caps: map = map.set(map.new(), "mn", mn)
    map.set_mut(caps, "rn", operand.text(lhs))
    map.set_mut(caps, "nzcv", arm64_macro_number(nzcv))
    map.set_mut(caps, "cond", operand.text(cond))
    if map.has(arm64_reg_table, operand.text(rhs)) {
        map.set_mut(caps, "rm", operand.text(rhs))
        arm64_asm_ccmp_reg(caps)
    } else {
        map.set_mut(caps, "imm", arm64_macro_number(rhs))
        arm64_asm_ccmp_imm(caps)
    }
}

fn arm64_macro_memory(mn: string, reg: operand, address: operand, post: list) {
    const text: string = operand.text(address)
    let caps: map = map.set(map.new(), "mn", mn)
    map.set_mut(caps, "rt", operand.text(reg))
    if !starts_with(text, "[") {
        assert(len(post) == 0, "literal load does not take post-index")
        map.set_mut(caps, "rd", operand.text(reg))
        map.set_mut(caps, "target", text)
        arm64_asm_reg_target(caps)
    } else {
        const pre: bool = ends_with(text, "]!")
        assert(pre || ends_with(text, "]"), "invalid memory operand")
        let closing: u64 = len(text) - 1
        if pre {
            closing = closing - 1
        }
        const parts: list = operand.split(operand.slice(address, 1, closing))
        assert(len(parts) >= 1 && len(parts) <= 2, "expected base and optional offset")
        map.set_mut(caps, "rn", operand.text(list.get(parts, 0)))
        assert(len(post) <= 1, "too many post-index operands")
        if len(post) == 1 {
            assert(!pre && len(parts) == 1, "post-index requires a bare base address")
            map.set_mut(caps, "imm", arm64_macro_number(list.get(post, 0)))
            arm64_asm_post(caps)
        } else if len(parts) == 1 {
            assert(!pre, "pre-index requires an offset")
            arm64_asm_mem0(caps)
        } else {
            const offset: operand = list.get(parts, 1)
            if map.has(arm64_reg_table, operand.text(offset)) {
                assert(!pre, "register offset cannot use writeback")
                map.set_mut(caps, "rm", operand.text(offset))
                arm64_asm_mem_reg0(caps)
            } else {
                map.set_mut(caps, "imm", arm64_macro_number(offset))
                if pre {
                    arm64_asm_pre(caps)
                } else {
                    arm64_asm_mem_off(caps)
                }
            }
        }
    }
}

fn arm64_macro_pair(mn: string, first: operand, second: operand, address: operand) {
    const text: string = operand.text(address)
    assert(starts_with(text, "[") && ends_with(text, "]"), "pair load/store requires [base, offset]")
    const parts: list = operand.split(operand.slice(address, 1, len(text) - 1))
    assert(len(parts) >= 1 && len(parts) <= 2, "expected base and optional pair offset")
    let caps: map = map.set(map.new(), "mn", mn)
    map.set_mut(caps, "rt", operand.text(first))
    map.set_mut(caps, "rt2", operand.text(second))
    map.set_mut(caps, "rn", operand.text(list.get(parts, 0)))
    if len(parts) == 1 {
        arm64_asm_pair0(caps)
    } else {
        map.set_mut(caps, "imm", arm64_macro_number(list.get(parts, 1)))
        arm64_asm_pair_off(caps)
    }
}
