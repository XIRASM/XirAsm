pub const api = @import("api.zig");
pub const encode = @import("encode.zig");
pub const regs = @import("regs.zig");
pub const source = @import("source.zig");
pub const tables = @import("tables.zig");
pub const types = @import("types.zig");

pub const EncodedInstruction = api.EncodedInstruction;
pub const EncodeError = api.EncodeError;
pub const EncodeRequest = api.EncodeRequest;
pub const Operand = api.Operand;
pub const Register = api.Register;

pub const encodeMnemonic = api.encodeMnemonic;
pub const encodeRawMnemonic = api.encodeRawMnemonic;
pub const encodeInstructionText = source.encodeInstructionText;
pub const instructionByMnemonic = api.instructionByMnemonic;
pub const parseInstructionText = source.parseInstructionText;
pub const parseRegister = api.parseRegister;

test {
    _ = api;
    _ = encode;
    _ = regs;
    _ = source;
    _ = tables;
    _ = types;
}
