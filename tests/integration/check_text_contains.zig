const std = @import("std");

const Io = std.Io;
const Allocator = std.mem.Allocator;

pub fn main(init: std.process.Init) !void {
    const allocator = init.arena.allocator();
    const args = try init.minimal.args.toSlice(allocator);

    var stderr_buffer: [2048]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    if (args.len < 3) {
        try stderr.print("usage: {s} <text-file> <expected-substring>...\n", .{args[0]});
        try stderr.flush();
        std.process.exit(2);
    }

    const actual = try readFile(allocator, init.io, args[1]);
    for (args[2..]) |needle| {
        if (std.mem.indexOf(u8, actual, needle) == null) {
            try stderr.print("text fixture mismatch: {s}\nmissing: {s}\n", .{ args[1], needle });
            try stderr.flush();
            std.process.exit(1);
        }
    }
}

fn readFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    return try Io.Dir.cwd().readFileAlloc(io, path, allocator, .limited(std.math.maxInt(usize)));
}
