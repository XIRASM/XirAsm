const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [1024]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len != 3) {
        try stderr.print("usage: {s} <actual-bin> <expected-hex>\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const actual = try readFile(allocator, init.io, args[1]);
    const expected = try parseHex(allocator, args[2]);

    if (!std.mem.eql(u8, actual, expected)) {
        try stderr.print("fixture mismatch: {s}\nexpected: {s}\nactual:   ", .{ args[1], args[2] });
        for (actual) |byte| try stderr.print("{x:0>2}", .{byte});
        try stderr.print("\n", .{});
        try stderr.flush();
        std.process.exit(1);
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}

fn parseHex(allocator: Allocator, text: []const u8) ![]u8 {
    if (text.len % 2 != 0) return error.InvalidHex;

    const bytes = try allocator.alloc(u8, text.len / 2);
    errdefer allocator.free(bytes);

    var index: usize = 0;
    while (index < bytes.len) : (index += 1) {
        const hi = try hexNibble(text[index * 2]);
        const lo = try hexNibble(text[index * 2 + 1]);
        bytes[index] = (hi << 4) | lo;
    }
    return bytes;
}

fn hexNibble(byte: u8) !u8 {
    if (byte >= '0' and byte <= '9') return byte - '0';
    if (byte >= 'a' and byte <= 'f') return byte - 'a' + 10;
    if (byte >= 'A' and byte <= 'F') return byte - 'A' + 10;
    return error.InvalidHex;
}
