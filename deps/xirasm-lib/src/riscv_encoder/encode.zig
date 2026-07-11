const std = @import("std");
const types = @import("types.zig");

pub fn encode(request: types.EncodeRequest, spec: *const types.InstructionSpec) types.EncodeError!types.EncodedInstruction {
    return encodeWithMode(request, spec, .semantic);
}

pub fn encodeRaw(request: types.EncodeRequest, spec: *const types.InstructionSpec) types.EncodeError!types.EncodedInstruction {
    return encodeWithMode(request, spec, .raw);
}

const EncodeMode = enum {
    semantic,
    raw,
};

fn encodeWithMode(request: types.EncodeRequest, spec: *const types.InstructionSpec, mode: EncodeMode) types.EncodeError!types.EncodedInstruction {
    if (request.xlen != 32 and request.xlen != 64) return error.InvalidXLen;
    if (request.xlen < spec.min_xlen) return error.UnsupportedXLen;
    if (request.xlen > spec.max_xlen) return error.UnsupportedXLen;
    if (spec.bit_width != 16 and spec.bit_width != 32) return error.UnsupportedInstructionWidth;

    const word = switch (mode) {
        .semantic => try encodeWord(spec, request.operands),
        .raw => try encodeRawWord(spec, request.operands),
    };
    const len: u8 = switch (spec.bit_width) {
        16 => 2,
        32 => 4,
        else => return error.UnsupportedInstructionWidth,
    };
    return .{
        .word = word,
        .bytes = .{
            @intCast(word & 0xff),
            @intCast((word >> 8) & 0xff),
            @intCast((word >> 16) & 0xff),
            @intCast((word >> 24) & 0xff),
        },
        .len = len,
    };
}

fn encodeWord(spec: *const types.InstructionSpec, operands: []const types.Operand) types.EncodeError!u32 {
    if (spec.semantic == .raw) return encodeRawWord(spec, operands);
    const values = try semanticFieldValues(spec, operands);
    var word = spec.match;
    for (spec.fields) |field| {
        const value = try fieldValue(values, field.name);
        word |= try packField(field, value);
    }
    return word;
}

const FieldValues = struct {
    rd: u32 = 0,
    rs1: u32 = 0,
    rs2: u32 = 0,
    rs3: u32 = 0,
    vd: u32 = 0,
    vs1: u32 = 0,
    vs2: u32 = 0,
    vs3: u32 = 0,
    csr: u32 = 0,
    fm: u32 = 0,
    pred: u32 = 0,
    succ: u32 = 0,
    rm: u32 = 0,
    vm: u32 = 0,
    nf: u32 = 0,
    imm12: u32 = 0,
    imm12hi: u32 = 0,
    imm12lo: u32 = 0,
    bimm12hi: u32 = 0,
    bimm12lo: u32 = 0,
    imm20: u32 = 0,
    jimm20: u32 = 0,
    simm5: u32 = 0,
    zimm5: u32 = 0,
    zimm6hi: u32 = 0,
    zimm6lo: u32 = 0,
    zimm10: u32 = 0,
    zimm11: u32 = 0,
    imm5: u32 = 0,
    shamtw: u32 = 0,
    shamtd: u32 = 0,
    aq: u32 = 0,
    rl: u32 = 0,
    bs: u32 = 0,
    rnum: u32 = 0,
    uimm: u32 = 0,
    p_rd_p: u32 = 0,
    p_rs1_p: u32 = 0,
    p_rs2_p: u32 = 0,
    rs2_e: u32 = 0,
    mop_r_t_30: u32 = 0,
    mop_r_t_27_26: u32 = 0,
    mop_r_t_21_20: u32 = 0,
    mop_rr_t_30: u32 = 0,
    mop_rr_t_27_26: u32 = 0,
    c_rd: u32 = 0,
    c_rs1: u32 = 0,
    c_rs2: u32 = 0,
    c_imm12: u32 = 0,
    c_imm6hi: u32 = 0,
    c_imm6lo: u32 = 0,
    c_bimm9hi: u32 = 0,
    c_bimm9lo: u32 = 0,
    c_nzimm10hi: u32 = 0,
    c_nzimm10lo: u32 = 0,
    c_nzimm18hi: u32 = 0,
    c_nzimm18lo: u32 = 0,
    c_nzuimm10: u32 = 0,
    c_uimm1: u32 = 0,
    c_uimm2: u32 = 0,
    c_uimm7hi: u32 = 0,
    c_uimm7lo: u32 = 0,
    c_uimm8hi: u32 = 0,
    c_uimm8lo: u32 = 0,
    c_uimm8sp_s: u32 = 0,
    c_uimm8sphi: u32 = 0,
    c_uimm8splo: u32 = 0,
    c_uimm9sp_s: u32 = 0,
    c_uimm9sphi: u32 = 0,
    c_uimm9splo: u32 = 0,
    c_uimm6hi: u32 = 0,
    c_uimm6lo: u32 = 0,
    c_uimm5: u32 = 0,
    c_mop_t: u32 = 0,
    c_rlist: u32 = 0,
    c_spimm: u32 = 0,
    c_sreg1: u32 = 0,
    c_sreg2: u32 = 0,
    c_index: u32 = 0,
};

