const std = @import("std");

const fragment = @import("../fragment.zig");
const module_mod = @import("../module.zig");
const contracts = @import("contracts.zig");

const ActiveOutput = contracts.ActiveOutput;
const LowerError = contracts.LowerError;

pub const Error = error{
    InvalidAlignment,
    OffsetOverflow,
};

pub fn nextOffsetFromFragment(stored_fragment: fragment.Fragment, current_offset: u64) Error!u64 {
    const size: u64 = switch (stored_fragment) {
        .bytes => |bytes| @intCast(bytes.data.len),
        .reserve => |reserve| reserve.size,
        .alignment => |alignment| {
            if (alignment.alignment == 0) return error.InvalidAlignment;
            const remainder = current_offset % alignment.alignment;
            if (remainder == 0) return current_offset;
            return std.math.add(u64, current_offset, alignment.alignment - remainder) catch error.OffsetOverflow;
        },
        .isa_instruction => |instruction| instruction.current_size,
    };

    return std.math.add(u64, current_offset, size) catch error.OffsetOverflow;
}

pub fn nextFileOffsetFromFragment(
    stored_fragment: fragment.Fragment,
    current_offset: u64,
    current_file_offset: u64,
) Error!u64 {
    return switch (stored_fragment) {
        .bytes => |bytes| checkedAdd(try materializedOffset(current_offset, current_file_offset), @intCast(bytes.data.len)),
        .isa_instruction => |instruction| checkedAdd(try materializedOffset(current_offset, current_file_offset), instruction.current_size),
        .reserve => current_file_offset,
        .alignment => |alignment| {
            const materialized = try materializedOffset(current_offset, current_file_offset);
            return alignForward(materialized, alignment.alignment);
        },
    };
}

pub fn materializedOffset(current_offset: u64, current_file_offset: u64) Error!u64 {
    return @max(current_offset, current_file_offset);
}

pub fn alignForward(value: u64, alignment: u64) Error!u64 {
    if (!isPowerOfTwoNonZero(alignment)) return error.InvalidAlignment;
    const remainder = value % alignment;
    if (remainder == 0) return value;
    return checkedAdd(value, alignment - remainder);
}

pub fn checkedAdd(a: u64, b: u64) Error!u64 {
    return std.math.add(u64, a, b) catch error.OffsetOverflow;
}

pub fn isPowerOfTwoNonZero(value: u64) bool {
    return value != 0 and (value & (value - 1)) == 0;
}

pub fn activeAddress(module: *const module_mod.Module, active: ActiveOutput) LowerError!u64 {
    const active_section = try module.sections.get(active.section_id);
    return std.math.add(u64, active_section.origin, active.offset) catch error.OffsetOverflow;
}

pub fn requireOpenOutputRegion(active: ActiveOutput) LowerError!void {
    if (active.file_aligned) return error.OutputRegionClosed;
}

pub fn discardLastActiveOutput(output_stack: *std.ArrayList(ActiveOutput)) void {
    // The API registers this only as an errdefer after a successful stack append.
    output_stack.shrinkRetainingCapacity(output_stack.items.len - 1);
}

pub fn advanceActiveOutput(active: *ActiveOutput, stored_fragment: fragment.Fragment) LowerError!void {
    active.file_offset = try nextFileOffsetFromFragment(stored_fragment, active.offset, active.file_offset);
    active.offset = try nextOffsetFromFragment(stored_fragment, active.offset);
}

pub fn sectionCursor(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u64 {
    const stored_section = try module.sections.get(section_id);
    var cursor: u64 = 0;
    for (stored_section.fragments.items) |fragment_id| {
        cursor = try nextOffsetFromFragment(module.fragments.items.items[fragment_id.index], cursor);
    }
    return cursor;
}

pub fn sectionFileCursor(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u64 {
    const stored_section = try module.sections.get(section_id);
    var cursor: u64 = 0;
    var file_cursor: u64 = 0;
    for (stored_section.fragments.items) |fragment_id| {
        const stored_fragment = module.fragments.items.items[fragment_id.index];
        file_cursor = try nextFileOffsetFromFragment(stored_fragment, cursor, file_cursor);
        cursor = try nextOffsetFromFragment(stored_fragment, cursor);
    }
    return alignForward(file_cursor, stored_section.file_size_alignment);
}

pub fn activeFragmentPosition(module: *const module_mod.Module, section_id: fragment.SectionId) LowerError!u32 {
    const stored_section = try module.sections.get(section_id);
    if (stored_section.fragments.items.len > std.math.maxInt(u32)) return error.FragmentTooLarge;
    return @intCast(stored_section.fragments.items.len);
}

test "layout cursor rejects invalid alignment" {
    try std.testing.expectError(error.InvalidAlignment, alignForward(1, 3));
}
