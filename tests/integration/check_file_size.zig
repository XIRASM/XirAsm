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
        try stderr.print("usage: {s} <actual-bin> <expected-size>\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const actual = try readFile(allocator, init.io, args[1]);
    const expected = try std.fmt.parseInt(usize, args[2], 10);
    if (actual.len != expected) {
        try stderr.print("file size mismatch: {s}\nexpected: {d}\nactual:   {d}\n", .{ args[1], expected, actual.len });
        try stderr.flush();
        std.process.exit(1);
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}
