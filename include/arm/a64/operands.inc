import("arm/a64/generated/registers.inc")
import("arm/a64/generated/names.inc")

fn a64_reg(text: string) -> list {
    const name: string = lower(trim(text))
    assert(map.has(a64_registers, name), "a64: invalid register or arrangement")
    return map.get(a64_registers, name);
}

fn a64_imm(value: integer) -> list {
    return list.of(0, value);
}

fn a64_fp(value: f64) -> list {
    let magnitude: f64 = value
    let sign: u64 = 0
    if value < 0.0 {
        magnitude = -value
        sign = 128
    }
    let index: u64 = 0
    for candidate in a64_fp_values {
        if magnitude == candidate {
            return list.of(24, sign | index);
        }
        index = index + 1
    }
    assert(false, "a64: floating immediate is not representable")
    return list.of(24, 0);
}

fn a64_stretched_immediate(value: u64) -> u64 {
    let result: u64 = 0
    let index: u64 = 0
    while index < 8 {
        const byte: u64 = (value >> (index * 8)) & 255
        assert(byte == 0 || byte == 255, "a64: immediate bytes must be 00 or FF")
        if byte == 255 {
            result = result | (1 << index)
        }
        index = index + 1
    }
    return result;
}

fn a64_lane(text: string, index: u64) -> list {
    const name: string = lower(trim(text))
    assert(map.has(a64_lanes, name), "a64: invalid lane register")
    const reg: list = map.get(a64_lanes, name)
    const kind: u64 = list.get(reg, 0)
    assert(index < a64_lane_count(kind), "a64: lane index out of range")
    return list.of(kind, list.get(reg, 1), index);
}

fn a64_lane_count(kind: u64) -> u64 {
    if kind == 53 || kind == 54 {
        return 4;
    }
    assert(kind >= 18 && kind <= 21, "a64: invalid lane kind")
    return 16 >> (kind - 18);
}

fn a64_reglist(registers: list) -> list {
    assert(len(registers) >= 1 && len(registers) <= 4, "a64: expected one to four registers")
    const first: list = a64_reg(list.get(registers, 0))
    const kind: u64 = list.get(first, 0)
    const start: u64 = list.get(first, 1)
    assert(kind >= 9 && kind <= 17, "a64: register list requires vector arrangements")
    let index: u64 = 0
    for text in registers {
        const reg: list = a64_reg(text)
        assert(list.get(reg, 0) == kind && list.get(reg, 1) == ((start + index) & 31), "a64: register list must be consecutive with matching arrangements")
        index = index + 1
    }
    return list.of(kind, start, len(registers));
}

fn a64_shift(name: string, amount: u64) -> list {
    const clean: string = lower(trim(name))
    if clean == "lsl" {
        return list.of(22, amount);
    }
    if clean == "msl" {
        return list.of(23, amount);
    }
    const options: list = list.of("lsr", "asr", "ror", "uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx")
    let tag: u64 = 39
    for option in options {
        if clean == option {
            return list.of(tag, amount);
        }
        tag = tag + 1
    }
    assert(false, "a64: invalid immediate modifier")
    return list.of(0, 0);
}

fn a64_option_index(value: u64, options: list) -> u64 {
    let index: u64 = 0
    for option in options {
        if value == option {
            return index;
        }
        index = index + 1
    }
    assert(false, "a64: invalid immediate option")
    return 0;
}

fn a64_flatten(args: list) -> list {
    assert(len(args) <= 5, "a64: invalid operand count")
    let flat: list = list.new()
    for arg in args {
        assert(len(arg) >= 2 && len(arg) <= 4, "a64: invalid operand descriptor")
        const kind: u64 = list.get(arg, 0)
        if (kind >= 18 && kind <= 21) || kind == 53 || kind == 54 {
            assert(len(arg) == 3 || len(arg) == 4, "a64: lane index is required")
            const index: u64 = list.get(arg, 2)
            assert(index < a64_lane_count(kind), "a64: lane index out of range")
            assert(kind <= 21 || len(arg) == 3, "a64: grouped lanes cannot form register lists")
            if len(arg) == 4 {
                list.push_mut(flat, list.of(kind, list.get(arg, 1), list.get(arg, 3)))
            } else {
                list.push_mut(flat, list.of(kind, list.get(arg, 1)))
            }
            list.push_mut(flat, a64_imm(index))
        } else if kind == 26 || kind == 27 {
            assert(len(arg) == 3, "a64: memory offset is required")
            list.push_mut(flat, list.of(kind, list.get(arg, 1)))
            list.push_mut(flat, a64_imm(list.get(arg, 2)))
        } else if kind == 28 {
            assert(len(arg) == 4, "a64: memory index is required")
            const reg: list = list.get(arg, 2)
            const tag: u64 = list.get(reg, 0)
            assert(len(reg) == 2 && tag >= 29 && tag <= 32, "a64: invalid index descriptor")
            list.push_mut(flat, list.of(kind, list.get(arg, 1)))
            list.push_mut(flat, reg)
            // Byte LSL omits the implicit option field in its XML template.
            list.push_mut(flat, a64_imm(list.get(list.of(2, 3, 6, 7), tag - 29)))
            list.push_mut(flat, a64_imm(list.get(arg, 3)))
        } else if kind == 52 {
            assert(len(arg) == 2 || len(arg) == 3, "a64: invalid system register descriptor")
            list.push_mut(flat, list.of(kind, list.get(arg, 1)))
        } else {
            assert(len(arg) <= 3, "a64: invalid operand descriptor")
            list.push_mut(flat, arg)
        }
    }
    return flat;
}

