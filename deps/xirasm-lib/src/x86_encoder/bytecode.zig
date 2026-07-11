//! Cursor over source-backed template bytecode streams.
//!
//! This is the Zig landing point for the `bytecode.txt` stream mechanics used
//! by `asm/assemble.c` `calcsize` and later `gencode`.

const std = @import("std");
const generated = @import("generated_match_tables.zig");
const match = @import("match.zig");

pub const BytecodeError = error{
    MissingBytecode,
    MissingPayload,
};

pub const BytecodeCursor = struct {
    template: match.TemplateRef,
    bytes: []const u8,
    offset: usize = 0,
    opex: u8 = 0,

    pub fn init(template: match.TemplateRef) BytecodeError!BytecodeCursor {
        const bytes = generated.bytecodeForTemplate(template.raw()) orelse return error.MissingBytecode;
        return .{
            .template = template,
            .bytes = bytes,
        };
    }

    pub fn peek(self: BytecodeCursor) ?u8 {
        if (self.offset >= self.bytes.len) return null;
        return self.bytes[self.offset];
    }

    pub fn next(self: *BytecodeCursor) ?u8 {
        const byte = self.peek() orelse return null;
        self.offset += 1;
        return byte;
    }

    pub fn nextRequired(self: *BytecodeCursor) BytecodeError!u8 {
        return self.next() orelse error.MissingPayload;
    }

    pub fn setOpex(self: *BytecodeCursor, opex: u8) void {
        self.opex = opex;
    }

    pub fn clearOpex(self: *BytecodeCursor) void {
        self.opex = 0;
    }

    pub fn operandIndices(self: BytecodeCursor, opcode: u8) struct { primary: u8, secondary: u8 } {
        return .{
            .primary = (opcode & 3) + ((self.opex & 1) << 2),
            .secondary = ((opcode >> 3) & 3) + ((self.opex & 2) << 1),
        };
    }

    pub fn consumeLiteralBytes(self: *BytecodeCursor, count: usize) BytecodeError!void {
        for (0..count) |_| {
            try self.consumeRequiredByte();
        }
    }

    pub fn consumeRequiredByte(self: *BytecodeCursor) BytecodeError!void {
        if (try self.nextRequired() >= 0) {}
    }

    pub fn consumeVexPayload(self: *BytecodeCursor) BytecodeError!struct { cm: u8, wlp: u8 } {
        return .{
            .cm = try self.nextRequired(),
            .wlp = try self.nextRequired(),
        };
    }

    pub fn consumeEvexPayload(self: *BytecodeCursor) BytecodeError!struct { p0: u8, p1: u8, p2: u8, tuple: u8 } {
        return .{
            .p0 = try self.nextRequired(),
            .p1 = try self.nextRequired(),
            .p2 = try self.nextRequired(),
            .tuple = try self.nextRequired(),
        };
    }
};

test "BytecodeCursor walks source-backed source-backed bytecode streams" {
    const testing = std.testing;
    const push_bucket = generated.bucketByMnemonic("push") orelse return error.UnexpectedTestResult;
    const template = match.templateAt(push_bucket.template_start) orelse return error.UnexpectedTestResult;

    var cursor = try BytecodeCursor.init(template);
    try testing.expectEqual(template.bytecodeFirst(), cursor.peek().?);
    try testing.expectEqual(template.bytecodeFirst(), (try cursor.nextRequired()));
    try cursor.consumeLiteralBytes(1);
    try testing.expectEqual(@as(u8, 0), (try cursor.nextRequired()));
}

test "BytecodeCursor preserves x86 operand selector extension rules" {
    const testing = std.testing;
    const jmp_bucket = generated.bucketByMnemonic("jmp") orelse return error.UnexpectedTestResult;
    const template = match.templateAt(jmp_bucket.template_start + 1) orelse return error.UnexpectedTestResult;

    var cursor = try BytecodeCursor.init(template);
    cursor.setOpex(3);
    const indices = cursor.operandIndices(0o13);

    try testing.expectEqual(@as(u8, 7), indices.primary);
    try testing.expectEqual(@as(u8, 5), indices.secondary);
}
