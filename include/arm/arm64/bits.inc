// A64 bit math: field fitting, rotation, popcount, and the logical-immediate
// (N:R:S) codec. Pure value functions; no emission.

// Internal: assert that an unsigned value fits a field of `bits` bits and
// return it unchanged for use in bit packing.
fn arm64_fit(value: u64, bits: u64, name: string) -> u64 {
    assert(value < (1 << bits), sym.join(name, " does not fit its field width"));
    return value;
}

// Internal: 64-bit rotate right, amount must be 0..63. The masked shift form
// keeps every intermediate value inside u64 (Meta arithmetic is checked).
fn arm64_ror64(value: u64, amount: u64) -> u64 {
    assert(amount < 64, "internal: ror64 amount out of range");
    if amount == 0 {
        return value;
    }
    return (value >> amount) | ((value & ((1 << amount) - 1)) << (64 - amount));
}

fn arm64_popcount64(value: u64) -> u64 {
    let v: u64 = value
    let count: u64 = 0
    while v != 0 {
        count = count + (v & 1)
        v = v >> 1
    }
    return count;
}

// Internal: encode a bitmask immediate for the logical (immediate) group.
// Returns N<<12 | immr<<6 | imms, or fails when the value is not encodable.
//
// Method: replicate the W form to 64 bits, take the smallest power-of-two
// period as the element size, rotate the element until its ones-run sits at
// bit 0, then imms = (64 - 2*esize) | (ones-1) (computed via the complement so
// the esize=64 case never underflows) and immr = (esize - rotate) mod esize.
//
// Fixtures: llvm/test/MC/AArch64/basic-a64-instructions.s
//   orr w9, w10, #0x3ff       -> [49 25 00 32]  (esize 32, ones 10, R 0, S 9)
//   orr w3, w9, #0xffff0000   -> [23 3d 10 32]  (esize 32, ones 16, R 16, S 15)
//   and w14, w15, #0x80008000 -> [ee 81 01 12]  (esize 16, ones 1, R 1, S 32)
//   and w12, w13, #0xffc3ffc3 -> [ac ad 0a 12]  (esize 16, ones 12, R 10, S 43)
//   eor w3, w6, #0xe0e0e0e0   -> [c3 c8 03 52]  (esize 8, ones 12, R 3, S 50)
fn arm64_logical_imm(value: u64, is64: bool) -> u64 {
    let v: u64 = value
    if !is64 {
        assert(value < (1 << 32), "logical immediate: W form requires value < 2^32");
        v = value | (value << 32)
    }
    assert(v != 0 && v != 0xffffffffffffffff, "logical immediate cannot be 0 or all ones");
    let esize: u64 = 64
    let p: u64 = 2
    while p < 64 {
        if esize == 64 {
            if arm64_ror64(v, p) == v {
                esize = p
            }
        }
        p = p * 2
    }
    let mask: u64 = 0xffffffffffffffff
    if esize != 64 {
        mask = (1 << esize) - 1
    }
    const elem: u64 = v & mask
    const ones: u64 = arm64_popcount64(elem)
    const run: u64 = (1 << ones) - 1
    let r: u64 = 0
    let t: u64 = elem
    while t != run {
        assert(r < esize, "value is not a valid A64 logical immediate");
        const low: u64 = t & 1
        t = (t >> 1) | (low << (esize - 1))
        r = r + 1
    }
    const n: u64 = esize / 64
    const imms: u64 = ((~(2 * esize - 1)) & 0x3f) | (ones - 1)
    const immr: u64 = (esize - r) % esize
    return (n << 12) | (immr << 6) | imms;
}

// Internal: decode a packed logical-immediate (N<<12 | immr<<6 | imms) into its
// 64-bit bitmask pattern, following the ARM ARM DecodeBitMasks pseudocode.
// len = HighestSetBit(N:NOT(imms)) is the zero-based index of the highest set
// bit across all seven bits; esize = 2^len. Used by the exhaustive round-trip
// test (tests/isa/arm/arm64-m2-logical-imm.asm).
fn arm64_logical_imm_pattern(packed: u64) -> u64 {
    const n: u64 = (packed >> 12) & 1
    const immr: u64 = (packed >> 6) & 0x3f
    const imms: u64 = packed & 0x3f
    const immenc: u64 = (n << 6) | ((~imms) & 0x3f)
    let len: u64 = 0
    let bit: u64 = 7
    while bit > 0 {
        bit = bit - 1
        if len == 0 {
            if ((immenc >> bit) & 1) == 1 {
                len = bit
            }
        }
    }
    assert(len >= 1, "internal: logical immediate decode len");
    const levels: u64 = (1 << len) - 1
    const s: u64 = imms & levels
    // Reserved logical immediate: S == levels (element would be all ones).
    // Return the 0 sentinel before computing 1 << (s + 1), which for
    // esize == 64 would be a checked shift overflow.
    if s == levels {
        return 0;
    }
    const r: u64 = immr & levels
    const esize: u64 = 1 << len
    let mask: u64 = 0xffffffffffffffff
    if esize != 64 {
        mask = (1 << esize) - 1
    }
    let welem: u64 = ((1 << (s + 1)) - 1) & mask
    let w: u64 = welem
    if r != 0 {
        w = ((welem >> r) | ((welem & ((1 << r) - 1)) << (esize - r))) & mask
    }
    let out: u64 = w
    let pos: u64 = esize
    while pos < 64 {
        out = out | (w << pos)
        pos = pos + esize
    }
    return out;
}
