const std = @import("std");

const fragment_mod = @import("fragment.zig");
const layout_mod = @import("layout.zig");
const module_mod = @import("module.zig");
const source_mod = @import("source.zig");

const Allocator = std.mem.Allocator;

const bytes_per_row: usize = 8;
const byte_column_width: usize = bytes_per_row * 3;

/// How much of a source line the listing prints. Generated macro bodies hold very
/// long lines, and one of them pushes the address and the call site off the
/// screen, which is exactly the information a reader came for.
const max_source_column: usize = 100;

/// What a row describes. The rows are typed because the same columns mean
/// different things: a `code` byte is an encoded instruction, a `gap` byte is in
/// the file but belongs to no fragment, and a `trim` byte is reserved space that
/// was dropped from the file and therefore has no file offset at all.
const RowKind = enum {
    code,
    data,
    reserve,
    alignment,
    gap,
    trim,

    fn name(self: RowKind) []const u8 {
        return switch (self) {
            .code => "code",
            .data => "data",
            .reserve => "resv",
            .alignment => "algn",
            .gap => "gap",
            .trim => "trim",
        };
    }
};

pub const RenderOptions = struct {
    source_path: []const u8,
    output_bytes: []const u8,
    /// How many rows of one gap are printed before the rest is summarised. A
    /// region can be placed megabytes into the file, and a listing that prints
    /// every byte of that hole stops being readable.
    max_gap_rows: usize = 4,
};

/// Render a flat listing from the finalized output byte image.
///
/// Fragment metadata supplies source spans, addresses, and file offsets, but byte
/// rows come from `options.output_bytes`. Deferred `store.*` finalizers and fixup
/// patching mutate the final byte image after ISA fragments have already been
/// encoded, so listing output must not read bytes from original fragment payloads.
///
/// Columns put the address first because that is what a reader follows: the file
/// offset is a separate fact about the same byte, not a substitute for it.
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
    try appendFmt(
        &out,
        allocator,
        "gap rows are file bytes no fragment claims; trim rows are reserved space\n" ++
            "dropped from the file, so they have no file offset. D is the expansion depth.\n\n",
        .{},
    );
    try appendFmt(&out, allocator, "              RVA      FOA  Line  Kind  D  Bytes                    Source\n", .{});
    try appendFmt(&out, allocator, " ---------------- -------- ----- ----- -- ------------------------ ----------------\n", .{});

    var covered_end: ?u64 = null;
    for (module_layout.sections) |section_layout| {
        const stored_section = try module.sections.get(section_layout.section);
        if (stored_section.kind == .virtual_output) continue;

        for (section_layout.fragments) |entry| {
            const stored_fragment = try fragmentAt(module, entry.fragment);
            const kind = fragmentKind(stored_fragment, entry.file_size);
            const address = std.math.add(u64, section_layout.origin, entry.offset) catch return error.OffsetOverflow;
            const file_offset = std.math.add(u64, section_layout.file_offset, entry.offset) catch return error.OffsetOverflow;

            if (entry.file_size != 0) {
                if (covered_end) |previous| {
                    if (file_offset > previous) {
                        try appendGapRows(&out, allocator, options, previous, file_offset);
                    }
                }
                covered_end = std.math.add(u64, file_offset, entry.file_size) catch return error.OffsetOverflow;
            }

            try appendFragmentRows(&out, allocator, module, .{
                .kind = kind,
                .address = address,
                .file_offset = file_offset,
                .file_size = entry.file_size,
                .logical_size = entry.logical_size,
                .span = fragmentSpan(stored_fragment),
                .depth = expansionDepth(module, fragmentSpan(stored_fragment)),
            }, options);
        }
    }

    return out.toOwnedSlice(allocator);
}

