const encode_mod = @import("encode.zig");
const regs = @import("regs.zig");
const tables = @import("tables.zig");
const types = @import("types.zig");

pub const EncodeError = types.EncodeError;
pub const EncodedInstruction = types.EncodedInstruction;
pub const EncodeRequest = types.EncodeRequest;
pub const Operand = types.Operand;
pub const Register = regs.Register;

pub fn parseRegister(text: []const u8) EncodeError!Register {
    return regs.parseRegister(text);
}

pub fn instructionByMnemonic(mnemonic: []const u8) EncodeError!?*const types.InstructionSpec {
    return tables.instructionByMnemonic(mnemonic);
}

pub fn instructionByMnemonicAnyXLen(mnemonic: []const u8) EncodeError!?*const types.InstructionSpec {
    return tables.instructionByMnemonicAnyXLen(mnemonic);
}

pub fn encode(request: EncodeRequest) EncodeError!EncodedInstruction {
    return encodeWithMode(request, .semantic);
}

pub fn encodeRaw(request: EncodeRequest) EncodeError!EncodedInstruction {
    return encodeWithMode(request, .raw);
}

const EncodeMode = enum {
    semantic,
    raw,
};

fn encodeWithMode(request: EncodeRequest, mode: EncodeMode) EncodeError!EncodedInstruction {
    if (request.xlen != 32 and request.xlen != 64) return error.InvalidXLen;
    const spec = try tables.instructionByMnemonicForXLen(request.mnemonic, request.xlen) orelse {
        if (try tables.instructionByMnemonicAnyXLen(request.mnemonic) != null) {
            return error.UnsupportedXLen;
        }
        return error.UnsupportedInstruction;
    };
    return switch (mode) {
        .semantic => encode_mod.encode(request, spec),
        .raw => encode_mod.encodeRaw(request, spec),
    };
}

pub fn encodeMnemonic(mnemonic: []const u8, xlen: u8, operands: []const Operand) EncodeError!EncodedInstruction {
    return encode(.{
        .mnemonic = mnemonic,
        .xlen = xlen,
        .operands = operands,
    });
}

pub fn encodeRawMnemonic(mnemonic: []const u8, xlen: u8, operands: []const Operand) EncodeError!EncodedInstruction {
    return encodeRaw(.{
        .mnemonic = mnemonic,
        .xlen = xlen,
        .operands = operands,
    });
}
