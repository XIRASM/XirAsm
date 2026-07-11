const std = @import("std");
const Allocator = std.mem.Allocator;

const types = @import("types.zig");
const spec = @import("spec.zig");

pub const Section = @This();

pub const Word = types.Word;
pub const Id = types.Id;
pub const EncodeError = types.EncodeError;

instructions: std.ArrayListUnmanaged(Word) = .empty,

pub fn deinit(self: *Section, allocator: Allocator) void {
    self.instructions.deinit(allocator);
    self.* = undefined;
}

pub fn reset(self: *Section) void {
    self.instructions.clearRetainingCapacity();
}

pub fn toWords(self: Section) []const Word {
    return self.instructions.items;
}

pub fn toBytes(self: Section) []const u8 {
    return std.mem.sliceAsBytes(self.instructions.items);
}

pub fn append(self: *Section, allocator: Allocator, other: Section) !void {
    try self.instructions.appendSlice(allocator, other.instructions.items);
}

pub fn ensureUnusedCapacity(self: *Section, allocator: Allocator, words: usize) !void {
    try self.instructions.ensureUnusedCapacity(allocator, words);
}

pub fn emitRaw(self: *Section, allocator: Allocator, opcode: spec.Opcode, operand_words: usize) !void {
    const word_count = try instructionWordCount(operand_words);
    try self.instructions.ensureUnusedCapacity(allocator, word_count);
    self.writeWord(instructionHeader(word_count, opcode));
}

pub fn emitRawInstruction(self: *Section, allocator: Allocator, opcode: spec.Opcode, operands: []const Word) !void {
    try self.emitRaw(allocator, opcode, operands.len);
    self.writeWords(operands);
}

pub fn emit(self: *Section, allocator: Allocator, comptime opcode: spec.Opcode, operands: opcode.Operands()) !void {
    const word_count = instructionSize(opcode, operands);
    if (word_count > std.math.maxInt(u16)) return EncodeError.InstructionTooLong;
    try self.instructions.ensureUnusedCapacity(allocator, word_count);
    self.writeWord(instructionHeader(word_count, opcode));
    writeOperands(self, opcode.Operands(), operands);
}

pub fn emitAssumeCapacity(self: *Section, comptime opcode: spec.Opcode, operands: opcode.Operands()) EncodeError!void {
    const word_count = instructionSize(opcode, operands);
    if (word_count > std.math.maxInt(u16)) return EncodeError.InstructionTooLong;
    self.writeWord(instructionHeader(word_count, opcode));
    writeOperands(self, opcode.Operands(), operands);
}

pub fn writeWord(self: *Section, word: Word) void {
    self.instructions.appendAssumeCapacity(word);
}

pub fn writeWords(self: *Section, words: []const Word) void {
    self.instructions.appendSliceAssumeCapacity(words);
}

pub fn writeDoubleWord(self: *Section, dword: u64) void {
    self.writeWords(&.{
        @truncate(dword),
        @truncate(dword >> @bitSizeOf(Word)),
    });
}

fn instructionWordCount(operand_words: usize) EncodeError!usize {
    if (operand_words >= std.math.maxInt(u16)) return EncodeError.InstructionTooLong;
    const word_count = operand_words + 1;
    return word_count;
}

fn instructionHeader(word_count: usize, opcode: spec.Opcode) Word {
    const count: u32 = @intCast(word_count);
    return (count << 16) | @intFromEnum(opcode);
}

fn writeOperands(section: *Section, comptime Operands: type, operands: Operands) void {
    const info = switch (@typeInfo(Operands)) {
        .@"struct" => |info| info,
        .void => return,
        else => @compileError("SPIR-V operands must be a struct or void"),
    };
    inline for (info.field_names, info.field_types) |field_name, Field| {
        writeOperand(section, Field, @field(operands, field_name));
    }
}