fn fragmentKind(stored_fragment: fragment_mod.Fragment, file_size: u64) RowKind {
    return switch (stored_fragment) {
        .isa_instruction => .code,
        .bytes => .data,
        .alignment => .alignment,
        // A reservation that produced no file bytes was trimmed from the tail.
        .reserve => if (file_size == 0) .trim else .reserve,
    };
}

const FragmentRow = struct {
    kind: RowKind,
    address: u64,
    file_offset: u64,
    file_size: u64,
    logical_size: u64,
    span: source_mod.SourceSpan,
    depth: usize,
};

fn appendFragmentRows(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    module: *const module_mod.Module,
    row: FragmentRow,
    options: RenderOptions,
) !void {
    const source_text = try sourceLine(module, row.span);
    const location = try module.sources.location(row.span);
    const line = locationLine(location);
    const expansion = try expansionNote(allocator, module, row.span);
    defer if (expansion) |text| allocator.free(text);

    if (row.file_size == 0) {
        // Reserved space that never reached the file: there is no byte to show
        // and no file offset to point at, so the row says so instead of printing
        // a zero that would claim the file holds one.
        var text: std.ArrayList(u8) = .empty;
        defer text.deinit(allocator);
        if (expansion) |note| {
            try text.appendSlice(allocator, note);
            if (source_text.len != 0) try text.appendSlice(allocator, "  ");
        }
        try appendSourceColumn(&text, allocator, source_text);
        try appendListingRow(out, allocator, .{
            .line = line,
            .address = row.address,
            .file_offset = null,
            .kind = row.kind,
            .depth = row.depth,
            .bytes = "--",
            .source = text.items,
            .note = null,
        });
        return;
    }

    const bytes = try outputBytesForFragment(options.output_bytes, row.file_offset, row.file_size);
    try appendByteRows(out, allocator, row, line, bytes, source_text, expansion);
}

fn appendGapRows(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    options: RenderOptions,
    start: u64,
    end: u64,
) !void {
    const length = end - start;
    const full_rows = length / bytes_per_row;
    const printed_rows = if (full_rows > options.max_gap_rows) options.max_gap_rows else full_rows;
    const printed_bytes = printed_rows * bytes_per_row;

    if (printed_bytes != 0) {
        const bytes = try outputBytesForFragment(options.output_bytes, start, printed_bytes);
        var consumed: usize = 0;
        while (consumed < bytes.len) {
            const row_count = @min(bytes.len - consumed, bytes_per_row);
            var byte_text: std.ArrayList(u8) = .empty;
            defer byte_text.deinit(allocator);
            try appendHexBytes(&byte_text, allocator, bytes[consumed..][0..row_count]);
            const row_offset = std.math.add(u64, start, consumed) catch return error.OffsetOverflow;
            try appendListingRow(out, allocator, .{
                .line = 0,
                .address = row_offset,
                .file_offset = row_offset,
                .kind = .gap,
                .depth = 0,
                .bytes = byte_text.items,
                .source = "",
                .note = null,
            });
            consumed += row_count;
        }
    }

    const remaining = length - printed_bytes;
    if (remaining != 0) {
        var summary: std.ArrayList(u8) = .empty;
        defer summary.deinit(allocator);
        try appendFmt(&summary, allocator, "({d} more gap bytes)", .{remaining});
        const summary_offset = std.math.add(u64, start, printed_bytes) catch return error.OffsetOverflow;
        try appendListingRow(out, allocator, .{
            .line = 0,
            .address = summary_offset,
            .file_offset = summary_offset,
            .kind = .gap,
            .depth = 0,
            .bytes = "",
            .source = summary.items,
            .note = null,
        });
    }
}