fn encodeRawWord(spec: *const types.InstructionSpec, operands: []const types.Operand) types.EncodeError!u32 {
    try expectOperandCount(operands, spec.fields.len);
    var word = spec.match;
    for (spec.fields, 0..) |field, index| {
        word |= try packField(field, try readRawField(operands[index]));
    }
    return word;
}

fn semanticFieldValues(spec: *const types.InstructionSpec, operands: []const types.Operand) types.EncodeError!FieldValues {
    return switch (spec.semantic) {
        .raw => error.UnsupportedInstruction,
        .none => blk: {
            try expectOperandCount(operands, 0);
            break :blk .{};
        },
        .rd => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .rd = try readReg(operands[0]) };
        },
        .rd_n0 => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .rd = try readNonZeroReg(operands[0]) };
        },
        .rs1 => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .rs1 = try readReg(operands[0]) };
        },
        .rd_rs1 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
            };
        },
        .rd_rs2 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
            };
        },
        .rd_rs1_rs2 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
            };
        },
        .rd_rs1_imm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .imm12 = try wrapSigned(try readImm(operands[2]), 12),
            };
        },
        .rd_even_rs1_imm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try evenRegValue(try readReg(operands[0])),
                .rs1 = try readReg(operands[1]),
                .imm12 = try wrapSigned(try readImm(operands[2]), 12),
            };
        },
        .rd_rs1_shamt => blk: {
            try expectOperandCount(operands, 3);
            const shamt = try unsignedRange(try readImm(operands[2]), try shamtBits(spec));
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .shamtw = shamt,
                .shamtd = shamt,
            };
        },
        .rd_rs1_csr => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .csr = try unsignedRange(try readImm(operands[1]), 12),
                .rs1 = try readReg(operands[2]),
            };
        },
        .rd_zimm_csr => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .csr = try unsignedRange(try readImm(operands[1]), 12),
                .zimm5 = try unsignedRange(try readImm(operands[2]), 5),
            };
        },
        .rd_csr => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .csr = try unsignedRange(try readImm(operands[1]), 12),
            };
        },
        .rs1_csr => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .csr = try unsignedRange(try readImm(operands[0]), 12),
                .rs1 = try readReg(operands[1]),
            };
        },
        .zimm_csr => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .csr = try unsignedRange(try readImm(operands[0]), 12),
                .zimm5 = try unsignedRange(try readImm(operands[1]), 5),
            };
        },
        .rd_zimm => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .zimm5 = try unsignedRange(try readImm(operands[1]), 5),
            };
        },
        .rd_rs1_rm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rm = try unsignedRange(try readImm(operands[2]), 3),
            };
        },
        .rd_rs1_rs2_rm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .rm = try unsignedRange(try readImm(operands[3]), 3),
            };
        },
        .rd_rs1_rs2_rs3_rm => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .rs3 = try readReg(operands[3]),
                .rm = try unsignedRange(try readImm(operands[4]), 3),
            };
        },
        .rd_rs1_rs2_bs => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .bs = try unsignedRange(try readImm(operands[3]), try fieldBits(spec, "bs")),
            };
        },
        .rd_rs1_rnum => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rnum = try unsignedRange(try readImm(operands[2]), try fieldBits(spec, "rnum")),
            };
        },
        .rd_rs1_uimm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .uimm = try unsignedRange(try readImm(operands[2]), try pUimmBits(spec)),
            };
        },
        .rd_uimm => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .uimm = try unsignedRange(try readImm(operands[1]), try pUimmBits(spec)),
            };
        },
        .rd_rs1_rl => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rl = try unsignedRange(try readImm(operands[2]), 1),
            };
        },
        .rs1_rs2_aq => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
                .aq = try unsignedRange(try readImm(operands[2]), 1),
            };
        },
        .rs2_imm_rs1 => blk: {
            try expectOperandCount(operands, 3);
            const imm = try wrapSigned(try readImm(operands[1]), 12);
            break :blk .{
                .rs2 = try readReg(operands[0]),
                .rs1 = try readReg(operands[2]),
                .imm12hi = imm >> 5,
                .imm12lo = imm & 0x1f,
            };
        },
        .rs1_rs2 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
            };
        },
        .rs1_rs2_offset => blk: {
            try expectOperandCount(operands, 3);
            const imm = try wrapAlignedSigned(try readImm(operands[2]), 13, 2);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
                .bimm12hi = (((imm >> 12) & 0x1) << 6) | ((imm >> 5) & 0x3f),
                .bimm12lo = (((imm >> 1) & 0xf) << 1) | ((imm >> 11) & 0x1),
            };
        },
        .rs1_offset => blk: {
            try expectOperandCount(operands, 2);
            const imm = try wrapAlignedSigned(try readImm(operands[1]), 13, 2);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .bimm12hi = (((imm >> 12) & 0x1) << 6) | ((imm >> 5) & 0x3f),
                .bimm12lo = (((imm >> 1) & 0xf) << 1) | ((imm >> 11) & 0x1),
            };
        },
        .rs2_rs1_offset => blk: {
            try expectOperandCount(operands, 3);
            const imm = try wrapAlignedSigned(try readImm(operands[2]), 13, 2);
            break :blk .{
                .rs2 = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .bimm12hi = (((imm >> 12) & 0x1) << 6) | ((imm >> 5) & 0x3f),
                .bimm12lo = (((imm >> 1) & 0xf) << 1) | ((imm >> 11) & 0x1),
            };
        },
        .rs2_offset => blk: {
            try expectOperandCount(operands, 2);
            const imm = try wrapAlignedSigned(try readImm(operands[1]), 13, 2);
            break :blk .{
                .rs2 = try readReg(operands[0]),
                .bimm12hi = (((imm >> 12) & 0x1) << 6) | ((imm >> 5) & 0x3f),
                .bimm12lo = (((imm >> 1) & 0xf) << 1) | ((imm >> 11) & 0x1),
            };
        },
        .rs1_imm5_offset => blk: {
            try expectOperandCount(operands, 3);
            const imm = try wrapAlignedSigned(try readImm(operands[2]), 13, 2);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .imm5 = try unsignedRange(try readImm(operands[1]), 5),
                .imm12hi = (((imm >> 12) & 0x1) << 6) | ((imm >> 5) & 0x3f),
                .imm12lo = (((imm >> 1) & 0xf) << 1) | ((imm >> 11) & 0x1),
            };
        },
        .rd_imm20 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .imm20 = try unsignedRange(try readImm(operands[1]), 20),
            };
        },
        .imm20 => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .imm20 = try unsignedRange(try readImm(operands[0]), 20) };
        },
        .rd_offset => blk: {
            try expectOperandCount(operands, 2);
            const imm = try wrapAlignedSigned(try readImm(operands[1]), 21, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .jimm20 = (((imm >> 20) & 0x1) << 19) |
                    (((imm >> 1) & 0x3ff) << 9) |
                    (((imm >> 11) & 0x1) << 8) |
                    ((imm >> 12) & 0xff),
            };
        },
        .offset => blk: {
            try expectOperandCount(operands, 1);
            const imm = try wrapAlignedSigned(try readImm(operands[0]), 21, 2);
            break :blk .{
                .jimm20 = (((imm >> 20) & 0x1) << 19) |
                    (((imm >> 1) & 0x3ff) << 9) |
                    (((imm >> 11) & 0x1) << 8) |
                    ((imm >> 12) & 0xff),
            };
        },
        .fence => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .pred = try unsignedRange(try readImm(operands[0]), 4),
                .succ = try unsignedRange(try readImm(operands[1]), 4),
            };
        },
        .amo => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
                .rs1 = try readReg(operands[2]),
                .aq = try unsignedRange(try readImm(operands[3]), 1),
                .rl = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .lr => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .aq = try unsignedRange(try readImm(operands[2]), 1),
                .rl = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .sc => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs2 = try readReg(operands[1]),
                .rs1 = try readReg(operands[2]),
                .aq = try unsignedRange(try readImm(operands[3]), 1),
                .rl = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .vd_vs2_vs1_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .vs1 = try readReg(operands[2]),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vd_vs2_rs1_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .rs1 = try readReg(operands[2]),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vd_vs2_vm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .vm = try unsignedRange(try readImm(operands[2]), 1),
            };
        },
        .vd_rs1 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
            };
        },
        .vd_vs2_vs1 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .vs1 = try readReg(operands[2]),
            };
        },
        .vd_vs2 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
            };
        },
        .vd_vs2_simm5_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .simm5 = try wrapSigned(try readImm(operands[2]), 5),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vd_vs2_zimm5_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .zimm5 = try unsignedRange(try readImm(operands[2]), 5),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vd_vs2_simm5 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .simm5 = try wrapSigned(try readImm(operands[2]), 5),
            };
        },
        .vd_vs2_zimm5 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .zimm5 = try unsignedRange(try readImm(operands[2]), 5),
            };
        },
        .rd_vs2_vm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .vm = try unsignedRange(try readImm(operands[2]), 1),
            };
        },
        .rd_vs2 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .rd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
            };
        },
        .rd_rs1_zimm11 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .zimm11 = try unsignedRange(try readImm(operands[2]), 11),
            };
        },
        .rd_zimm5_zimm10 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .zimm5 = try unsignedRange(try readImm(operands[1]), 5),
                .zimm10 = try unsignedRange(try readImm(operands[2]), 10),
            };
        },
        .vd_vm => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vm = try unsignedRange(try readImm(operands[1]), 1),
            };
        },
        .vd_vs1 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs1 = try readReg(operands[1]),
            };
        },
        .vd_simm5 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vd = try readReg(operands[0]),
                .simm5 = try wrapSigned(try readImm(operands[1]), 5),
            };
        },
        .vd_rs1_nf_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .nf = try unsignedRange(try readImm(operands[2]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vs3_rs1_nf_vm => blk: {
            try expectOperandCount(operands, 4);
            break :blk .{
                .vs3 = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .nf = try unsignedRange(try readImm(operands[2]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .vd_rs1_vs2_nf_vm => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .vd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .vs2 = try readReg(operands[2]),
                .nf = try unsignedRange(try readImm(operands[3]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .vs3_rs1_vs2_nf_vm => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .vs3 = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .vs2 = try readReg(operands[2]),
                .nf = try unsignedRange(try readImm(operands[3]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .vd_rs1_rs2_nf_vm => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .vd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .nf = try unsignedRange(try readImm(operands[3]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .vs3_rs1_rs2_nf_vm => blk: {
            try expectOperandCount(operands, 5);
            break :blk .{
                .vs3 = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .nf = try unsignedRange(try readImm(operands[3]), try fieldBits(spec, "nf")),
                .vm = try unsignedRange(try readImm(operands[4]), 1),
            };
        },
        .vs3_rs1 => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .vs3 = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
            };
        },
        .vd_vs2_rs1 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .rs1 = try readReg(operands[2]),
            };
        },
        .vd_vs2_zimm6_vm => blk: {
            try expectOperandCount(operands, 4);
            const zimm6 = try unsignedRange(try readImm(operands[2]), 6);
            break :blk .{
                .vd = try readReg(operands[0]),
                .vs2 = try readReg(operands[1]),
                .zimm6hi = (zimm6 >> 5) & 0x1,
                .zimm6lo = zimm6 & 0x1f,
                .vm = try unsignedRange(try readImm(operands[3]), 1),
            };
        },
        .c_none => blk: {
            try expectOperandCount(operands, 0);
            break :blk .{};
        },
        .c_mop_t => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .c_mop_t = try unsignedRange(try readImm(operands[0]), 3) };
        },
        .c_rs1 => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .rs1 = try readNonZeroReg(operands[0]) };
        },
        .c_rd => blk: {
            try expectOperandCount(operands, 1);
            const rd = try readReg(operands[0]);
            break :blk .{
                .rd = rd,
                .c_rd = try compressedRegValue(rd),
            };
        },
        .c_rd_rs2 => blk: {
            try expectOperandCount(operands, 2);
            const rd = try readReg(operands[0]);
            const rs2 = try readReg(operands[1]);
            break :blk .{
                .rd = try nonZeroRegValue(rd),
                .rs2 = try nonZeroRegValue(rs2),
            };
        },
        .c_rd_p_rs2_p => blk: {
            try expectOperandCount(operands, 2);
            const rd = try readReg(operands[0]);
            const rs2 = try readReg(operands[1]);
            break :blk .{
                .c_rd = try compressedRegValue(rd),
                .c_rs2 = try compressedRegValue(rs2),
            };
        },
        .c_rd_imm6 => blk: {
            try expectOperandCount(operands, 2);
            const rd = try readReg(operands[0]);
            const imm = try wrapSigned(try readImm(operands[1]), 6);
            break :blk .{
                .rd = try nonZeroRegValue(rd),
                .c_rd = try compressedRegValue(rd),
                .c_imm6hi = (imm >> 5) & 0x1,
                .c_imm6lo = imm & 0x1f,
            };
        },
        .c_imm6 => blk: {
            try expectOperandCount(operands, 1);
            const imm = try wrapSigned(try readImm(operands[0]), 6);
            break :blk .{
                .c_imm6hi = (imm >> 5) & 0x1,
                .c_imm6lo = imm & 0x1f,
            };
        },
        .c_rd_uimm6 => blk: {
            try expectOperandCount(operands, 2);
            const rd = try readReg(operands[0]);
            const imm = try unsignedRange(try readImm(operands[1]), try cUimmBits(spec));
            break :blk .{
                .rd = try nonZeroRegValue(rd),
                .c_rd = try compressedRegValue(rd),
                .c_uimm6hi = (imm >> 5) & 0x1,
                .c_uimm6lo = imm & 0x1f,
                .c_uimm5 = imm & 0x1f,
            };
        },
        .c_rd_p_rs1_p_uimm => blk: {
            try expectOperandCount(operands, 3);
            const offset = try readImm(operands[1]);
            break :blk fillCompressedOffset(spec, .{
                .c_rd = try compressedRegValue(try readReg(operands[0])),
                .c_rs1 = try compressedRegValue(try readReg(operands[2])),
            }, offset);
        },
        .c_rs1_p_rs2_p_uimm => blk: {
            try expectOperandCount(operands, 3);
            const offset = try readImm(operands[1]);
            break :blk fillCompressedOffset(spec, .{
                .c_rs2 = try compressedRegValue(try readReg(operands[0])),
                .c_rs1 = try compressedRegValue(try readReg(operands[2])),
            }, offset);
        },
        .c_rd_sp_uimm => blk: {
            try expectOperandCount(operands, 2);
            const rd = try readReg(operands[0]);
            break :blk fillCompressedOffset(spec, .{ .rd = try nonZeroRegValue(rd) }, try readImm(operands[1]));
        },
        .c_rs2_sp_uimm => blk: {
            try expectOperandCount(operands, 2);
            break :blk fillCompressedOffset(spec, .{ .rs2 = try readReg(operands[0]) }, try readImm(operands[1]));
        },
        .c_offset => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .c_imm12 = try compressedJumpOffset(try readImm(operands[0])) };
        },
        .c_rs1_p_offset => blk: {
            try expectOperandCount(operands, 2);
            const offset = try compressedBranchOffset(try readImm(operands[1]));
            break :blk .{
                .c_rs1 = try compressedRegValue(try readReg(operands[0])),
                .c_bimm9hi = offset.hi,
                .c_bimm9lo = offset.lo,
            };
        },
        .c_addi16sp => blk: {
            try expectOperandCount(operands, 1);
            const encoded = try compressedAddi16spImmediate(try readImm(operands[0]));
            break :blk .{ .c_nzimm10hi = encoded.hi, .c_nzimm10lo = encoded.lo };
        },
        .c_rd_lui_imm => blk: {
            try expectOperandCount(operands, 2);
            const encoded = try compressedLuiImmediate(try readImm(operands[1]));
            break :blk .{
                .rd = try nonZeroNonSpRegValue(try readReg(operands[0])),
                .c_nzimm18hi = encoded.hi,
                .c_nzimm18lo = encoded.lo,
            };
        },
        .c_addi4spn => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .c_rd = try compressedRegValue(try readReg(operands[0])),
                .c_nzuimm10 = try compressedAddi4spnImmediate(try readImm(operands[1])),
            };
        },
        .c_rlist_spimm => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .c_rlist = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "c_rlist")),
                .c_spimm = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "c_spimm")),
            };
        },
        .c_sreg_sreg => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .c_sreg1 = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "c_sreg1")),
                .c_sreg2 = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "c_sreg2")),
            };
        },
        .c_index => blk: {
            try expectOperandCount(operands, 1);
            break :blk .{ .c_index = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "c_index")) };
        },
        .p_rd_p_rs1_p_rs2_p => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
                .p_rs2_p = try unsignedRange(try readImm(operands[2]), try fieldBits(spec, "p_rs2_p")),
            };
        },
        .p_rd_p_rs1_rs2 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
            };
        },
        .rd_p_rs1_p_rs2 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
                .rs2 = try readReg(operands[2]),
            };
        },
        .p_rd_p_rs1_p_rs2 => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
                .rs2 = try readReg(operands[2]),
            };
        },
        .p_rd_p_rs1_p_uimm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
                .uimm = try unsignedRange(try readImm(operands[2]), try pUimmBits(spec)),
            };
        },
        .rd_p_rs1_p_uimm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
                .uimm = try unsignedRange(try readImm(operands[2]), try pUimmBits(spec)),
            };
        },
        .p_rd_p_rs1_p => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .p_rs1_p = try unsignedRange(try readImm(operands[1]), try fieldBits(spec, "p_rs1_p")),
            };
        },
        .p_rd_p_rs1_uimm => blk: {
            try expectOperandCount(operands, 3);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .rs1 = try readReg(operands[1]),
                .uimm = try unsignedRange(try readImm(operands[2]), try pUimmBits(spec)),
            };
        },
        .p_rd_p_uimm => blk: {
            try expectOperandCount(operands, 2);
            break :blk .{
                .p_rd_p = try unsignedRange(try readImm(operands[0]), try fieldBits(spec, "p_rd_p")),
                .uimm = try unsignedRange(try readImm(operands[1]), try pUimmBits(spec)),
            };
        },
        .rs1_prefetch_offset => blk: {
            try expectOperandCount(operands, 2);
            const imm = try wrapAlignedSigned(try readImm(operands[1]), 12, 32);
            break :blk .{
                .rs1 = try readReg(operands[0]),
                .imm12hi = (imm >> 5) & 0x7f,
            };
        },
        .mop_r_n => blk: {
            try expectOperandCount(operands, 3);
            const mop = try unsignedRange(try readImm(operands[2]), 5);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .mop_r_t_30 = bit(mop, 4),
                .mop_r_t_27_26 = (bit(mop, 3) << 1) | bit(mop, 2),
                .mop_r_t_21_20 = mop & 0x3,
            };
        },
        .mop_rr_n => blk: {
            try expectOperandCount(operands, 4);
            const mop = try unsignedRange(try readImm(operands[3]), 3);
            break :blk .{
                .rd = try readReg(operands[0]),
                .rs1 = try readReg(operands[1]),
                .rs2 = try readReg(operands[2]),
                .mop_rr_t_30 = bit(mop, 2),
                .mop_rr_t_27_26 = (bit(mop, 1) << 1) | bit(mop, 0),
            };
        },
        .rd_pair_rs1_imm => blk: {
            try expectOperandCount(operands, 3);
            const imm = try wrapAlignedSigned(try readImm(operands[2]), 12, 2);
            break :blk .{
                .imm12lo = try evenRegValue(try readReg(operands[0])),
                .rs1 = try readReg(operands[1]),
                .rs2_e = (imm >> 1) & 0xf,
                .imm12hi = (imm >> 5) & 0x7f,
            };
        },
    };
}