pub fn writeOperand(section: *Section, comptime Operand: type, operand: Operand) void {
    switch (Operand) {
        spec.LiteralSpecConstantOpInteger => section.writeWord(@intFromEnum(operand.opcode)),
        types.Id => section.writeWord(@intFromEnum(operand)),
        types.LiteralInteger => section.writeWord(operand),
        types.LiteralString => section.writeString(operand),
        types.LiteralContextDependentNumber => section.writeContextDependentNumber(operand),
        types.LiteralExtInstInteger => section.writeWord(operand.inst),
        types.PairLiteralIntegerIdRef => section.writeWords(&.{ operand.value, @intFromEnum(operand.label) }),
        types.PairIdRefLiteralInteger => section.writeWords(&.{ @intFromEnum(operand.target), operand.member }),
        types.PairIdRefIdRef => section.writeWords(&.{ @intFromEnum(operand[0]), @intFromEnum(operand[1]) }),
        else => switch (@typeInfo(Operand)) {
            .@"enum" => section.writeWord(@intFromEnum(operand)),
            .optional => |info| if (operand) |child| writeOperand(section, info.child, child),
            .pointer => |info| {
                comptime if (info.size != .slice) @compileError("SPIR-V pointer operands must be slices");
                for (operand) |item| {
                    writeOperand(section, info.child, item);
                }
            },
            .@"struct" => |info| {
                if (info.layout == .@"packed") {
                    section.writeWord(@as(Word, @bitCast(operand)));
                } else {
                    writeExtendedMask(section, Operand, operand);
                }
            },
            .@"union" => writeExtendedUnion(section, Operand, operand),
            else => @compileError("unsupported SPIR-V operand type"),
        },
    }
}

pub fn writeString(section: *Section, str: []const u8) void {
    const zero_terminated_len = str.len + 1;
    var i: usize = 0;
    while (i < zero_terminated_len) : (i += @sizeOf(Word)) {
        var word: Word = 0;
        var j: usize = 0;
        while (j < @sizeOf(Word) and i + j < str.len) : (j += 1) {
            word |= @as(Word, str[i + j]) << @as(std.math.Log2Int(Word), @intCast(j * @bitSizeOf(u8)));
        }
        section.instructions.appendAssumeCapacity(word);
    }
}

pub fn writeContextDependentNumber(section: *Section, operand: types.LiteralContextDependentNumber) void {
    switch (operand) {
        .int32 => |int| section.writeWord(@bitCast(int)),
        .uint32 => |int| section.writeWord(int),
        .int64 => |int| section.writeDoubleWord(@bitCast(int)),
        .uint64 => |int| section.writeDoubleWord(int),
        .float32 => |float| section.writeWord(@bitCast(float)),
        .float64 => |float| section.writeDoubleWord(@bitCast(float)),
    }
}

fn writeExtendedMask(section: *Section, comptime Operand: type, operand: Operand) void {
    var mask: Word = 0;
    const info = @typeInfo(Operand).@"struct";
    inline for (info.field_names, info.field_types, 0..) |field_name, Field, bit| {
        switch (@typeInfo(Field)) {
            .optional => if (@field(operand, field_name) != null) {
                mask |= @as(Word, 1) << @as(u5, @intCast(bit));
            },
            .bool => if (@field(operand, field_name)) {
                mask |= @as(Word, 1) << @as(u5, @intCast(bit));
            },
            else => @compileError("extended mask fields must be bool or optional payloads"),
        }
    }
    section.writeWord(mask);
    inline for (info.field_names, info.field_types) |field_name, Field| {
        switch (@typeInfo(Field)) {
            .optional => |opt_info| if (@field(operand, field_name)) |child| {
                writeOperands(section, opt_info.child, child);
            },
            .bool => {},
            else => @compileError("extended mask fields must be bool or optional payloads"),
        }
    }
}

fn writeExtendedUnion(section: *Section, comptime Operand: type, operand: Operand) void {
    switch (operand) {
        inline else => |op, tag| {
            section.writeWord(@intFromEnum(tag));
            writeOperands(section, @TypeOf(op), op);
        },
    }
}