fn appendByteRows(
    out: *std.ArrayList(u8),
    allocator: Allocator,
    row: FragmentRow,
    line: u32,
    bytes: []const u8,
    source_text: []const u8,
    expansion_note: ?[]const u8,
) !void {
    var consumed: usize = 0;
    while (consumed < bytes.len) {
        const row_count = @min(bytes.len - consumed, bytes_per_row);
        var byte_text: std.ArrayList(u8) = .empty;
        defer byte_text.deinit(allocator);
        try appendHexBytes(&byte_text, allocator, bytes[consumed..][0..row_count]);

        const row_offset = std.math.add(u64, row.file_offset, consumed) catch return error.OffsetOverflow;
        const row_address = std.math.add(u64, row.address, consumed) catch return error.OffsetOverflow;
        var combined: std.ArrayList(u8) = .empty;
        defer combined.deinit(allocator);
        if (consumed == 0) {
            // The call site comes first: for an expanded line it is the part a
            // reader can act on, and the definition body that follows is often a
            // long generated line.
            if (expansion_note) |note| {
                try combined.appendSlice(allocator, note);
                if (source_text.len != 0) try combined.appendSlice(allocator, "  ");
            }
            try appendSourceColumn(&combined, allocator, source_text);
        }

        try appendListingRow(out, allocator, .{
            .line = if (consumed == 0) line else 0,
            .address = row_address,
            .file_offset = row_offset,
            .kind = row.kind,
            .depth = row.depth,
            .bytes = byte_text.items,
            .source = combined.items,
            .note = null,
        });
        consumed += row_count;
    }
}

const ListingRow = struct {
    line: u32,
    address: u64,
    file_offset: ?u64,
    kind: RowKind,
    depth: usize,
    bytes: []const u8,
    source: []const u8,
    note: ?[]const u8,
};

fn appendListingRow(out: *std.ArrayList(u8), allocator: Allocator, row: ListingRow) !void {
    try appendHexFixed(out, allocator, row.address, 16);
    try out.append(allocator, ' ');
    if (row.file_offset) |file_offset| {
        try appendHexFixed(out, allocator, file_offset, 8);
    } else {
        try appendSpaces(out, allocator, 8);
    }
    try out.append(allocator, ' ');
    if (row.line == 0) {
        try appendSpaces(out, allocator, 5);
    } else {
        try appendPaddedUnsigned(out, allocator, row.line, 5);
    }
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, row.kind.name());
    try appendSpaces(out, allocator, 6 - row.kind.name().len);
    try out.append(allocator, ' ');
    try appendPaddedUnsigned(out, allocator, row.depth, 2);
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, row.bytes);
    if (row.bytes.len < byte_column_width) {
        try appendSpaces(out, allocator, byte_column_width - row.bytes.len);
    }
    try out.append(allocator, ' ');
    try out.appendSlice(allocator, row.source);
    if (row.note) |note| {
        if (row.source.len != 0) try out.append(allocator, ' ');
        try out.appendSlice(allocator, note);
    }
    try out.append(allocator, '\n');
}

/// How many macro or function expansions produced this span. Zero means the line
/// was written where it appears; a higher number means the reader is looking at a
/// definition body that was expanded, which is what makes a listing of a macro
/// library readable instead of a wall of instructions.
fn expansionDepth(module: *const module_mod.Module, span: source_mod.SourceSpan) usize {
    var depth: usize = 0;
    var index = span.expansion;
    while (index) |current| {
        if (current >= module.diagnostics.expansions.items.len) break;
        depth += 1;
        index = module.diagnostics.expansions.items[current].invocation.expansion;
    }
    return depth;
}

/// `; from <path>:<line>` for an expanded line, naming the outermost call site so
/// the reader can find the source that produced it.
fn expansionNote(
    allocator: Allocator,
    module: *const module_mod.Module,
    span: source_mod.SourceSpan,
) !?[]u8 {
    var index: ?u32 = span.expansion;
    var outermost: ?source_mod.SourceSpan = null;
    while (index) |current| {
        if (current >= module.diagnostics.expansions.items.len) break;
        const expansion = module.diagnostics.expansions.items[current];
        outermost = expansion.invocation;
        index = expansion.invocation.expansion;
    }
    const invocation = outermost orelse return null;
    const location = (try module.sources.location(invocation)) orelse return null;
    // Only the file name: the header already names the main source, and a full
    // path in every expanded row pushes the row past a readable width.
    return try std.fmt.allocPrint(allocator, "; from {s}:{d}", .{ std.fs.path.basename(location.path), location.line });
}

