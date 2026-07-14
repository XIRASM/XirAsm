const std = @import("std");

const fragment_mod = @import("fragment.zig");
const layout_mod = @import("layout.zig");
const module_mod = @import("module.zig");
const source_mod = @import("source.zig");

const Allocator = std.mem.Allocator;

const bytes_per_row: usize = 8;
const byte_column_width: usize = bytes_per_row * 3;

pub const RenderOptions = struct {
    source_path: []const u8,
    output_bytes: []const u8,
};

/// Render a flat listing from the finalized output byte image.
///
/// Fragment metadata supplies source spans, addresses, and file offsets, but
/// byte rows come from `options.output_bytes`. Deferred `store.*` finalizers and
/// fixup patching mutate the final byte image after ISA fragments have already
/// been encoded, so listing output must not read bytes from original fragment
/// payloads.
pub fn renderFlat(
    allocator: Allocator,
    module: *const module_mod.Module,
    module_layout: *const layout_mod.ModuleLayout,
    options: RenderOptions,
) ![]u8 {
    var out: std.ArrayList(u8) = .empty;
    errdefer out.deinit(allocator);

    try appendFmt(&out, allocator, "XIRASM listing\n", .{});
    try appendFmt(&out, allocator, "Source: {s}\n", .{options.source_path});
    try appendFmt(&out, allocator, "Output size: {d} bytes\n", .{options.output_bytes.len});
    try appendFmt(&out, allocator, "Mode: flat\n\n", .{});
    try appendFmt(&out, allocator, " Line Address          FileOff  Bytes                    Source\n", .{});
    try appendFmt(&out, allocator, " ---- ---------------- -------- ------------------------ ----------------\n", .{});

    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind == .virtual_output) continue;

        for (section_layout.fragments) |entry| {
            const stored_fragment = try fragmentAt(module, entry.fragment);
            try appendFragmentRows(&out, allocator, module, section_layout, entry, stored_fragment, options.output_bytes);
        }
    }

    return out.toOwnedSlice(allocator);
}

fn appendFragmentRows(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    module: *const module_mod.Module,
    section_layout: layout_mod.SectionLayout,
    entry: layout_mod.FragmentLayout,
    stored_fragment: fragment_mod.Fragment,
    output_bytes: []const u8,
) !void {
    const span = fragmentSpan(stored_fragment);
    const source_text = try sourceLine(module, span);
    const location = try module.sources.location(span);
    const line = locationLine(location);
    const address = std.math.add(u64, section_layout.origin, entry.offset) catch return error.OffsetOverflow;
    const file_offset = std.math.add(u64, section_layout.file_offset, entry.offset) catch return error.OffsetOverflow;

    if (entry.file_size == 0) {
        try appendListingRow(out, allocator, .{
            .line = line,
            .address = address,
            .file_offset = null,
            .bytes = "<trimmed>",
            .source = source_text,
        });
        return;
    }

    const bytes = try outputBytesForFragment(output_bytes, file_offset, entry.file_size);
    try appendByteRows(out, allocator, line, address, file_offset, bytes, source_text);
}

fn appendByteRows(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    line: u32,
    address: u64,
    file_offset: u64,
    bytes: []const u8,
    source_text: []const u8,
) !void {
    var consumed: usize = 0;
    while (consumed < bytes.len) {
        const row_count = @min(bytes.len - consumed, bytes_per_row);
        var byte_text: std.ArrayList(u8) = .empty;
        defer byte_text.deinit(allocator);
        try appendHexBytes(&byte_text, allocator, bytes[consumed..][0..row_count]);

        const row_offset = std.math.add(u64, file_offset, consumed) catch return error.OffsetOverflow;
        const row_address = std.math.add(u64, address, consumed) catch return error.OffsetOverflow;
        try appendListingRow(out, allocator, .{
            .line = if (consumed == 0) line else 0,
            .address = row_address,
            .file_offset = row_offset,
            .bytes = byte_text.items,
            .source = if (consumed == 0) source_text else "",
        });
        consumed += row_count;
    }
}

const ListingRow = struct {
    line: u32,
    address: u64,
    file_offset: ?u64,
    bytes: []const u8,
    source: []const u8,
};

fn appendListingRow(out: *std.ArrayList(u8), allocator: Allocator, row: ListingRow) !void {
    if (row.line == 0) {
        try appendSpaces(out, allocator, 5);
    } else {
        try appendPaddedUnsigned(out, allocator, row.line, 5);
    }
    try out.append(allocator, ' ');
    try appendHexFixed(out, allocator, row.address, 16);
    try out.append(allocator, ' ');
    if (row.file_offset) |file_offset| {
        try appendHexFixed(out, allocator, file_offset, 8);
    } else {
        try appendSpaces(out, allocator, 8);
    }
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, row.bytes);
    if (row.bytes.len < byte_column_width) {
        try appendSpaces(out, allocator, byte_column_width - row.bytes.len);
    }
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, row.source);
    try out.append(allocator, '\n');
}