fn shamtBits(spec: *const types.InstructionSpec) types.EncodeError!u6 {
    return fieldBits(spec, "shamtw") catch fieldBits(spec, "shamtd");
}

fn fieldBits(spec: *const types.InstructionSpec, comptime name: []const u8) types.EncodeError!u6 {
    for (spec.fields) |field| {
        if (fieldName(field.name, name)) return field.width;
    }
    return error.UnsupportedInstruction;
}

fn hasField(spec: *const types.InstructionSpec, comptime name: []const u8) bool {
    for (spec.fields) |field| {
        if (fieldName(field.name, name)) return true;
    }
    return false;
}

fn pUimmBits(spec: *const types.InstructionSpec) types.EncodeError!u6 {
    for (spec.fields) |field| {
        if (pUimmField(field.name)) return field.width;
    }
    return error.UnsupportedInstruction;
}

fn fieldValue(values: FieldValues, name: []const u8) types.EncodeError!u32 {
    if (fieldAliasSource(name)) |alias_source| return fieldValue(values, alias_source);
    if (fieldName(name, "rd")) return values.rd;
    if (fieldName(name, "rs1")) return values.rs1;
    if (fieldName(name, "rs2")) return values.rs2;
    if (fieldName(name, "rs3")) return values.rs3;
    if (fieldName(name, "vd")) return values.vd;
    if (fieldName(name, "vs1")) return values.vs1;
    if (fieldName(name, "vs2")) return values.vs2;
    if (fieldName(name, "vs3")) return values.vs3;
    if (fieldName(name, "csr")) return values.csr;
    if (fieldName(name, "fm")) return values.fm;
    if (fieldName(name, "pred")) return values.pred;
    if (fieldName(name, "succ")) return values.succ;
    if (fieldName(name, "rm")) return values.rm;
    if (fieldName(name, "vm")) return values.vm;
    if (fieldName(name, "nf")) return values.nf;
    if (fieldName(name, "imm12")) return values.imm12;
    if (fieldName(name, "imm12hi")) return values.imm12hi;
    if (fieldName(name, "imm12lo")) return values.imm12lo;
    if (fieldName(name, "bimm12hi")) return values.bimm12hi;
    if (fieldName(name, "bimm12lo")) return values.bimm12lo;
    if (fieldName(name, "imm20")) return values.imm20;
    if (fieldName(name, "jimm20")) return values.jimm20;
    if (fieldName(name, "simm5")) return values.simm5;
    if (fieldName(name, "zimm5")) return values.zimm5;
    if (fieldName(name, "zimm6hi")) return values.zimm6hi;
    if (fieldName(name, "zimm6lo")) return values.zimm6lo;
    if (fieldName(name, "zimm10")) return values.zimm10;
    if (fieldName(name, "zimm11")) return values.zimm11;
    if (fieldName(name, "imm5")) return values.imm5;
    if (fieldName(name, "shamtw")) return values.shamtw;
    if (fieldName(name, "shamtd")) return values.shamtd;
    if (fieldName(name, "aq")) return values.aq;
    if (fieldName(name, "rl")) return values.rl;
    if (fieldName(name, "bs")) return values.bs;
    if (fieldName(name, "rnum")) return values.rnum;
    if (pUimmField(name)) return values.uimm;
    if (fieldName(name, "p_rd_p")) return values.p_rd_p;
    if (fieldName(name, "p_rs1_p")) return values.p_rs1_p;
    if (fieldName(name, "p_rs2_p")) return values.p_rs2_p;
    if (fieldName(name, "rs2_e")) return values.rs2_e;
    if (fieldName(name, "mop_r_t_30")) return values.mop_r_t_30;
    if (fieldName(name, "mop_r_t_27_26")) return values.mop_r_t_27_26;
    if (fieldName(name, "mop_r_t_21_20")) return values.mop_r_t_21_20;
    if (fieldName(name, "mop_rr_t_30")) return values.mop_rr_t_30;
    if (fieldName(name, "mop_rr_t_27_26")) return values.mop_rr_t_27_26;
    if (fieldName(name, "rd_p")) return values.c_rd;
    if (fieldName(name, "rs1_p")) return values.c_rs1;
    if (fieldName(name, "rs2_p")) return values.c_rs2;
    if (fieldName(name, "rd_rs1_p")) return values.c_rd;
    if (fieldName(name, "rd_rs1_n0")) return values.rd;
    if (fieldName(name, "rd_n0")) return values.rd;
    if (fieldName(name, "rd_n2")) return values.rd;
    if (fieldName(name, "rs1_n0")) return values.rs1;
    if (fieldName(name, "c_rs1_n0")) return values.rs1;
    if (fieldName(name, "c_rs2_n0")) return values.rs2;
    if (fieldName(name, "c_rs2")) return values.rs2;
    if (fieldName(name, "c_imm12")) return values.c_imm12;
    if (fieldName(name, "c_nzimm6hi")) return values.c_imm6hi;
    if (fieldName(name, "c_nzimm6lo")) return values.c_imm6lo;
    if (fieldName(name, "c_imm6hi")) return values.c_imm6hi;
    if (fieldName(name, "c_imm6lo")) return values.c_imm6lo;
    if (fieldName(name, "c_bimm9hi")) return values.c_bimm9hi;
    if (fieldName(name, "c_bimm9lo")) return values.c_bimm9lo;
    if (fieldName(name, "c_nzimm10hi")) return values.c_nzimm10hi;
    if (fieldName(name, "c_nzimm10lo")) return values.c_nzimm10lo;
    if (fieldName(name, "c_nzimm18hi")) return values.c_nzimm18hi;
    if (fieldName(name, "c_nzimm18lo")) return values.c_nzimm18lo;
    if (fieldName(name, "c_nzuimm10")) return values.c_nzuimm10;
    if (fieldName(name, "c_uimm1")) return values.c_uimm1;
    if (fieldName(name, "c_uimm2")) return values.c_uimm2;
    if (fieldName(name, "c_uimm7hi")) return values.c_uimm7hi;
    if (fieldName(name, "c_uimm7lo")) return values.c_uimm7lo;
    if (fieldName(name, "c_uimm8hi")) return values.c_uimm8hi;
    if (fieldName(name, "c_uimm8lo")) return values.c_uimm8lo;
    if (fieldName(name, "c_uimm8sp_s")) return values.c_uimm8sp_s;
    if (fieldName(name, "c_uimm8sphi")) return values.c_uimm8sphi;
    if (fieldName(name, "c_uimm8splo")) return values.c_uimm8splo;
    if (fieldName(name, "c_uimm9sp_s")) return values.c_uimm9sp_s;
    if (fieldName(name, "c_uimm9sphi")) return values.c_uimm9sphi;
    if (fieldName(name, "c_uimm9splo")) return values.c_uimm9splo;
    if (fieldName(name, "c_nzuimm6hi")) return values.c_uimm6hi;
    if (fieldName(name, "c_nzuimm6lo")) return values.c_uimm6lo;
    if (fieldName(name, "c_nzuimm5")) return values.c_uimm5;
    if (fieldName(name, "c_mop_t")) return values.c_mop_t;
    if (fieldName(name, "c_rlist")) return values.c_rlist;
    if (fieldName(name, "c_spimm")) return values.c_spimm;
    if (fieldName(name, "c_sreg1")) return values.c_sreg1;
    if (fieldName(name, "c_sreg2")) return values.c_sreg2;
    if (fieldName(name, "c_index")) return values.c_index;
    return error.UnsupportedInstruction;
}

