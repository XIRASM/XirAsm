const std = @import("std");
const registers = @import("generated_registers.zig");
const types = @import("types.zig");
pub const match_tables = @import("generated_match_tables.zig");

pub const RegisterInfo = registers.RegisterInfo;
pub const all = registers.all;

pub fn registerByName(name: []const u8) ?RegisterInfo {
    for (all) |register| {
        if (std.ascii.eqlIgnoreCase(register.name, name)) return register;
    }
    return null;
}

pub fn registerByExprReg(expr_reg: i32) ?RegisterInfo {
    for (all) |register| {
        if (register.expr_reg == expr_reg) return register;
    }
    return null;
}

pub const TemplateRef = struct {
    index: usize,

    pub fn raw(self: TemplateRef) match_tables.Template {
        return match_tables.templates[self.index];
    }

    pub fn opcode(self: TemplateRef) u16 {
        return self.raw().opcode;
    }

    pub fn operandCount(self: TemplateRef) usize {
        return self.raw().operand_count;
    }

    pub fn bytecodeFirst(self: TemplateRef) u8 {
        return self.raw().bytecode_first;
    }

    pub fn iflagField(self: TemplateRef, field_index: usize) u32 {
        return match_tables.iflag_fields[self.raw().iflag_index][field_index];
    }

    pub fn iflagTest(self: TemplateRef, bit: u32) bool {
        const field_index: usize = @intCast(bit >> 5);
        if (field_index >= types.if_field_count) return false;
        const mask = @as(u32, 1) << @as(u5, @intCast(bit & 31));
        return (self.iflagField(field_index) & mask) != 0;
    }

    pub fn hasOperandIflag(self: TemplateRef, operand_iflag: i32) bool {
        return operand_iflag >= 0 and self.iflagTest(@intCast(operand_iflag));
    }

    pub fn operandTypeBits(self: TemplateRef, operand_index: usize) u64 {
        const pool_index: usize = @intCast(self.raw().operands[operand_index]);
        return match_tables.operand_flags_pool[pool_index].raw_bits;
    }

    pub fn operandDecoratorRawBits(self: TemplateRef, operand_index: usize) u16 {
        const pool_index: usize = @intCast(self.raw().decorators[operand_index]);
        return match_tables.decorator_flags_pool[pool_index].raw_bits;
    }

    pub fn smask(self: TemplateRef) u32 {
        return self.iflagField(0) & types.if_smask;
    }

    pub fn armask(self: TemplateRef) u32 {
        return self.iflagField(0) & types.if_armask;
    }

    pub fn smmatchMask(self: TemplateRef) u32 {
        return self.iflagField(0) & types.if_smmask;
    }

    pub fn arxMask(self: TemplateRef) u32 {
        return self.armask() >> types.if_ar0;
    }

    pub fn smxMask(self: TemplateRef) u32 {
        return self.smmatchMask() >> types.if_sm0;
    }

    pub fn baseSizeMask(self: TemplateRef) u64 {
        return @as(u64, self.smask() & types.if_tsmask) << (types.size_shift - types.if_sb);
    }

    pub fn usesOperandSize(self: TemplateRef) bool {
        return (self.smask() & types.ifm_osize) != 0;
    }

    pub fn usesAddressSize(self: TemplateRef) bool {
        return (self.smask() & types.ifm_asize) != 0;
    }

    pub fn cpuLevelBits(self: TemplateRef) u32 {
        return self.iflagField(types.if_cpu_field) & types.if_cpu_level_mask;
    }
};

pub fn opcodeByMnemonic(mnemonic: []const u8) ?u16 {
    const bucket = match_tables.bucketByMnemonic(mnemonic) orelse return null;
    return bucket.opcode_index;
}

pub fn templateAt(index: usize) ?TemplateRef {
    if (index >= match_tables.templates.len) return null;
    return .{ .index = index };
}

test "registerByName finds generated register rows" {
    const testing = std.testing;

    const rax = registerByName("rax") orelse return error.UnexpectedTestResult;
    try testing.expectEqual(@as(i16, 210), rax.expr_reg);
    try testing.expectEqualStrings("R_RAX", rax.enum_name);
    try testing.expectEqual(@as(i32, 0), rax.value);

    const zmm31 = registerByName("zmm31") orelse return error.UnexpectedTestResult;
    try testing.expectEqual(@as(i16, 338), zmm31.expr_reg);
    try testing.expectEqualStrings("R_ZMM31", zmm31.enum_name);
    try testing.expectEqual(@as(i32, 31), zmm31.value);

    const upper = registerByName("RAX") orelse return error.UnexpectedTestResult;
    try testing.expectEqual(@as(i16, 210), upper.expr_reg);
    try testing.expect(registerByName("not_a_register") == null);
}