fn fragmentAt(module: *const module_mod.Module, id: fragment_mod.FragmentId) !fragment_mod.Fragment {
    if (id.index >= module.fragments.items.items.len) return error.InvalidFragment;
    return module.fragments.items.items[id.index];
}

fn outputBytesForFragment(output_bytes: []const u8, file_offset: u64, file_size: u64) ![]const u8 {
    const start = try fileSizeToUsize(file_offset);
    const size = try fileSizeToUsize(file_size);
    const end = std.math.add(usize, start, size) catch return error.OffsetOverflow;
    if (end > output_bytes.len) return error.InvalidFragment;
    return output_bytes[start..end];
}

fn fragmentSpan(stored_fragment: fragment_mod.Fragment) source_mod.SourceSpan {
    return switch (stored_fragment) {
        .bytes => |bytes| bytes.span,
        .reserve => |reserve| reserve.span,
        .alignment => |alignment| alignment.span,
        .isa_instruction => |instruction| instruction.span,
    };
}

fn sourceLine(module: *const module_mod.Module, span: source_mod.SourceSpan) ![]const u8 {
    const source_id = span.source orelse return "";
    const file = try module.sources.get(source_id);
    const start = lineStart(file.bytes, span.start);
    const end = lineEnd(file.bytes, start);
    return std.mem.trim(u8, file.bytes[start..end], " \t\r\n");
}

fn lineStart(bytes: []const u8, offset: u32) usize {
    var index: usize = @min(@as(usize, @intCast(offset)), bytes.len);
    while (index > 0) {
        const previous = index - 1;
        if (bytes[previous] == '\n' or bytes[previous] == '\r') break;
        index = previous;
    }
    return index;
}

fn lineEnd(bytes: []const u8, start: usize) usize {
    var index = start;
    while (index < bytes.len) : (index += 1) {
        if (bytes[index] == '\n' or bytes[index] == '\r') break;
    }
    return index;
}

fn locationLine(location: ?source_mod.SourceLocation) u32 {
    return if (location) |value| value.line else 0;
}

fn fileSizeToUsize(value: u64) !usize {
    if (value > std.math.maxInt(usize)) return error.FragmentTooLarge;
    return @intCast(value);
}

fn appendHexBytes(out: *std.ArrayList(u8), allocator: Allocator, bytes: []const u8) !void {
    for (bytes, 0..) |byte, index| {
        if (index != 0) try out.append(allocator, ' ');
        try appendHexByte(out, allocator, byte);
    }
}

fn appendHexByte(out: *std.ArrayList(u8), allocator: Allocator, byte: u8) !void {
    try out.append(allocator, hexDigit(byte >> 4));
    try out.append(allocator, hexDigit(byte & 0x0f));
}

fn hexDigit(value: u8) u8 {
    return if (value < 10) '0' + value else 'a' + (value - 10);
}

fn appendHexFixed(out: *std.ArrayList(u8), allocator: Allocator, value: u64, width: usize) !void {
    var remaining = width;
    while (remaining > 0) {
        remaining -= 1;
        const shift = remaining * 4;
        const nibble: u8 = @intCast((value >> @intCast(shift)) & 0x0f);
        try out.append(allocator, hexDigit(nibble));
    }
}

fn appendPaddedUnsigned(out: *std.ArrayList(u8), allocator: Allocator, value: u64, width: usize) !void {
    const text = try std.fmt.allocPrint(allocator, "{d}", .{value});
    defer allocator.free(text);
    if (text.len < width) try appendSpaces(out, allocator, width - text.len);
    try out.appendSlice(allocator, text);
}

fn appendSpaces(out: *std.ArrayList(u8), allocator: Allocator, count: usize) !void {
    var index: usize = 0;
    while (index < count) : (index += 1) {
        try out.append(allocator, ' ');
    }
}

fn appendFmt(out: *std.ArrayList(u8), allocator: Allocator, comptime fmt: []const u8, args: anytype) !void {
    const text = try std.fmt.allocPrint(allocator, fmt, args);
    defer allocator.free(text);
    try out.appendSlice(allocator, text);
}

