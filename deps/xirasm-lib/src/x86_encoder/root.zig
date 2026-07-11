pub const api = @import("api.zig");
pub const bytecode = @import("bytecode.zig");
pub const ea = @import("ea.zig");
pub const encode = @import("encode.zig");
pub const match = @import("match.zig");
pub const regs = @import("regs.zig");
pub const size = @import("size.zig");
pub const tables = @import("tables.zig");
pub const types = @import("types.zig");

pub const BuiltinEncodeResult = api.BuiltinEncodeResult;
pub const BuiltinEncodeRoute = api.BuiltinEncodeRoute;
pub const BuiltinMainlineGap = api.BuiltinMainlineGap;
pub const AddressSizePrefix = api.AddressSizePrefix;
pub const BranchRelaxationDecision = api.BranchRelaxationDecision;
pub const EncodingPrefix = api.EncodingPrefix;
pub const EncodeContext = api.EncodeContext;
pub const EncodeError = api.EncodeError;
pub const EncodeUnit = api.EncodeUnit;
pub const ExpressionResolveError = api.ExpressionResolveError;
pub const ExpressionResolver = api.ExpressionResolver;
pub const Fixup = api.Fixup;
pub const FixupKind = api.FixupKind;
pub const MaterializeError = api.MaterializeError;
pub const OperandSizePrefix = api.OperandSizePrefix;
pub const RepPrefixKind = api.RepPrefixKind;
pub const ResolvedExpr = api.ResolvedExpr;

pub const builtinMainlineGap = api.builtinMainlineGap;
pub const encodeBuiltinUnits = api.encodeBuiltinUnits;
pub const encodeBuiltinUnitsWithResolver = api.encodeBuiltinUnitsWithResolver;
pub const materializeFixup = api.materializeFixup;
pub const materializeOutput = api.materializeOutput;
pub const segmentPrefixValueByName = api.segmentPrefixValueByName;

test {
    _ = api;
    _ = bytecode;
    _ = ea;
    _ = encode;
    _ = match;
    _ = regs;
    _ = size;
    _ = tables;
    _ = types;
}