fn appendSourceColumn(out: *std.ArrayList(u8), allocator: Allocator, text: []const u8) !void {
    if (text.len <= max_source_column) {
        try out.appendSlice(allocator, text);
        return;
    }
    try out.appendSlice(allocator, text[0..max_source_column]);
    try out.appendSlice(allocator, " ...");
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
    // The address leads the row, the file offset follows it, and the kind says
    // which of the two facts the row is showing.
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000007c00 00000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "data") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "eb") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u8(0xeb);") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000007c01 00000001") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "55 aa") != null);
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

    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000004000 00000000") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "78 56 34 12") != null);
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

    // The instruction is the only row typed `code`, and the gap the sections
    // leave in the file is listed as its own bytes rather than skipped.
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000401000 00000004") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "code") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "xor eax, eax") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "0000000000402000 00000010") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "11 22 33 44") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u8(0xff);") == null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "gap") != null);
}

test "a trimmed reservation is listed without a file offset" {
    var module = try module_mod.Module.init(std.testing.allocator, .default);
    defer module.deinit();

    const source_text =
        \\origin(0x1000);
        \\emit.u8(0x11);
        \\reserve(4);
        \\
    ;
    const source_id = try module.addSource("tail.asm", source_text);
    try module.setOrigin(module.default_section, 0x1000);
    _ = try module.emitBytes(module.default_section, &.{0x11}, try testSpan(source_id, source_text, "emit.u8(0x11);"));
    _ = try module.reserve(module.default_section, 4, 1, try testSpan(source_id, source_text, "reserve(4);"));

    var module_layout = try layout_mod.layoutModule(std.testing.allocator, &module);
    defer module_layout.deinit(std.testing.allocator);
    const listing = try renderFlat(std.testing.allocator, &module, &module_layout, .{
        .source_path = "tail.asm",
        .output_bytes = &.{0x11},
    });
    defer std.testing.allocator.free(listing);

    // `--` and no file offset: the four bytes are a logical fact, not file bytes.
    try std.testing.expect(std.mem.indexOf(u8, listing, "trim") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "--") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "reserve(4);") != null);
}

test "an expanded line carries its depth and the call site that produced it" {
    var module = try module_mod.Module.init(std.testing.allocator, .default);
    defer module.deinit();

    const source_text =
        \\macro twice() {
        \\    emit.u8(0x22)
        \\}
        \\twice
        \\
    ;
    const source_id = try module.addSource("macro.asm", source_text);
    const definition_span = try testSpan(source_id, source_text, "emit.u8(0x22)");
    // `twice` also appears in the definition header, so the invocation is found by
    // the line that holds nothing but the call.
    const invocation_span = try testSpan(source_id, source_text, "twice\n");

    const expansion = try module.diagnostics.beginExpansion(std.testing.allocator, invocation_span, definition_span, .macro);
    var body_span = definition_span;
    body_span.expansion = expansion;
    _ = try module.emitBytes(module.default_section, &.{0x22}, body_span);

    var module_layout = try layout_mod.layoutModule(std.testing.allocator, &module);
    defer module_layout.deinit(std.testing.allocator);
    const listing = try renderFlat(std.testing.allocator, &module, &module_layout, .{
        .source_path = "macro.asm",
        .output_bytes = &.{0x22},
    });
    defer std.testing.allocator.free(listing);

    try std.testing.expect(std.mem.indexOf(u8, listing, "emit.u8(0x22)") != null);
    try std.testing.expect(std.mem.indexOf(u8, listing, "; from macro.asm:4") != null);
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