fn a64_cond(text: string) -> list {
    const name: string = lower(trim(text))
    assert(map.has(a64_conditions, name), "a64: invalid condition")
    return list.of(1, map.get(a64_conditions, name));
}

fn a64_signature(args: list) -> u64 {
    assert(len(args) <= 6, "a64: invalid operand count")
    let key: u64 = 1
    for arg in args {
        const kind: u64 = list.get(arg, 0)
        const value: integer = list.get(arg, 1)
        assert(kind <= 55 && kind != 25 && !(kind >= 35 && kind <= 37), "a64: invalid operand kind")
        if (kind >= 2 && kind <= 21) || (kind >= 26 && kind <= 32) || kind >= 53 {
            assert(value >= 0 && value <= 31, "a64: register number out of range")
        } else if kind == 34 || kind == 38 {
            assert(value == 31, "a64: invalid SP descriptor")
        } else if kind == 1 {
            assert(value >= 0 && value <= 15, "a64: condition out of range")
        } else if kind == 24 {
            assert(value >= 0 && value <= 255, "a64: invalid floating immediate descriptor")
        }
        let count: u64 = 0
        if len(arg) > 2 {
            count = list.get(arg, 2)
            assert(kind >= 9 && kind <= 21 && count >= 1 && count <= 4, "a64: invalid register list descriptor")
        }
        key = key * 512 + kind + count * 64
    }
    return key;
}

fn a64_clean(arg: operand) -> operand {
    const text: string = operand.text(arg)
    let start: u64 = 0
    let end: u64 = len(text)
    while start < end && trim(operand.text(operand.slice(arg, start, start + 1))) == "" {
        start = start + 1
    }
    while end > start && trim(operand.text(operand.slice(arg, end - 1, end))) == "" {
        end = end - 1
    }
    return operand.slice(arg, start, end);
}

fn a64_number(arg: operand) -> operand {
    const clean: operand = a64_clean(arg)
    const text: string = operand.text(clean)
    if starts_with(text, "#") {
        return operand.slice(clean, 1, len(text));
    }
    return clean;
}

fn a64_is_lo12(arg: operand) -> bool {
    const captured: operand = a64_number(arg)
    const parsed: map = match.tokens("=: =lo12 =: label:name", lower(trim(operand.text(captured))))
    return map.get(parsed, "ok");
}

fn a64_lo12_name(arg: operand) -> string {
    const captured: operand = a64_number(arg)
    const parsed: map = match.tokens("=: =lo12 =: label:name", lower(trim(operand.text(captured))))
    assert(map.get(parsed, "ok"), "a64: invalid :lo12: label modifier")
    const captures: map = map.get(parsed, "captures")
    return map.get(captures, "label");
}

fn a64_list_register(name: string) -> list {
    const clean: string = lower(trim(name))
    if map.has(a64_lanes, clean) {
        return map.get(a64_lanes, clean);
    }
    return a64_reg(clean);
}

fn a64_parse_regnames(arg: operand) -> list {
    const text: string = lower(operand.text(arg))
    assert(ends_with(text, "}"), "a64: unterminated register list")
    const inner: operand = operand.slice(arg, 1, len(text) - 1)
    const parts: list = operand.split(inner)
    let names: list = list.new()
    if len(parts) == 1 && contains(operand.text(inner), "-") {
        const endpoints: list = split(lower(operand.text(inner)), "-")
        assert(len(endpoints) == 2, "a64: invalid register range")
        const first: list = a64_list_register(list.get(endpoints, 0))
        const last: list = a64_list_register(list.get(endpoints, 1))
        assert(list.get(first, 0) == list.get(last, 0), "a64: mismatched register range")
        const start: u64 = list.get(first, 1)
        const count: u64 = ((list.get(last, 1) + 32 - start) & 31) + 1
        assert(count <= 4, "a64: register range exceeds four registers")
        const arrangement: string = list.get(split(trim(list.get(endpoints, 0)), "."), 1)
        let index: u64 = 0
        while index < count {
            list.push_mut(names, sym.join("v", (start + index) & 31, ".", arrangement))
            index = index + 1
        }
    } else {
        for part in parts {
            list.push_mut(names, operand.text(part))
        }
    }
    return names;
}

fn a64_parse_reglist(arg: operand) -> list {
    return a64_reglist(a64_parse_regnames(arg));
}

