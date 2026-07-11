const std = @import("std");

const layout = @import("../layout.zig");
const module_file = @import("../module.zig");
const output_image = @import("image.zig");
const output_result = @import("result.zig");

const Allocator = std.mem.Allocator;

pub const OutputKind = enum {
    flat,
};

pub const WriterResult = output_result.WriterResult;

pub fn writeOutput(
    allocator: Allocator,
    kind: OutputKind,
    module: *const module_file.Module,
    module_layout: *const layout.ModuleLayout,
) !WriterResult {
    return switch (kind) {
        .flat => writeFlat(allocator, module, module_layout),
    };
}

fn writeFlat(
    allocator: Allocator,
    module: *const module_file.Module,
    module_layout: *const layout.ModuleLayout,
) !WriterResult {
    const output_len = try sizeToUsize(try flatOutputSize(module, module_layout));
    const bytes = try allocator.alloc(u8, output_len);
    errdefer allocator.free(bytes);

    @memset(bytes, 0);
    try materializeFlatSections(bytes, module, module_layout);

    const regions = try flatImageRegions(allocator, module, module_layout);
    errdefer allocator.free(regions);

    return .{ .bytes = bytes, .regions = regions };
}

fn flatImageRegions(
    allocator: Allocator,
    module: *const module_file.Module,
    module_layout: *const layout.ModuleLayout,
) ![]output_image.ImageRegion {
    var count: usize = 0;
    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind != .virtual_output) count += 1;
    }

    const regions = try allocator.alloc(output_image.ImageRegion, count);
    errdefer allocator.free(regions);

    var index: usize = 0;
    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind == .virtual_output) continue;
        regions[index] = .{
            .section = section_layout.section,
            .origin = section_layout.origin,
            .file_offset = section_layout.file_offset,
            .logical_size = section_layout.logical_size,
            .file_size = section_layout.file_size,
        };
        index += 1;
    }
    return regions;
}

fn flatOutputSize(module: *const module_file.Module, module_layout: *const layout.ModuleLayout) !u64 {
    var output_size: u64 = 0;
    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind == .virtual_output) continue;

        const section_end = std.math.add(u64, section_layout.file_offset, section_layout.file_size) catch return error.OffsetOverflow;
        output_size = @max(output_size, section_end);
    }
    return output_size;
}

fn materializeFlatSections(bytes: []u8, module: *const module_file.Module, module_layout: *const layout.ModuleLayout) !void {
    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind == .virtual_output) continue;

        for (section_layout.fragments) |entry| {
            if (entry.file_size == 0) continue;

            const start_offset = std.math.add(u64, section_layout.file_offset, entry.offset) catch return error.OffsetOverflow;
            const start = try sizeToUsize(start_offset);
            const file_size = try sizeToUsize(entry.file_size);
            const end = std.math.add(usize, start, file_size) catch return error.OffsetOverflow;
            if (end > bytes.len) return error.InvalidFragment;
            if (entry.fragment.index >= module.fragments.items.items.len) return error.InvalidFragment;

            switch (module.fragments.items.items[entry.fragment.index]) {
                .bytes => |fragment| {
                    if (file_size > fragment.data.len) return error.InvalidFragment;
                    @memcpy(bytes[start..end], fragment.data[0..file_size]);
                },
                .isa_instruction => |fragment| {
                    if (file_size > fragment.encoded_bytes.len) return error.InvalidFragment;
                    @memcpy(bytes[start..end], fragment.encoded_bytes[0..file_size]);
                },
                .alignment => |fragment| @memset(bytes[start..end], fragment.fill),
                .reserve => {},
            }
        }
    }
}

fn sizeToUsize(value: u64) !usize {
    if (value > std.math.maxInt(usize)) return error.OutputTooLarge;
    return @intCast(value);
}