fn expectOperandCount(operands: []const types.Operand, expected: usize) types.EncodeError!void {
    if (operands.len != expected) return error.OperandCountMismatch;
}

fn readReg(operand: types.Operand) types.EncodeError!u32 {
    return switch (operand) {
        .reg => |value| value,
        .imm => error.OperandKindMismatch,
    };
}

fn readImm(operand: types.Operand) types.EncodeError!i64 {
    return switch (operand) {
        .imm => |value| value,
        .reg => error.OperandKindMismatch,
    };
}

fn readRawField(operand: types.Operand) types.EncodeError!u32 {
    return switch (operand) {
        .reg => |value| value,
        .imm => |value| blk: {
            if (value < 0) return error.ImmediateOutOfRange;
            if (value > std.math.maxInt(u32)) return error.ImmediateOutOfRange;
            break :blk @intCast(value);
        },
    };
}

fn readNonZeroReg(operand: types.Operand) types.EncodeError!u32 {
    return nonZeroRegValue(try readReg(operand));
}

fn nonZeroRegValue(value: u32) types.EncodeError!u32 {
    if (value == 0) return error.RegisterOutOfRange;
    return value;
}

fn nonZeroNonSpRegValue(value: u32) types.EncodeError!u32 {
    if (value == 0 or value == 2) return error.RegisterOutOfRange;
    return value;
}