pub fn instructionSize(comptime opcode: spec.Opcode, operands: opcode.Operands()) usize {
    return checkedAdd(operandsSize(opcode.Operands(), operands), 1);
}

pub fn operandsSize(comptime Operands: type, operands: Operands) usize {
    const info = switch (@typeInfo(Operands)) {
        .@"struct" => |info| info,
        .void => return 0,
        else => @compileError("SPIR-V operands must be a struct or void"),
    };
    var total: usize = 0;
    inline for (info.field_names, info.field_types) |field_name, Field| {
        total = checkedAdd(total, operandSize(Field, @field(operands, field_name)));
    }
    return total;
}

pub fn operandSize(comptime Operand: type, operand: Operand) usize {
    return switch (Operand) {
        spec.LiteralSpecConstantOpInteger => 1,
        types.Id, types.LiteralInteger, types.LiteralExtInstInteger => 1,
        types.LiteralString => literalStringWordCount(operand.len),
        types.LiteralContextDependentNumber => switch (operand) {
            .int32, .uint32, .float32 => 1,
            .int64, .uint64, .float64 => 2,
        },
        types.PairLiteralIntegerIdRef, types.PairIdRefLiteralInteger, types.PairIdRefIdRef => 2,
        else => switch (@typeInfo(Operand)) {
            .@"enum" => 1,
            .optional => |info| if (operand) |child| operandSize(info.child, child) else 0,
            .pointer => |info| {
                comptime if (info.size != .slice) @compileError("SPIR-V pointer operands must be slices");
                var total: usize = 0;
                for (operand) |item| {
                    total = checkedAdd(total, operandSize(info.child, item));
                }
                return total;
            },
            .@"struct" => |struct_info| {
                if (struct_info.layout == .@"packed") return 1;
                var total: usize = 0;
                inline for (struct_info.field_names, struct_info.field_types) |field_name, Field| {
                    switch (@typeInfo(Field)) {
                        .optional => |info| if (@field(operand, field_name)) |child| {
                            total = checkedAdd(total, operandsSize(info.child, child));
                        },
                        .bool => {},
                        else => @compileError("extended mask fields must be bool or optional payloads"),
                    }
                }
                return checkedAdd(total, 1);
            },
            .@"union" => switch (operand) {
                inline else => |op| checkedAdd(operandsSize(@TypeOf(op), op), 1),
            },
            else => @compileError("unsupported SPIR-V operand type"),
        },
    };
}

fn checkedAdd(lhs: usize, rhs: usize) usize {
    return std.math.add(usize, lhs, rhs) catch std.math.maxInt(usize);
}

fn literalStringWordCount(len: usize) usize {
    const zero_terminated_len = std.math.add(usize, len, 1) catch return std.math.maxInt(usize);
    const padded_len = std.math.add(usize, zero_terminated_len, @sizeOf(Word) - 1) catch return std.math.maxInt(usize);
    return padded_len / @sizeOf(Word);
}

test "emit nop" {
    var section = Section{};
    defer section.deinit(std.testing.allocator);
    try section.emit(std.testing.allocator, .op_nop, {});
    try std.testing.expectEqualSlices(Word, &.{@as(Word, 1) << 16 | 0}, section.toWords());
}

test "emit undef" {
    var section = Section{};
    defer section.deinit(std.testing.allocator);
    try section.emit(std.testing.allocator, .op_undef, .{ .id_result_type = @enumFromInt(1), .id_result = @enumFromInt(2) });
    try std.testing.expectEqualSlices(Word, &.{
        @as(Word, 3) << 16 | 1,
        1,
        2,
    }, section.toWords());
}

test "raw instruction rejects word count overflow" {
    var section = Section{};
    defer section.deinit(std.testing.allocator);
    try std.testing.expectError(EncodeError.InstructionTooLong, section.emitRaw(std.testing.allocator, .op_nop, std.math.maxInt(u16)));
}
