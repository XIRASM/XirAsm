fn a64_base(name: string) -> u64 {
    const reg: list = a64_reg(name)
    const kind: u64 = list.get(reg, 0)
    const number: u64 = list.get(reg, 1)
    assert(kind == 34 || (kind == 3 && number < 31), "a64: memory base requires X0-X30 or SP")
    return number;
}

fn a64_mem(base: string, offset: integer) -> list {
    return list.of(26, a64_base(base), offset);
}

fn a64_pre(base: string, offset: integer) -> list {
    return list.of(27, a64_base(base), offset);
}

fn a64_index(base: string, index: string, extend: string, amount: integer) -> list {
    const reg: list = a64_reg(index)
    const kind: u64 = list.get(reg, 0)
    const option: string = lower(trim(extend))
    let tag: u64 = 0
    if option == "uxtw" {
        tag = 29
    } else if option == "lsl" {
        tag = 30
    } else if option == "sxtw" {
        tag = 31
    } else if option == "sxtx" {
        tag = 32
    }
    assert(tag != 0, "a64: invalid memory extend")
    assert((kind == 2 && (tag == 29 || tag == 31)) || (kind == 3 && (tag == 30 || tag == 32)), "a64: index register width does not match extend")
    assert(amount == -1 || amount <= 4, "a64: invalid index shift")
    return list.of(28, a64_base(base), list.of(tag, list.get(reg, 1)), amount);
}

fn a64_scale_flag(amount: integer, scale: integer) -> u64 {
    if amount == scale {
        return 1;
    }
    return 0;
}

fn a64_rel(displacement: integer) -> list {
    return list.of(33, displacement);
}

fn a64_target(name: string) -> list {
    return list.of(36, name);
}

fn a64_address(address: u64) -> list {
    return list.of(37, address);
}

fn a64_has_target(args: list) -> bool {
    if len(args) == 0 {
        return false;
    }
    const kind: u64 = list.get(list.get(args, len(args) - 1), 0)
    return kind >= 35 && kind <= 37;
}

fn a64_literal_values(args: list, pc: u64, evaluate: bool, page: bool) -> list {
    const arg: list = list.get(args, len(args) - 1)
    const kind: u64 = list.get(arg, 0)
    let delta: integer = 0
    if evaluate {
        let address: integer = 0
        if kind == 35 {
            const captured: operand = list.get(arg, 1)
            address = operand.eval(captured)
        } else if kind == 36 {
            address = label_addr(list.get(arg, 1))
        } else {
            address = list.get(arg, 1)
        }
        let site: u64 = pc
        if page {
            address = address & ~4095
            site = site & ~4095
        }
        if address >= site {
            delta = address - site
        } else {
            delta = -(site - address)
        }
    }
    let result: list = list.new()
    let index: u64 = 0
    while index + 1 < len(args) {
        list.push_mut(result, list.get(args, index))
        index = index + 1
    }
    list.push_mut(result, a64_rel(delta))
    return result;
}

fn a64_parse_memory(arg: operand, evaluate: bool) -> list {
    const text: string = operand.text(arg)
    const pre: bool = ends_with(text, "]!")
    assert(pre || ends_with(text, "]"), "a64: unterminated memory operand")
    let end: u64 = len(text) - 1
    if pre {
        end = end - 1
    }
    const parts: list = operand.split(operand.slice(arg, 1, end))
    assert(len(parts) >= 1 && len(parts) <= 3, "a64: invalid memory operand count")
    const base: string = operand.text(list.get(parts, 0))
    if len(parts) == 1 {
        assert(!pre, "a64: pre-index requires an offset")
        return a64_mem(base, 0);
    }
    const offset: operand = a64_clean(list.get(parts, 1))
    const index: string = lower(operand.text(offset))
    if map.has(a64_registers, index) {
        assert(!pre, "a64: register offset cannot write back")
        let extend: string = "lsl"
        let amount: integer = -1
        if len(parts) == 3 {
            const modifier: operand = a64_clean(list.get(parts, 2))
            const name: string = lower(operand.text(modifier))
            let width: u64 = 4
            if starts_with(name, "lsl") {
                width = 3
            }
            assert(len(name) >= width, "a64: invalid memory extend")
            extend = operand.text(operand.slice(modifier, 0, width))
            if len(name) > width {
                const separator: string = operand.text(operand.slice(modifier, width, width + 1))
                assert(trim(separator) == "" || separator == "#", "a64: invalid memory shift")
                const shift: operand = a64_number(operand.slice(modifier, width, len(name)))
                if len(trim(operand.text(shift))) > 0 {
                    amount = 0
                    if evaluate {
                        amount = operand.eval(shift)
                    }
                    assert(amount <= 4, "a64: invalid memory shift")
                }
            }
        } else {
            assert(list.get(a64_reg(index), 0) == 3, "a64: W index requires an extend")
        }
        return a64_index(base, index, extend, amount);
    }
    assert(len(parts) == 2, "a64: immediate offset cannot have a modifier")
    let value: integer = 0
    if evaluate {
        value = operand.eval(a64_number(offset))
    }
    if pre {
        return a64_pre(base, value);
    }
    return a64_mem(base, value);
}

fn a64_lanelist(registers: list, index: u64) -> list {
    assert(len(registers) >= 1 && len(registers) <= 4, "a64: expected one to four lane registers")
    const first: list = a64_lane(list.get(registers, 0), index)
    const kind: u64 = list.get(first, 0)
    const start: u64 = list.get(first, 1)
    let count: u64 = 0
    for name in registers {
        const reg: list = a64_lane(name, index)
        assert(list.get(reg, 0) == kind && list.get(reg, 1) == ((start + count) & 31), "a64: lane list must be consecutive with matching sizes")
        count = count + 1
    }
    return list.of(kind, start, index, count);
}

fn a64_parse_structure(arg: operand, evaluate: bool) -> list {
    const text: string = operand.text(arg)
    if ends_with(text, "}") {
        return a64_parse_reglist(arg);
    }
    const pieces: list = split(text, "}")
    assert(len(pieces) == 2, "a64: invalid structure list")
    const end: u64 = len(list.get(pieces, 0)) + 1
    const tail: operand = a64_clean(operand.slice(arg, end, len(text)))
    const suffix: string = operand.text(tail)
    assert(starts_with(suffix, "[") && ends_with(suffix, "]"), "a64: structure lane index required")
    let index: u64 = 0
    if evaluate {
        index = operand.eval(operand.slice(tail, 1, len(suffix) - 1))
    }
    return a64_lanelist(a64_parse_regnames(operand.slice(arg, 0, end)), index);
}

fn a64_is_prefetch(name: string) -> bool {
    return starts_with(name, "pldl") || starts_with(name, "plil") || starts_with(name, "pstl");
}

fn a64_prefetch(text: string) -> list {
    const name: string = lower(trim(text))
    let value: u64 = 0
    for operation in list.of("pld", "pli", "pst") {
        let level: u64 = 1
        while level <= 3 {
            if name == sym.join(operation, "l", level, "keep") {
                return a64_imm(value);
            }
            if name == sym.join(operation, "l", level, "strm") {
                return a64_imm(value + 1);
            }
            value = value + 2
            level = level + 1
        }
        value = value + 2
    }
    assert(false, "a64: invalid prefetch operation")
    return a64_imm(0);
}