fn evenRegValue(value: u32) types.EncodeError!u32 {
    if ((value & 0x1) != 0) return error.RegisterOutOfRange;
    return value;
}

fn compressedRegValue(value: u32) types.EncodeError!u32 {
    if (value < 8 or value > 15) return error.RegisterOutOfRange;
    return value - 8;
}

fn bit(value: u32, comptime index: u5) u32 {
    return (value >> index) & 0x1;
}

fn unsignedAligned(value: i64, bits: u6, alignment: i64) types.EncodeError!u32 {
    if (value < 0) return error.ImmediateOutOfRange;
    if (@mod(value, alignment) != 0) return error.ImmediateAlignment;
    return unsignedRange(value, bits);
}

const Split = struct {
    hi: u32,
    lo: u32,
};

fn fillCompressedOffset(spec: *const types.InstructionSpec, base: FieldValues, value: i64) types.EncodeError!FieldValues {
    var out = base;
    if (hasField(spec, "c_uimm1")) {
        const imm = try unsignedAligned(value, 2, 2);
        out.c_uimm1 = bit(imm, 1);
        return out;
    }
    if (hasField(spec, "c_uimm2")) {
        const imm = try unsignedRange(value, 2);
        out.c_uimm2 = imm;
        return out;
    }
    if (hasField(spec, "c_uimm7lo") or hasField(spec, "c_uimm7hi")) {
        const imm = try unsignedAligned(value, 7, 4);
        out.c_uimm7hi = bit(imm, 3) | (bit(imm, 4) << 1) | (bit(imm, 5) << 2);
        out.c_uimm7lo = bit(imm, 6) | (bit(imm, 2) << 1);
        return out;
    }
    if (hasField(spec, "c_uimm8lo") or hasField(spec, "c_uimm8hi")) {
        const imm = try unsignedAligned(value, 8, 8);
        out.c_uimm8hi = bit(imm, 3) | (bit(imm, 4) << 1) | (bit(imm, 5) << 2);
        out.c_uimm8lo = bit(imm, 6) | (bit(imm, 7) << 1);
        return out;
    }
    if (hasField(spec, "c_uimm8sphi") or hasField(spec, "c_uimm8splo")) {
        const imm = try unsignedAligned(value, 8, 4);
        out.c_uimm8sphi = bit(imm, 5);
        out.c_uimm8splo = (bit(imm, 6)) |
            (bit(imm, 7) << 1) |
            (bit(imm, 2) << 2) |
            (bit(imm, 3) << 3) |
            (bit(imm, 4) << 4);
        return out;
    }
    if (hasField(spec, "c_uimm8sp_s")) {
        const imm = try unsignedAligned(value, 8, 4);
        out.c_uimm8sp_s = (bit(imm, 6)) |
            (bit(imm, 7) << 1) |
            (bit(imm, 2) << 2) |
            (bit(imm, 3) << 3) |
            (bit(imm, 4) << 4) |
            (bit(imm, 5) << 5);
        return out;
    }
    if (hasField(spec, "c_uimm9sphi") or hasField(spec, "c_uimm9splo")) {
        const imm = try unsignedAligned(value, 9, 8);
        out.c_uimm9sphi = bit(imm, 5);
        out.c_uimm9splo = (bit(imm, 6)) |
            (bit(imm, 7) << 1) |
            (bit(imm, 8) << 2) |
            (bit(imm, 3) << 3) |
            (bit(imm, 4) << 4);
        return out;
    }
    if (hasField(spec, "c_uimm9sp_s")) {
        const imm = try unsignedAligned(value, 9, 8);
        out.c_uimm9sp_s = (bit(imm, 6)) |
            (bit(imm, 7) << 1) |
            (bit(imm, 8) << 2) |
            (bit(imm, 3) << 3) |
            (bit(imm, 4) << 4) |
            (bit(imm, 5) << 5);
        return out;
    }
    return error.UnsupportedInstruction;
}

