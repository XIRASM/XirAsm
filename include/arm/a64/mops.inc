// FEAT_MOPS operand parsing.
//
// MOPS instructions spell their updated registers with writeback decoration:
//   SETP [<Xd>]!, <Xn>!, <Xs>      (set: destination, count, source data)
//   CPYP [<Xd>]!, [<Xs>]!, <Xn>!   (copy: destination, source, count)
//   SETGOP [<Xd>]!, <Xn>!          (set-go: destination, count; Rs is RES1)
// The brackets and "!" are assembly syntax only; they do not occupy encoding
// bits, so the finite-form word functions take plain X register descriptors.
// This helper strips the decoration and rejects anything that is not a 64-bit
// X register (XZR is allowed, SP/W registers are not, matching the XML rules
// XdOrXZR / XnOrXZR / XsOrXZR).

fn a64_mops_one(arg: operand, syntax: string) -> list {
    let body: string = lower(trim(operand.text(a64_clean(arg))))
    if syntax == "bracketed_writeback" {
        assert(starts_with(body, "[") && ends_with(body, "]!"), "a64 mops: expected [Xn]!")
        const opened: list = split(body, "[")
        assert(len(opened) == 2 && list.get(opened, 0) == "", "a64 mops: malformed [Xn]! operand")
        const closed: list = split(list.get(opened, 1), "]!")
        assert(len(closed) == 2 && list.get(closed, 1) == "", "a64 mops: malformed [Xn]! operand")
        body = list.get(closed, 0)
    } else if syntax == "writeback" {
        assert(!contains(body, "[") && !contains(body, "]") && ends_with(body, "!"), "a64 mops: expected Xn!")
        const bang: list = split(body, "!")
        assert(len(bang) == 2 && list.get(bang, 1) == "", "a64 mops: malformed Xn! operand")
        body = list.get(bang, 0)
    } else {
        assert(syntax == "plain", "a64 mops: invalid operand syntax class")
        assert(!contains(body, "[") && !contains(body, "]") && !contains(body, "!"), "a64 mops: expected plain X register")
    }
    const reg: list = a64_reg(trim(body))
    assert(list.get(reg, 0) == 3, "a64 mops: MOPS registers must be 64-bit X registers")
    return reg
}

fn a64_mops_operands(args: list, shape: string) -> list {
    let parsed: list = list.new()
    if shape == "setgo" {
        assert(len(args) == 2, "a64 mops: SETGO expects two operands")
        list.push_mut(parsed, a64_mops_one(list.get(args, 0), "bracketed_writeback"))
        list.push_mut(parsed, a64_mops_one(list.get(args, 1), "writeback"))
    } else if shape == "set" {
        assert(len(args) == 3, "a64 mops: SET expects three operands")
        list.push_mut(parsed, a64_mops_one(list.get(args, 0), "bracketed_writeback"))
        list.push_mut(parsed, a64_mops_one(list.get(args, 1), "writeback"))
        list.push_mut(parsed, a64_mops_one(list.get(args, 2), "plain"))
    } else {
        assert(shape == "cpy", "a64 mops: invalid instruction shape")
        assert(len(args) == 3, "a64 mops: CPY expects three operands")
        list.push_mut(parsed, a64_mops_one(list.get(args, 0), "bracketed_writeback"))
        list.push_mut(parsed, a64_mops_one(list.get(args, 1), "bracketed_writeback"))
        list.push_mut(parsed, a64_mops_one(list.get(args, 2), "writeback"))
    }
    return parsed
}
