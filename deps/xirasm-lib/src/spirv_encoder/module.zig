const std = @import("std");
const Allocator = std.mem.Allocator;

const section = @import("section.zig");
const types = @import("types.zig");

pub const Module = @This();

pub const Word = types.Word;
pub const Section = section.Section;
pub const EncodeError = types.EncodeError;

pub const magic_number: Word = 0x07230203;
pub const default_generator: Word = 0;
pub const default_schema: Word = 0;

pub const Version = enum(Word) {
    v1_0 = 0x00010000,
    v1_1 = 0x00010100,
    v1_2 = 0x00010200,
    v1_3 = 0x00010300,
    v1_4 = 0x00010400,
    v1_5 = 0x00010500,
    v1_6 = 0x00010600,

    pub fn toWord(self: Version) Word {
        return @intFromEnum(self);
    }
};

version: Version = .v1_6,
generator: Word = default_generator,
bound: Word = 1,
schema: Word = default_schema,
sections: struct {
    capabilities: Section = .{},
    extensions: Section = .{},
    extended_instruction_set: Section = .{},
    memory_model: Section = .{},
    entry_points: Section = .{},
    execution_modes: Section = .{},
    debug: Section = .{},
    annotations: Section = .{},
    globals: Section = .{},
    functions: Section = .{},
} = .{},

pub fn deinit(self: *Module, allocator: Allocator) void {
    self.sections.capabilities.deinit(allocator);
    self.sections.extensions.deinit(allocator);
    self.sections.extended_instruction_set.deinit(allocator);
    self.sections.memory_model.deinit(allocator);
    self.sections.entry_points.deinit(allocator);
    self.sections.execution_modes.deinit(allocator);
    self.sections.debug.deinit(allocator);
    self.sections.annotations.deinit(allocator);
    self.sections.globals.deinit(allocator);
    self.sections.functions.deinit(allocator);
    self.* = undefined;
}

pub fn setIdBound(self: *Module, bound: Word) EncodeError!void {
    if (bound == 0) return EncodeError.InvalidHeaderBound;
    self.bound = bound;
}

pub fn bumpIdBoundFor(self: *Module, id: types.Id) EncodeError!void {
    try self.ensureIdBoundFor(id);
}

pub fn ensureIdBoundFor(self: *Module, id: types.Id) EncodeError!void {
    const raw = @intFromEnum(id);
    if (raw < self.bound) return;
    if (raw == std.math.maxInt(Word)) return EncodeError.IdBoundOverflow;
    self.bound = raw + 1;
}

pub fn writeHeader(self: Module, out: *std.ArrayListUnmanaged(Word), allocator: Allocator) !void {
    try out.ensureUnusedCapacity(allocator, 5);
    out.appendAssumeCapacity(magic_number);
    out.appendAssumeCapacity(self.version.toWord());
    out.appendAssumeCapacity(self.generator);
    out.appendAssumeCapacity(self.bound);
    out.appendAssumeCapacity(self.schema);
}

pub fn appendBody(self: Module, out: *std.ArrayListUnmanaged(Word), allocator: Allocator) !void {
    try out.appendSlice(allocator, self.sections.capabilities.toWords());
    try out.appendSlice(allocator, self.sections.extensions.toWords());
    try out.appendSlice(allocator, self.sections.extended_instruction_set.toWords());
    try out.appendSlice(allocator, self.sections.memory_model.toWords());
    try out.appendSlice(allocator, self.sections.entry_points.toWords());
    try out.appendSlice(allocator, self.sections.execution_modes.toWords());
    try out.appendSlice(allocator, self.sections.debug.toWords());
    try out.appendSlice(allocator, self.sections.annotations.toWords());
    try out.appendSlice(allocator, self.sections.globals.toWords());
    try out.appendSlice(allocator, self.sections.functions.toWords());
}

pub fn toOwnedWords(self: Module, allocator: Allocator) ![]Word {
    var out: std.ArrayListUnmanaged(Word) = .empty;
    errdefer out.deinit(allocator);
    try self.writeHeader(&out, allocator);
    try self.appendBody(&out, allocator);
    return try out.toOwnedSlice(allocator);
}

pub fn toOwnedBytes(self: Module, allocator: Allocator) ![]u8 {
    const words = try self.toOwnedWords(allocator);
    defer allocator.free(words);
    return try allocator.dupe(u8, std.mem.sliceAsBytes(words));
}

test "module header defaults to SPIR-V 1.6" {
    var module = Module{};
    const words = try module.toOwnedWords(std.testing.allocator);
    defer std.testing.allocator.free(words);

    try std.testing.expectEqualSlices(Word, &.{
        magic_number,
        Version.v1_6.toWord(),
        default_generator,
        1,
        default_schema,
    }, words);
}

test "module body follows logical layout order" {
    var module = Module{};
    defer module.deinit(std.testing.allocator);

    try module.sections.capabilities.emitRawInstruction(std.testing.allocator, .op_capability, &.{@intFromEnum(@import("spec.zig").Capability.shader)});
    try module.sections.memory_model.emitRawInstruction(std.testing.allocator, .op_memory_model, &.{
        @intFromEnum(@import("spec.zig").AddressingModel.logical),
        @intFromEnum(@import("spec.zig").MemoryModel.glsl450),
    });

    const words = try module.toOwnedWords(std.testing.allocator);
    defer std.testing.allocator.free(words);

    try std.testing.expectEqual(@as(usize, 10), words.len);
    try std.testing.expectEqual(@as(Word, 0x00020011), words[5]);
    try std.testing.expectEqual(@as(Word, 0x0003000e), words[7]);
}