fn compressedJumpOffset(value: i64) types.EncodeError!u32 {
    const imm = try wrapAlignedSigned(value, 12, 2);
    return (bit(imm, 5)) |
        (bit(imm, 1) << 1) |
        (bit(imm, 2) << 2) |
        (bit(imm, 3) << 3) |
        (bit(imm, 7) << 4) |
        (bit(imm, 6) << 5) |
        (bit(imm, 10) << 6) |
        (bit(imm, 8) << 7) |
        (bit(imm, 9) << 8) |
        (bit(imm, 4) << 9) |
        (bit(imm, 11) << 10);
}

fn compressedBranchOffset(value: i64) types.EncodeError!Split {
    const imm = try wrapAlignedSigned(value, 9, 2);
    return .{
        .hi = bit(imm, 3) | (bit(imm, 4) << 1) | (bit(imm, 8) << 2),
        .lo = bit(imm, 5) | (bit(imm, 1) << 1) | (bit(imm, 2) << 2) | (bit(imm, 6) << 3) | (bit(imm, 7) << 4),
    };
}

fn compressedAddi16spImmediate(value: i64) types.EncodeError!Split {
    if (value == 0) return error.ImmediateOutOfRange;
    const imm = try wrapAlignedSigned(value, 10, 16);
    return .{
        .hi = bit(imm, 9),
        .lo = bit(imm, 5) | (bit(imm, 7) << 1) | (bit(imm, 8) << 2) | (bit(imm, 6) << 3) | (bit(imm, 4) << 4),
    };
}

