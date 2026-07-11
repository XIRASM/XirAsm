//! x86 `asm/assemble.c` register-helper translation.
//!
//! This module is the Zig landing point for `regflag` and `regval`. It reads
//! register metadata from the generated generated x86 register table projection.

const std = @import("std");
const match = @import("match.zig");
const tables = @import("tables.zig");

pub const reg_stage_functions = [_][]const u8{ "regflag", "regval" };

pub const RegisterError = error{
    InvalidRegisterOperand,
    InvalidImmediateValue,
    InvalidRegisterFlags,
    MissingRegisterMetadata,
};

pub fn registerRef(expr_reg: i32) ?tables.RegisterInfo {
    return tables.registerByExprReg(expr_reg);
}

pub fn regflag(operand: *const match.Operand) RegisterError!u64 {
    if (!match.isRegister(operand.basereg)) return error.InvalidRegisterOperand;
    const register = registerRef(operand.basereg) orelse return error.MissingRegisterMetadata;
    if (register.flags < 0) return error.InvalidRegisterFlags;
    return @intCast(register.flags);
}

pub fn regval(operand: *const match.Operand) RegisterError!i32 {
    if ((operand.type_bits & match.immediate) != 0) {
        if (operand.offset < std.math.minInt(i32) or operand.offset > std.math.maxInt(i32)) {
            return error.InvalidImmediateValue;
        }
        return @intCast(operand.offset);
    }
    if (!match.isRegister(operand.basereg)) return error.InvalidRegisterOperand;
    const register = registerRef(operand.basereg) orelse return error.MissingRegisterMetadata;
    return register.value;
}

test "regflag and regval read generated generated x86 register metadata" {
    const testing = std.testing;
    const rax = tables.registerByName("rax") orelse return error.UnexpectedTestResult;
    const r8 = tables.registerByName("r8") orelse return error.UnexpectedTestResult;
    const ah = tables.registerByName("ah") orelse return error.UnexpectedTestResult;

    const rax_op: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(rax.flags),
        .basereg = rax.expr_reg,
    };
    try testing.expectEqual(@as(u64, @intCast(rax.flags)), try regflag(&rax_op));
    try testing.expectEqual(@as(i32, 0), try regval(&rax_op));

    const r8_op: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(r8.flags),
        .basereg = r8.expr_reg,
    };
    try testing.expectEqual(@as(i32, 8), try regval(&r8_op));

    const ah_op: match.Operand = .{
        .kind = .register,
        .type_bits = @intCast(ah.flags),
        .basereg = ah.expr_reg,
    };
    try testing.expectEqual(@as(i32, 4), try regval(&ah_op));
}

test "regval preserves x86 immediate register-field allowance" {
    const testing = std.testing;
    const operand: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 7,
    };

    try testing.expectEqual(@as(i32, 7), try regval(&operand));
}

test "register helpers keep invalid operands as explicit errors" {
    const testing = std.testing;
    const operand: match.Operand = .{
        .kind = .register,
        .type_bits = match.register,
    };

    try testing.expectError(error.InvalidRegisterOperand, regflag(&operand));
    try testing.expectError(error.InvalidRegisterOperand, regval(&operand));
}
