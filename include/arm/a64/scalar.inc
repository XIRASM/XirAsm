fn a64_modifier_prefix(text: string) -> u64 {
    for name in list.of("lsl", "msl", "lsr", "asr", "ror", "uxtb", "uxth", "uxtw", "uxtx", "sxtb", "sxth", "sxtw", "sxtx") {
        if starts_with(text, name) {
            return len(name);
        }
    }
    return 0;
}

fn a64_name(text: string) -> list {
    const name: string = lower(trim(text))
    assert(map.has(a64_names, name), "a64: unknown system operand")
    return list.of(50, map.get(a64_names, name));
}

fn a64_small_number(text: string, maximum: u64) -> u64 {
    let value: u64 = 0
    while value <= maximum {
        if text == sym.join("", value) {
            return value;
        }
        value = value + 1
    }
    assert(false, "a64: numeric suffix out of range")
    return 0;
}

fn a64_control(text: string) -> list {
    const name: string = lower(trim(text))
    let index: u64 = 0
    while index < 16 {
        if name == sym.join("c", index) {
            return list.of(51, index);
        }
        index = index + 1
    }
    assert(false, "a64: expected C0-C15")
    return list.of(51, 0);
}

fn a64_sysreg(text: string) -> list {
    const name: string = lower(trim(text))
    if map.has(a64_system_registers, name) {
        const entry: list = map.get(a64_system_registers, name)
        return list.of(52, list.get(entry, 0), list.get(entry, 1));
    }
    const parts: list = split(name, "_")
    assert(len(parts) == 5, "a64: expected system register S2/S3_op1_Cn_Cm_op2")
    const prefix: string = list.get(parts, 0)
    assert(prefix == "s2" || prefix == "s3", "a64: invalid system register op0")
    let op0: u64 = 0
    if prefix == "s3" {
        op0 = 1
    }
    const op1: u64 = a64_small_number(list.get(parts, 1), 7)
    const crn: u64 = list.get(a64_control(list.get(parts, 2)), 1)
    const crm: u64 = list.get(a64_control(list.get(parts, 3)), 1)
    const op2: u64 = a64_small_number(list.get(parts, 4), 7)
    return list.of(52, (op0 << 14) | (op1 << 11) | (crn << 7) | (crm << 3) | op2);
}

fn a64_check_sysreg(args: list, index: u64, access: u64) {
    if len(args) > index {
        const arg: list = list.get(args, index)
        if len(arg) == 3 && list.get(arg, 0) == 52 {
            const allowed: u64 = list.get(arg, 2)
            assert(allowed >= 1 && allowed <= 3 && (allowed & access) != 0, "a64: invalid system register access")
        }
    }
}

fn a64_msr_register_form(args: list) -> bool {
    if len(args) != 2 {
        return false;
    }
    const source: string = lower(trim(operand.text(list.get(args, 1))))
    return map.has(a64_registers, source);
}

fn a64_parse_target(arg: operand, evaluate: bool) -> list {
    if !evaluate {
        return a64_rel(0);
    }
    const text: string = operand.text(arg)
    if starts_with(text, "#") {
        return a64_rel(operand.eval(a64_number(arg)));
    }
    const parsed: map = match.tokens("name:name", text)
    if map.get(parsed, "ok") {
        return a64_target(text);
    }
    return list.of(35, arg);
}

fn a64_mask(width: u64) -> u64 {
    if width == 64 {
        return 0xffffffffffffffff;
    }
    return (1 << width) - 1;
}

fn a64_rotate(value: u64, amount: u64, width: u64) -> u64 {
    const shift: u64 = amount % width
    if shift == 0 {
        return value & a64_mask(width);
    }
    return ((value >> shift) | (value << (width - shift))) & a64_mask(width);
}

// Return a sentinel for a nonmatching MOV candidate instead of rejecting before dispatch.
fn a64_scalar_special(input: integer, kind: string) -> u64 {
    let width: u64 = 64
    if ends_with(kind, "_w") {
        width = 32
    }
    const mask: u64 = a64_mask(width)
    if width == 32 && (input >> 32) != 0 && (input >> 32) != 0xffffffff {
        return 0xffffffffffffffff;
    }
    let value: u64 = input & mask
    if !starts_with(kind, "logical") {
        if starts_with(kind, "inverted") {
            value = (~value) & mask
        }
        let shift: u64 = 0
        while shift < width {
            const half: u64 = (value >> shift) & 65535
            if (half << shift) == value {
                return half | ((shift / 16) << 16);
            }
            shift = shift + 16
        }
        return 0xffffffffffffffff;
    }
    if value == 0 || value == mask {
        return 0xffffffffffffffff;
    }
    let size: u64 = 2
    while size <= width {
        const element: u64 = value & a64_mask(size)
        let repeated: u64 = 0
        let position: u64 = 0
        while position < width {
            repeated = repeated | (element << position)
            position = position + size
        }
        if repeated == value {
            let rotation: u64 = 0
            while rotation < size {
                const run: u64 = a64_rotate(element, (size - rotation) % size, size)
                if run != a64_mask(size) && (run & (run + 1)) == 0 {
                    let ones: u64 = 0
                    let bits: u64 = run
                    while bits > 0 {
                        ones = ones + 1
                        bits = bits >> 1
                    }
                    let n: u64 = 0
                    if size == 64 {
                        n = 1
                    }
                    return (n << 12) | (rotation << 6) | ((~(2 * size - 1) & 63) | (ones - 1));
                }
                rotation = rotation + 1
            }
            return 0xffffffffffffffff;
        }
        size = size * 2
    }
    return 0xffffffffffffffff;
}