test "full match tables preserve x86 match stage bucket inputs" {
    const testing = std.testing;

    try testing.expectEqual(@as(usize, 2639), match_tables.instruction_names.len);
    try testing.expectEqual(match_tables.instruction_names.len, match_tables.instruction_buckets.len);
    try testing.expectEqual(@as(usize, 12319), match_tables.templates.len);
    try testing.expectEqual(@as(usize, 73483), match_tables.bytecodes.len);
    try testing.expectEqual(@as(usize, 174), match_tables.operand_flags_pool.len);
    try testing.expectEqual(@as(usize, 14), match_tables.decorator_flags_pool.len);
    try testing.expectEqual(match_tables.iflag_fields.len, match_tables.iflag_policy_bits.len);

    const push_bucket = match_tables.bucketByMnemonic("push") orelse return error.UnexpectedTestResult;
    try testing.expect(push_bucket.hasTemplates());
    try testing.expectEqual(@as(u16, 317), push_bucket.opcode_index);
    try testing.expectEqual(@as(u32, 2971), push_bucket.template_start);
    try testing.expectEqual(@as(u16, 21), push_bucket.template_count);

    const pop_bucket = match_tables.bucketByMnemonic("pop") orelse return error.UnexpectedTestResult;
    try testing.expect(pop_bucket.hasTemplates());
    try testing.expectEqual(@as(u16, 318), pop_bucket.opcode_index);
    try testing.expectEqual(@as(u32, 2992), pop_bucket.template_start);
    try testing.expectEqual(@as(u16, 14), pop_bucket.template_count);

    const mov_bucket = match_tables.bucketByMnemonic("mov") orelse return error.UnexpectedTestResult;
    try testing.expect(mov_bucket.hasTemplates());
    try testing.expectEqual(@as(u16, 20), mov_bucket.opcode_index);
    try testing.expectEqual(@as(u32, 19), mov_bucket.template_start);
    try testing.expectEqual(@as(u16, 84), mov_bucket.template_count);

    const jmp_bucket = match_tables.bucketByMnemonic("jmp") orelse return error.UnexpectedTestResult;
    try testing.expect(jmp_bucket.hasTemplates());
    try testing.expectEqual(@as(u16, 116), jmp_bucket.opcode_index);
    try testing.expectEqual(@as(u32, 2232), jmp_bucket.template_start);
    try testing.expectEqual(@as(u16, 31), jmp_bucket.template_count);

    const push_first = match_tables.templateAt(push_bucket.template_start) orelse return error.UnexpectedTestResult;
    try testing.expectEqual(push_bucket.opcode_index, push_first.opcode);
    try testing.expectEqual(@as(u8, 1), push_first.operand_count);
    try testing.expectEqual(@as(u32, 1785), push_first.xda_line);
    try testing.expectEqual(@as(u8, 0x01), push_first.bytecode_first);
    const push_first_bytecode = match_tables.bytecodeForTemplate(push_first) orelse return error.UnexpectedTestResult;
    try testing.expectEqual(push_first.bytecode_first, push_first_bytecode[0]);
    try testing.expectEqual(@as(u8, 0), push_first_bytecode[push_first_bytecode.len - 1]);

    const jmp_relax = match_tables.templateAt(jmp_bucket.template_start + 1) orelse return error.UnexpectedTestResult;
    try testing.expectEqual(jmp_bucket.opcode_index, jmp_relax.opcode);
    try testing.expectEqual(@as(u32, 1303), jmp_relax.xda_line);
    try testing.expectEqual(@as(u8, 0xD7), jmp_relax.bytecode_first);
    const jmp_relax_bytecode = match_tables.bytecodeForTemplate(jmp_relax) orelse return error.UnexpectedTestResult;
    try testing.expectEqual(jmp_relax.bytecode_first, jmp_relax_bytecode[0]);
    try testing.expectEqual(@as(u8, 0), jmp_relax_bytecode[jmp_relax_bytecode.len - 1]);
}