fn compressedLuiImmediate(value: i64) types.EncodeError!Split {
    if (value == 0) return error.ImmediateOutOfRange;
    const imm = try wrapAlignedSigned(value, 18, 4096);
    return .{
        .hi = bit(imm, 17),
        .lo = (imm >> 12) & 0x1f,
    };
}

fn compressedAddi4spnImmediate(value: i64) types.EncodeError!u32 {
    if (value == 0) return error.ImmediateOutOfRange;
    const imm = try unsignedAligned(value, 10, 4);
    return bit(imm, 3) |
        (bit(imm, 2) << 1) |
        (bit(imm, 6) << 2) |
        (bit(imm, 7) << 3) |
        (bit(imm, 8) << 4) |
        (bit(imm, 9) << 5) |
        (bit(imm, 4) << 6) |
        (bit(imm, 5) << 7);
}

fn packField(field: types.FieldSpec, value: u32) types.EncodeError!u32 {
    const max = (@as(u64, 1) << field.width) - 1;
    if (@as(u64, value) > max) return error.ImmediateOutOfRange;
    return value << field.lsb;
}

fn unsignedRange(value: i64, bits: u6) types.EncodeError!u32 {
    if (value < 0) return error.ImmediateOutOfRange;
    const max = (@as(i64, 1) << bits) - 1;
    if (value > max) return error.ImmediateOutOfRange;
    return @intCast(value);
}

