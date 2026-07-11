const std = @import("std");

const source = @import("source.zig");
const target = @import("target.zig");

const Allocator = std.mem.Allocator;

pub const FragmentId = struct {
    index: u32,
};

pub const SectionId = struct {
    index: u32,
};

pub const BytesFragment = struct {
    section: SectionId,
    data: []u8,
    span: source.SourceSpan,
};

pub const ReserveFragment = struct {
    section: SectionId,
    size: u64,
    alignment: u64,
    span: source.SourceSpan,
};

pub const AlignFragment = struct {
    section: SectionId,
    alignment: u64,
    fill: u8,
    span: source.SourceSpan,
};

pub const IsaInstructionFragment = struct {
    section: SectionId,
    target: target.Target,
    text: []u8,
    encoded_bytes: []u8 = &.{},
    min_size: u32,
    max_size: u32,
    current_size: u32,
    relaxable: bool = false,
    span: source.SourceSpan,
};

pub const Fragment = union(enum) {
    bytes: BytesFragment,
    reserve: ReserveFragment,
    alignment: AlignFragment,
    isa_instruction: IsaInstructionFragment,

    pub fn deinit(self: *Fragment, allocator: Allocator) void {
        switch (self.*) {
            .bytes => |fragment| allocator.free(fragment.data),
            .isa_instruction => |fragment| {
                allocator.free(fragment.text);
                if (fragment.encoded_bytes.len != 0) allocator.free(fragment.encoded_bytes);
            },
            .reserve, .alignment => {},
        }
        self.* = undefined;
    }
};

pub const FragmentStore = struct {
    items: std.ArrayList(Fragment) = .empty,

    pub fn deinit(self: *FragmentStore, allocator: Allocator) void {
        for (self.items.items) |*fragment| {
            fragment.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn addBytes(
        self: *FragmentStore,
        allocator: Allocator,
        section: SectionId,
        bytes: []const u8,
        span: source.SourceSpan,
    ) !FragmentId {
        const id = try nextFragmentId(self.items.items.len);
        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);

        try self.items.append(allocator, .{
            .bytes = .{
                .section = section,
                .data = owned_bytes,
                .span = span,
            },
        });
        return id;
    }

    pub fn addReserve(
        self: *FragmentStore,
        allocator: Allocator,
        section: SectionId,
        size: u64,
        alignment: u64,
        span: source.SourceSpan,
    ) !FragmentId {
        const id = try nextFragmentId(self.items.items.len);
        try self.items.append(allocator, .{
            .reserve = .{
                .section = section,
                .size = size,
                .alignment = alignment,
                .span = span,
            },
        });
        return id;
    }

    pub fn addAlignment(
        self: *FragmentStore,
        allocator: Allocator,
        section: SectionId,
        alignment: u64,
        fill: u8,
        span: source.SourceSpan,
    ) !FragmentId {
        const id = try nextFragmentId(self.items.items.len);
        try self.items.append(allocator, .{
            .alignment = .{
                .section = section,
                .alignment = alignment,
                .fill = fill,
                .span = span,
            },
        });
        return id;
    }

    pub fn addIsaInstruction(
        self: *FragmentStore,
        allocator: Allocator,
        section: SectionId,
        instruction_target: target.Target,
        text: []const u8,
        min_size: u32,
        max_size: u32,
        current_size: u32,
        span: source.SourceSpan,
    ) !FragmentId {
        const id = try nextFragmentId(self.items.items.len);
        const owned_text = try allocator.dupe(u8, text);
        errdefer allocator.free(owned_text);

        try self.items.append(allocator, .{
            .isa_instruction = .{
                .section = section,
                .target = instruction_target,
                .text = owned_text,
                .min_size = min_size,
                .max_size = max_size,
                .current_size = current_size,
                .span = span,
            },
        });
        return id;
    }

    pub fn updateIsaInstructionFacts(
        self: *FragmentStore,
        allocator: Allocator,
        id: FragmentId,
        bytes: []const u8,
        min_size: u32,
        max_size: u32,
        current_size: u32,
        relaxable: bool,
    ) !void {
        if (id.index >= self.items.items.len) return error.InvalidFragment;
        switch (self.items.items[id.index]) {
            .isa_instruction => |*instruction| {
                const owned_bytes = try allocator.dupe(u8, bytes);
                errdefer allocator.free(owned_bytes);

                if (instruction.encoded_bytes.len != 0) allocator.free(instruction.encoded_bytes);
                instruction.encoded_bytes = owned_bytes;
                instruction.min_size = min_size;
                instruction.max_size = max_size;
                instruction.current_size = current_size;
                instruction.relaxable = relaxable;
            },
            else => return error.InvalidFragment,
        }
    }
};

fn nextFragmentId(len: usize) error{TooManyFragments}!FragmentId {
    if (len > std.math.maxInt(u32)) return error.TooManyFragments;
    return .{ .index = @intCast(len) };
}