test "listing renders source rows and bytes" {
    var module = try module_mod.Module.init(std.testing.allocator, .default);
    defer module.deinit();

    const source_id = try module.addSource("demo.asm",
        \\origin(0x7c00);
        \\emit.u8(0xeb);
        \\emit.u16(0xaa55);
        \\
    );
    try module.setOrigin(module.default_section, 0x7c00);
    const first = try module.emitBytes(module.default_section, &.{0xeb}, .{ .source = source_id, .start = 16, .end = 29 });
    if (first.index >= module.fragments.items.items.len) return error.InvalidFragment;
    const second = try module.emitBytes(module.default_section, &.{ 0x55, 0xaa }, .{ .source = source_id, .start = 30, .end = 47 });
    if (second.index >= module.fragments.items.items.len) return error.InvalidFragment;

    var module_layout = try layout_mod.layoutModule(std.testing.allocator, &module);
    defer module_layout.deinit(std.testing.allocator);
    const listing = try renderFlat(std.testing.allocator, &module, &module_layout, .{
        .source_path = "demo.asm",
        .output_bytes = &.{ 0xeb, 0x55, 0xaa },
    });
    defer std.testing.allocator.free(listing);

    try std.testing.expect(std.mem.indexOf(u8, listing, "XIRASM listing") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000007c00 00000000 eb") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u8(0xeb);") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000007c01 00000001 55 aa") != null);
}

test "listing renders finalized byte image instead of original fragments" {
    var module = try module_mod.Module.init(std.testing.allocator, .default);
    defer module.deinit();

    const source_id = try module.addSource("patched.asm",
        \\origin(0x4000);
        \\emit.u32(0);
        \\
    );
    try module.setOrigin(module.default_section, 0x4000);
    const fragment_id = try module.emitBytes(module.default_section, &.{ 0, 0, 0, 0 }, .{ .source = source_id, .start = 16, .end = 28 });
    if (fragment_id.index >= module.fragments.items.items.len) return error.InvalidFragment;

    var module_layout = try layout_mod.layoutModule(std.testing.allocator, &module);
    defer module_layout.deinit(std.testing.allocator);
    const listing = try renderFlat(std.testing.allocator, &module, &module_layout, .{
        .source_path = "patched.asm",
        .output_bytes = &.{ 0x78, 0x56, 0x34, 0x12 },
    });
    defer std.testing.allocator.free(listing);

    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000004000 00000000 78 56 34 12") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "00 00 00 00") == null);
}

test "listing renders ISA fragments from output sections at absolute file offsets" {
    var module = try module_mod.Module.init(std.testing.allocator, .default);
    defer module.deinit();

    const source_text =
        \\emit.u8(0xaa);
        \\xor eax, eax
        \\emit.u32(0x44332211);
        \\emit.u8(0xff);
        \\
    ;
    const source_id = try module.addSource("multi-section.asm", source_text);
    const header_span = try testSpan(source_id, source_text, "emit.u8(0xaa);");
    const instruction_span = try testSpan(source_id, source_text, "xor eax, eax");
    const data_span = try testSpan(source_id, source_text, "emit.u32(0x44332211);");
    const virtual_span = try testSpan(source_id, source_text, "emit.u8(0xff);");

    _ = try module.emitBytes(module.default_section, &.{0xaa}, header_span);

    const text_section = try module.createOutputSection(".text", 0x401000, 4);
    const instruction_id = try module.appendIsaInstruction(text_section, module.target, "xor eax, eax", instruction_span);
    try module.fragments.updateIsaInstructionFacts(std.testing.allocator, instruction_id, &.{ 0x31, 0xc0 }, 2, 2, 2, false);

    const data_section = try module.createOutputSection(".data", 0x402000, 0x10);
    _ = try module.emitBytes(data_section, &.{ 0x11, 0x22, 0x33, 0x44 }, data_span);

    const virtual_section = try module.createVirtualSection(0x500000);
    _ = try module.emitBytes(virtual_section, &.{0xff}, virtual_span);

    var module_layout = try layout_mod.layoutModule(std.testing.allocator, &module);
    defer module_layout.deinit(std.testing.allocator);
    const listing = try renderFlat(std.testing.allocator, &module, &module_layout, .{
        .source_path = "multi-section.asm",
        .output_bytes = &.{ 0xaa, 0, 0, 0, 0x31, 0xc0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0x11, 0x22, 0x33, 0x44 },
    });
    defer std.testing.allocator.free(listing);

    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000401000 00000004 31 c0") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "xor eax, eax") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000402000 00000010 11 22 33 44") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u32(0x44332211);") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u8(0xff);") == null);
}

fn testSpan(source_id: source_mod.SourceId, source_text: []const u8, needle: []const u8) !source_mod.SourceSpan {
    const start = std.mem.indexOf(u8, source_text, needle) orelse return error.MissingTestSource;
    const end = std.math.add(usize, start, needle.len) catch return error.OffsetOverflow;
    if (end > std.math.maxInt(u32)) return error.OffsetOverflow;
    return .{
        .source = source_id,
        .start = @intCast(start),
        .end = @intCast(end),
    };
}
