// A64 logical immediate (N:R:S bitmask) encoder.
//
// Part 1 pins representative encodings against LLVM MC fixtures, including the
// wrapped-run case and the 16-bit-periodic case. Part 2 exhaustively round
// trips the complete legal encoding space: every (esize, S, R) triple with
// S != esize-1 is decoded to its pattern and re-encoded in both the X and
// (when 32-bit periodic) W forms.
import("arm/arm64.inc");

insn_orr_w_3ff:
arm64_orr_imm(arm64_w9, arm64_w10, 0x3ff)

insn_orr_w_ffff0000:
arm64_orr_imm(arm64_w3, arm64_w9, 0xffff0000)

insn_and_w_80008000:
arm64_and_imm(arm64_w14, arm64_w15, 0x80008000)

insn_and_w_ffc3ffc3:
arm64_and_imm(arm64_w12, arm64_w13, 0xffc3ffc3)

insn_eor_w_e0e0e0e0:
arm64_eor_imm(arm64_w3, arm64_w6, 0xe0e0e0e0)

insn_eor_w_81818181:
arm64_eor_imm(arm64_w16, arm64_w17, 0x81818181)

insn_orr_x_ff:
arm64_orr_imm(arm64_x0, arm64_x1, 0xff)

insn_ands_x_ffff:
arm64_ands_imm(arm64_x0, arm64_x1, 0xffff)

insn_eor_x_ff00:
arm64_eor_imm(arm64_x0, arm64_x1, 0xff00)

insn_bic_x_ff:
arm64_bic_imm(arm64_x0, arm64_x1, 0xff)

// Exhaustive round trip over the whole architectural encoding space: every
// (N, imms, immr) triple minus the reserved ones (len < 1 for N=0 with
// imms >= 62; S == levels produces an all-ones element and is skipped after
// decode). Each encoding is decoded to its pattern and the encoder must
// return an encoding that decodes back to the same pattern.
let n: u64 = 0
let checked: u64 = 0
while n <= 1 {
    let imms: u64 = 0
    while imms < 64 {
        if !(n == 0 && imms >= 62) {
            let r: u64 = 0
            while r < 64 {
                const packed_bits: u64 = (n << 12) | (r << 6) | imms
                const pattern: u64 = arm64_logical_imm_pattern(packed_bits)
                if pattern != 0 && pattern != 0xffffffffffffffff {
                    assert(pattern != 0, "decode produced zero");
                    const back: u64 = arm64_logical_imm(pattern, true)
                    const back_pattern: u64 = arm64_logical_imm_pattern(back)
                    assert(back_pattern == pattern, "logical immediate round trip X");
                    checked = checked + 1
                    if (pattern >> 32) == (pattern & 0xffffffff) {
                        const back_w: u64 = arm64_logical_imm(pattern & 0xffffffff, false)
                        const back_w_pattern: u64 = arm64_logical_imm_pattern(back_w)
                        assert(back_w_pattern == pattern, "logical immediate round trip W");
                        checked = checked + 1
                    }
                }
                r = r + 1
            }
        }
        imms = imms + 1
    }
    n = n + 1
}
print("logical immediate round trips", checked);

defer {
    assert(load.u32(insn_orr_w_3ff) == 0x32002549, "orr w9, w10, #0x3ff");
    assert(load.u32(insn_orr_w_ffff0000) == 0x32103d23, "orr w3, w9, #0xffff0000");
    assert(load.u32(insn_and_w_80008000) == 0x120181ee, "and w14, w15, #0x80008000");
    assert(load.u32(insn_and_w_ffc3ffc3) == 0x120aadac, "and w12, w13, #0xffc3ffc3");
    assert(load.u32(insn_eor_w_e0e0e0e0) == 0x5203c8c3, "eor w3, w6, #0xe0e0e0e0");
    assert(load.u32(insn_eor_w_81818181) == 0x5201c630, "eor w16, w17, #0x81818181");
    assert(load.u32(insn_orr_x_ff) == 0xb2401c20, "orr x0, x1, #0xff");
    assert(load.u32(insn_ands_x_ffff) == 0xf2403c20, "ands x0, x1, #0xffff");
    assert(load.u32(insn_eor_x_ff00) == 0xd2781c20, "eor x0, x1, #0xff00");
    assert(load.u32(insn_bic_x_ff) == 0x9278dc20, "bic x0, x1, #0xff");
}