fn wrapSigned(value: i64, bits: u6) types.EncodeError!u32 {
    const half = @as(i64, 1) << (bits - 1);
    const full = @as(i64, 1) << bits;
    if (value < -half or value >= half) return error.ImmediateOutOfRange;
    if (value < 0) return @intCast(value + full);
    return @intCast(value);
}

fn wrapAlignedSigned(value: i64, bits: u6, alignment: i64) types.EncodeError!u32 {
    if (@mod(value, alignment) != 0) return error.ImmediateAlignment;
    return wrapSigned(value, bits);
}

fn fieldName(actual: []const u8, comptime expected: []const u8) bool {
    return std.mem.eql(u8, fieldBase(actual), expected);
}

fn fieldBase(actual: []const u8) []const u8 {
    if (std.mem.indexOfScalar(u8, actual, '=')) |index| return actual[0..index];
    return actual;
}

fn fieldAliasSource(actual: []const u8) ?[]const u8 {
    if (std.mem.indexOfScalar(u8, actual, '=')) |index| return actual[index + 1 ..];
    return null;
}

fn pUimmField(actual: []const u8) bool {
    const base = fieldBase(actual);
    return std.mem.startsWith(u8, base, "p_w_uimm") or std.mem.startsWith(u8, base, "p_imm");
}

fn cUimmBits(spec: *const types.InstructionSpec) types.EncodeError!u6 {
    for (spec.fields) |field| {
        if (fieldName(field.name, "c_nzuimm5")) return 5;
        if (fieldName(field.name, "c_nzuimm6lo") or fieldName(field.name, "c_nzuimm6hi")) return 6;
    }
    return error.UnsupportedInstruction;
}