fn a64_operands(args: list, floating: bool, zero_float: bool, evaluate: bool, literal: bool, mnemonic: string) -> list {
    assert(len(args) <= 5, "a64: invalid operand count")
    let result: list = list.new()
    for raw in args {
        const arg: operand = a64_clean(raw)
        const text: string = operand.text(arg)
        const name: string = lower(trim(text))
        if literal && len(result) + 1 == len(args) && (mnemonic == "b" || mnemonic == "bl" || mnemonic == "b_cond_target" || mnemonic == "cbz" || mnemonic == "cbnz" || mnemonic == "tbz" || mnemonic == "tbnz" || mnemonic == "adr" || mnemonic == "adrp") {
            list.push_mut(result, a64_parse_target(arg, evaluate))
        } else if (mnemonic == "mrs" && len(result) == 1) || (mnemonic == "msr" && len(result) == 0 && (a64_msr_register_form(args) || starts_with(name, "s") && contains(name, "_") || !map.has(a64_names, name))) {
            list.push_mut(result, a64_sysreg(name))
        } else if (mnemonic == "sys" && (len(result) == 1 || len(result) == 2)) || (mnemonic == "sysl" && (len(result) == 2 || len(result) == 3)) {
            list.push_mut(result, a64_control(name))
        } else if mnemonic == "isb" && name == "sy" {
            list.push_mut(result, a64_imm(15))
        } else if !starts_with(name, "[") && contains(name, ":lo12:") {
            assert(a64_is_lo12(arg), "a64: invalid :lo12: label modifier")
            assert(mnemonic == "add", "a64: :lo12: immediate modifier is only valid for ADD")
            if evaluate {
                list.push_mut(result, a64_lo12(a64_lo12_name(arg)))
            } else {
                list.push_mut(result, a64_imm(0))
            }
        } else if !literal && map.has(a64_names, name) {
            list.push_mut(result, a64_name(name))
        } else if map.has(a64_registers, name) {
            list.push_mut(result, a64_reg(name))
        } else if map.has(a64_conditions, name) {
            list.push_mut(result, a64_cond(name))
        } else if starts_with(name, "[") {
            list.push_mut(result, a64_parse_memory(arg, evaluate))
        } else if starts_with(name, "{") {
            list.push_mut(result, a64_parse_structure(arg, evaluate))
        } else if starts_with(name, "v") && contains(name, "[") {
            const pieces: list = split(name, "[")
            assert(len(pieces) == 2 && ends_with(name, "]"), "a64: invalid lane syntax")
            const base: string = trim(list.get(pieces, 0))
            assert(map.has(a64_lanes, base), "a64: invalid lane register")
            const captured: operand = operand.slice(arg, len(list.get(pieces, 0)) + 1, len(text) - 1)
            let index: u64 = 0
            if evaluate {
                index = operand.eval(captured)
            }
            list.push_mut(result, a64_lane(base, index))
        } else if a64_modifier_prefix(name) != 0 {
            const width: u64 = a64_modifier_prefix(name)
            if len(name) == width {
                assert(width == 4, "a64: missing modifier amount")
                list.push_mut(result, a64_shift(name, 0))
                continue
            }
            const separator: string = operand.text(operand.slice(arg, width, width + 1))
            assert(trim(separator) == "" || separator == "#", "a64: invalid immediate modifier")
            const option: string = operand.text(operand.slice(arg, 0, width))
            const captured: operand = a64_number(operand.slice(arg, width, len(text)))
            let amount: u64 = 0
            if evaluate {
                amount = operand.eval(captured)
            }
            list.push_mut(result, a64_shift(option, amount))
        } else {
            const captured: operand = a64_number(arg)
            if literal && len(args) == 2 && len(result) == 1 {
                if evaluate {
                    if starts_with(name, "#") {
                        list.push_mut(result, a64_rel(operand.eval(captured)))
                    } else {
                        const label: map = match.tokens("name:name", name)
                        if map.get(label, "ok") {
                            list.push_mut(result, a64_target(name))
                        } else {
                            list.push_mut(result, list.of(35, captured))
                        }
                    }
                } else {
                    list.push_mut(result, a64_rel(0))
                }
            } else if a64_is_prefetch(name) {
                list.push_mut(result, a64_prefetch(name))
            } else if floating {
                if evaluate {
                    const value: f64 = operand.eval(captured)
                    list.push_mut(result, a64_fp(value))
                } else {
                    list.push_mut(result, list.of(24, 0))
                }
            } else if zero_float {
                if evaluate && trim(operand.text(captured)) != "0" {
                    const value: f64 = operand.eval(captured)
                    assert(value == 0.0, "a64: comparison immediate must be zero")
                }
                list.push_mut(result, a64_imm(0))
            } else {
                let value: integer = 0
                if evaluate {
                    value = operand.eval(captured)
                }
                list.push_mut(result, a64_imm(value))
            }
        }
    }
    return result;
}
