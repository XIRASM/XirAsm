const std = @import("std");

pub const Word = u32;

pub const Id = enum(Word) {
    none,
    _,

    pub fn format(self: Id, writer: *std.Io.Writer) std.Io.Writer.Error!void {
        switch (self) {
            .none => try writer.writeAll("%none"),
            else => try writer.print("%{d}", .{@intFromEnum(self)}),
        }
    }
};

pub const LiteralInteger = Word;
pub const LiteralFloat = Word;
pub const LiteralString = []const u8;

pub const LiteralContextDependentNumber = union(enum) {
    int32: i32,
    uint32: u32,
    int64: i64,
    uint64: u64,
    float32: f32,
    float64: f64,
};

pub const LiteralExtInstInteger = struct { inst: Word };

pub const PairLiteralIntegerIdRef = struct { value: LiteralInteger, label: Id };
pub const PairIdRefLiteralInteger = struct { target: Id, member: LiteralInteger };
pub const PairIdRefIdRef = [2]Id;

pub const IdRange = struct {
    base: Word,
    len: Word,

    pub fn at(self: IdRange, i: usize) ?Id {
        if (i >= @as(usize, self.len)) return null;
        const offset: Word = @intCast(i);
        const raw = std.math.add(Word, self.base, offset) catch return null;
        return @enumFromInt(raw);
    }
};

pub const EncodeError = error{
    IdBoundOverflow,
    InstructionTooLong,
    InvalidHeaderBound,
};
