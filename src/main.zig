const std = @import("std");
const Io = std.Io;

const xirasm = @import("xirasm");
const build_options = @import("build_options");

const Allocator = std.mem.Allocator;

const Command = union(enum) {
    assemble: AssembleOptions,
    build: BuildOptions,
    init: InitOptions,
    help: HelpTopic,
};

const HelpTopic = enum {
    overview,
    init,
    targets,
};

const ProgressMode = enum {
    auto,
    always,
    never,
};

const TimingMode = enum {
    off,
    summary,
    phases,

    fn enabled(self: TimingMode) bool {
        return self != .off;
    }

    fn tracePhases(self: TimingMode) bool {
        return self == .phases;
    }
};

const CliOptions = struct {
    source_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    listing_path: ?[]const u8 = null,
    progress: ProgressMode = .auto,
    timings: TimingMode = .off,
    show_help: bool = false,
    show_version: bool = false,
    target: xirasm.Target = xirasm.Target.default,
};

const AssembleOptions = CliOptions;

const BuildOptions = struct {
    source_path: ?[]const u8 = null,
    output_path: ?[]const u8 = null,
    listing_path: ?[]const u8 = null,
    progress: ProgressMode = .auto,
    timings: TimingMode = .off,
    target: xirasm.Target = xirasm.Target.default,
};

const InitTargetConfig = struct {
    isa: []const u8 = "x86-64",
    bits: u16 = 64,
    os: []const u8 = "bin",
    abi: []const u8 = "none",
};

const InitTemplateKind = enum {
    flat_x86_32,
    flat_x86_64,
    flat_riscv32,
    flat_riscv64,
    pe32,
    pe64,
    elf32,
    elf64,
};

const InitOptions = struct {
    name: ?[]const u8 = null,
    dir_path: ?[]const u8 = null,
    target: InitTargetConfig = .{},
    force: bool = false,
};

const CliParseIssue = union(enum) {
    missing_source_path,
    missing_output_path,
    missing_listing_path,
    missing_init_value: []const u8,
    multiple_source_paths: struct {
        first: []const u8,
        second: []const u8,
    },
    multiple_init_paths: struct {
        first: []const u8,
        second: []const u8,
    },
    unknown_option: []const u8,
    unknown_help_topic: []const u8,
    invalid_target: []const u8,
    invalid_init_value: struct {
        key: []const u8,
        value: []const u8,
    },
    misplaced_subcommand: []const u8,
};

const ParseCliResult = union(enum) {
    ok: Command,
    err: CliParseIssue,
};

const AssembledFlat = struct {
    module: xirasm.Module,
    layout: xirasm.ModuleLayout,
    bytes: []u8,
    encoded_count: usize,
    pending_fixups: usize,

    pub fn deinit(self: *AssembledFlat, allocator: Allocator) void {
        allocator.free(self.bytes);
        self.layout.deinit(allocator);
        self.module.deinit();
        self.* = undefined;
    }
};

const TimingStage = enum {
    read_source,
    parse_lower,
    encode,
    fixup_resolve,
    layout,
    materialize,
    patch,
    defer_finalizers,
    write_output,
    write_listing,
};

const TimingRecord = struct {
    stage: TimingStage,
    elapsed_ns: i96,
};

const TimingTrace = struct {
    const max_records = 32;

    start_ns: i96,
    records: [max_records]TimingRecord = undefined,
    record_count: usize = 0,

    fn init(io: Io) TimingTrace {
        return .{ .start_ns = nowNs(io) };
    }

    fn add(self: *TimingTrace, stage: TimingStage, elapsed_ns: i96) void {
        const safe_elapsed = @max(elapsed_ns, 0);
        for (self.records[0..self.record_count]) |*record| {
            if (record.stage == stage) {
                record.elapsed_ns = std.math.add(i96, record.elapsed_ns, safe_elapsed) catch std.math.maxInt(i96);
                return;
            }
        }
        if (self.record_count >= self.records.len) return;
        self.records[self.record_count] = .{
            .stage = stage,
            .elapsed_ns = safe_elapsed,
        };
        self.record_count += 1;
    }

    fn totalNs(self: *const TimingTrace, io: Io) i96 {
        return elapsedSince(self.start_ns, nowNs(io));
    }
};

const AssembledFlatCore = xirasm.assembly.FlatResult;

fn finishAssembledFlat(module: *xirasm.Module, core: AssembledFlatCore, module_owned: *bool) AssembledFlat {
    module_owned.* = false;
    return .{
        .module = module.*,
        .layout = core.layout,
        .bytes = core.bytes,
        .encoded_count = core.encoded_count,
        .pending_fixups = core.pending_fixups,
    };
}

const ResolvedBuildOptions = struct {
    source_path: []const u8,
    output_path: []const u8,
    target: xirasm.Target,
    progress: ProgressMode,
    timings: TimingMode,
};

const SourceInput = struct {
    path: []const u8,
    bytes: []const u8,
};

const FileIncludeResolver = struct {
    io: Io,
    project_root: ?[]const u8 = null,
    install_include_root: ?[]const u8 = null,
};

pub fn main(init: std.process.Init) !void {
    const arena = init.arena.allocator();
    const args = try init.minimal.args.toSlice(arena);

    var stdout_buffer: [4096]u8 = undefined;
    var stdout_file_writer = Io.File.stdout().writer(init.io, &stdout_buffer);
    const stdout = &stdout_file_writer.interface;

    var stderr_buffer: [4096]u8 = undefined;
    var stderr_file_writer = Io.File.stderr().writer(init.io, &stderr_buffer);
    const stderr = &stderr_file_writer.interface;

    const command = switch (parseCliArgs(args)) {
        .ok => |ok| ok,
        .err => |issue| {
            try writeCliParseIssue(stderr, issue);
            try writeHelpText(stderr);
            try stderr.flush();
            std.process.exit(2);
        },
    };

    switch (command) {
        .help => |topic| {
            try writeHelpTopic(stdout, topic);
            try stdout.flush();
        },
        .assemble => |options| try runAssembleCommand(arena, init.gpa, init.io, stdout, stderr, options),
        .build => |options| try runBuildCommand(arena, init.gpa, init.io, stdout, stderr, options),
        .init => |options| try runInitCommand(arena, init.io, stdout, options),
    }
}

fn parseCliArgs(args: []const []const u8) ParseCliResult {
    if (args.len > 1 and std.mem.eql(u8, args[1], "help")) {
        return parseHelpArgs(args[2..]);
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "init")) {
        return parseInitArgs(args[2..]);
    }
    if (args.len > 1 and std.mem.eql(u8, args[1], "build")) {
        return parseBuildArgs(args[2..]);
    }

    var options = AssembleOptions{};
    var index: usize = 1;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            options.show_help = true;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-V") or std.mem.eql(u8, arg, "--version")) {
            options.show_version = true;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--progress")) {
            options.progress = .always;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-progress")) {
            options.progress = .never;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--timings")) {
            options.timings = .summary;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--trace-phases")) {
            options.timings = .phases;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-o")) {
            if (index + 1 >= args.len) return .{ .err = .missing_output_path };
            if (std.mem.startsWith(u8, args[index + 1], "-")) return .{ .err = .missing_output_path };
            options.output_path = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--listing") or std.mem.eql(u8, arg, "--lst")) {
            if (index + 1 >= args.len) return .{ .err = .missing_listing_path };
            if (std.mem.startsWith(u8, args[index + 1], "-")) return .{ .err = .missing_listing_path };
            options.listing_path = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--target")) {
            if (index + 1 >= args.len) return .{ .err = .{ .invalid_target = arg } };
            options.target = parseTarget(args[index + 1]) orelse return .{ .err = .{ .invalid_target = args[index + 1] } };
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "build")) {
            return .{ .err = .{ .misplaced_subcommand = arg } };
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            return .{ .err = .{ .unknown_option = arg } };
        }
        if (options.source_path) |first| {
            return .{ .err = .{ .multiple_source_paths = .{ .first = first, .second = arg } } };
        }
        options.source_path = arg;
        index += 1;
    }

    return .{ .ok = .{ .assemble = options } };
}

fn parseBuildArgs(args: []const []const u8) ParseCliResult {
    var options = BuildOptions{};
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .ok = .{ .help = .overview } };
        }
        if (std.mem.eql(u8, arg, "--progress")) {
            options.progress = .always;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--no-progress")) {
            options.progress = .never;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--timings")) {
            options.timings = .summary;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--trace-phases")) {
            options.timings = .phases;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "-o")) {
            if (index + 1 >= args.len) return .{ .err = .missing_output_path };
            if (std.mem.startsWith(u8, args[index + 1], "-")) return .{ .err = .missing_output_path };
            options.output_path = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--listing") or std.mem.eql(u8, arg, "--lst")) {
            if (index + 1 >= args.len) return .{ .err = .missing_listing_path };
            if (std.mem.startsWith(u8, args[index + 1], "-")) return .{ .err = .missing_listing_path };
            options.listing_path = args[index + 1];
            index += 2;
            continue;
        }
        if (std.mem.eql(u8, arg, "--target")) {
            if (index + 1 >= args.len) return .{ .err = .{ .invalid_target = arg } };
            options.target = parseTarget(args[index + 1]) orelse return .{ .err = .{ .invalid_target = args[index + 1] } };
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            return .{ .err = .{ .unknown_option = arg } };
        }
        if (options.source_path) |first| {
            return .{ .err = .{ .multiple_source_paths = .{ .first = first, .second = arg } } };
        }
        options.source_path = arg;
        index += 1;
    }

    return .{ .ok = .{ .build = options } };
}

fn parseInitArgs(args: []const []const u8) ParseCliResult {
    var options = InitOptions{};
    var index: usize = 0;
    while (index < args.len) {
        const arg = args[index];
        if (std.mem.eql(u8, arg, "-h") or std.mem.eql(u8, arg, "--help")) {
            return .{ .ok = .{ .help = .overview } };
        }
        if (std.mem.eql(u8, arg, "--force")) {
            options.force = true;
            index += 1;
            continue;
        }
        if (std.mem.eql(u8, arg, "--name") or
            std.mem.eql(u8, arg, "--dir") or
            std.mem.eql(u8, arg, "--target") or
            std.mem.eql(u8, arg, "--isa") or
            std.mem.eql(u8, arg, "--arch") or
            std.mem.eql(u8, arg, "--bits") or
            std.mem.eql(u8, arg, "--bit") or
            std.mem.eql(u8, arg, "--os") or
            std.mem.eql(u8, arg, "--abi"))
        {
            if (index + 1 >= args.len) return .{ .err = .{ .missing_init_value = arg } };
            const value = args[index + 1];
            if (std.mem.startsWith(u8, value, "--")) return .{ .err = .{ .missing_init_value = arg } };
            if (std.mem.eql(u8, arg, "--name")) {
                if (!isValidProjectName(value)) return .{ .err = .{ .invalid_init_value = .{ .key = arg, .value = value } } };
                options.name = value;
            } else if (std.mem.eql(u8, arg, "--dir")) {
                if (options.dir_path) |first| {
                    return .{ .err = .{ .multiple_init_paths = .{ .first = first, .second = value } } };
                }
                options.dir_path = value;
            } else if (std.mem.eql(u8, arg, "--target")) {
                options.target = parseInitTarget(value) orelse return .{ .err = .{ .invalid_target = value } };
            } else if (std.mem.eql(u8, arg, "--isa") or std.mem.eql(u8, arg, "--arch")) {
                options.target = parseInitIsa(value, options.target) orelse return .{ .err = .{ .invalid_target = value } };
            } else if (std.mem.eql(u8, arg, "--bits") or std.mem.eql(u8, arg, "--bit")) {
                const bits = parseInitBits(value) orelse return .{ .err = .{ .invalid_init_value = .{ .key = arg, .value = value } } };
                options.target.bits = bits;
            } else if (std.mem.eql(u8, arg, "--os")) {
                if (!isValidInitTargetToken(value)) return .{ .err = .{ .invalid_init_value = .{ .key = arg, .value = value } } };
                options.target.os = value;
            } else {
                if (!isValidInitTargetToken(value)) return .{ .err = .{ .invalid_init_value = .{ .key = arg, .value = value } } };
                options.target.abi = value;
            }
            index += 2;
            continue;
        }
        if (std.mem.startsWith(u8, arg, "-")) {
            return .{ .err = .{ .unknown_option = arg } };
        }
        if (options.dir_path) |first| {
            return .{ .err = .{ .multiple_init_paths = .{ .first = first, .second = arg } } };
        }
        options.dir_path = arg;
        index += 1;
    }

    return .{ .ok = .{ .init = options } };
}

fn parseHelpArgs(args: []const []const u8) ParseCliResult {
    if (args.len == 0) return .{ .ok = .{ .help = .overview } };
    if (args.len > 1) return .{ .err = .{ .unknown_help_topic = args[1] } };
    if (std.mem.eql(u8, args[0], "init")) return .{ .ok = .{ .help = .init } };
    if (std.mem.eql(u8, args[0], "targets")) return .{ .ok = .{ .help = .targets } };
    return .{ .err = .{ .unknown_help_topic = args[0] } };
}

fn parseTarget(value: []const u8) ?xirasm.Target {
    if (std.mem.eql(u8, value, "x86-64") or
        std.mem.eql(u8, value, "x86_64") or
        std.mem.eql(u8, value, "x64"))
    {
        return .{ .x86 = .{ .mode_bits = 64 } };
    }
    if (std.mem.eql(u8, value, "x86") or std.mem.eql(u8, value, "x86-32")) {
        return .{ .x86 = .{ .mode_bits = 32 } };
    }
    if (std.mem.eql(u8, value, "rv64") or std.mem.eql(u8, value, "riscv64")) {
        return .{ .riscv = .{ .xlen = 64 } };
    }
    if (std.mem.eql(u8, value, "rv32") or std.mem.eql(u8, value, "riscv32")) {
        return .{ .riscv = .{ .xlen = 32 } };
    }
    if (std.mem.eql(u8, value, "spv") or std.mem.eql(u8, value, "spirv")) {
        return xirasm.Target.spv();
    }
    return null;
}

fn parseInitTarget(value: []const u8) ?InitTargetConfig {
    if (std.mem.eql(u8, value, "x86-64") or
        std.mem.eql(u8, value, "x86_64") or
        std.mem.eql(u8, value, "x64"))
    {
        return .{ .isa = "x86-64", .bits = 64, .os = "bin", .abi = "none" };
    }
    if (std.mem.eql(u8, value, "x86") or std.mem.eql(u8, value, "x86-32")) {
        return .{ .isa = "x86", .bits = 32, .os = "bin", .abi = "none" };
    }
    if (std.mem.eql(u8, value, "rv64") or std.mem.eql(u8, value, "riscv64")) {
        return .{ .isa = "riscv64", .bits = 64, .os = "none", .abi = "none" };
    }
    if (std.mem.eql(u8, value, "rv32") or std.mem.eql(u8, value, "riscv32")) {
        return .{ .isa = "riscv32", .bits = 32, .os = "none", .abi = "none" };
    }
    return null;
}

fn parseInitIsa(value: []const u8, current: InitTargetConfig) ?InitTargetConfig {
    if (std.mem.eql(u8, value, "x86-64") or
        std.mem.eql(u8, value, "x86_64") or
        std.mem.eql(u8, value, "x64"))
    {
        return .{ .isa = "x86-64", .bits = 64, .os = current.os, .abi = current.abi };
    }
    if (std.mem.eql(u8, value, "x86") or std.mem.eql(u8, value, "x86-32")) {
        return .{ .isa = "x86", .bits = 32, .os = current.os, .abi = current.abi };
    }
    if (std.mem.eql(u8, value, "riscv64") or std.mem.eql(u8, value, "rv64")) {
        return .{ .isa = "riscv64", .bits = 64, .os = current.os, .abi = current.abi };
    }
    if (std.mem.eql(u8, value, "riscv32") or std.mem.eql(u8, value, "rv32")) {
        return .{ .isa = "riscv32", .bits = 32, .os = current.os, .abi = current.abi };
    }
    return null;
}

fn parseInitBits(value: []const u8) ?u16 {
    if (std.mem.eql(u8, value, "64")) return 64;
    if (std.mem.eql(u8, value, "32")) return 32;
    return null;
}

fn isValidInitTargetToken(value: []const u8) bool {
    if (value.len == 0) return false;
    for (value) |byte| {
        if ((byte >= 'a' and byte <= 'z') or
            (byte >= 'A' and byte <= 'Z') or
            (byte >= '0' and byte <= '9') or
            byte == '_' or
            byte == '-' or
            byte == '.')
        {
            continue;
        }
        return false;
    }
    return true;
}

fn targetName(target: xirasm.Target) []const u8 {
    return switch (target) {
        .x86 => |cfg| if (cfg.mode_bits == 64) "x86-64" else "x86",
        .riscv => |cfg| if (cfg.xlen == 64) "rv64" else "rv32",
        .spirv => "spv",
    };
}

fn timingStageName(stage: TimingStage) []const u8 {
    return switch (stage) {
        .read_source => "read_source",
        .parse_lower => "parse_lower",
        .encode => "encode",
        .fixup_resolve => "fixup_resolve",
        .layout => "layout",
        .materialize => "materialize",
        .patch => "patch",
        .defer_finalizers => "defer_finalizers",
        .write_output => "write_output",
        .write_listing => "write_listing",
    };
}

fn nowNs(io: Io) i96 {
    return Io.Clock.awake.now(io).nanoseconds;
}

fn elapsedSince(start_ns: i96, end_ns: i96) i96 {
    if (end_ns < start_ns) return 0;
    return end_ns - start_ns;
}

fn writeElapsedMilliseconds(writer: *Io.Writer, elapsed_ns: i96) !void {
    const safe_ns = @max(elapsed_ns, 0);
    const whole_ms = @divTrunc(safe_ns, std.time.ns_per_ms);
    const fractional_ms = @divTrunc(@mod(safe_ns, std.time.ns_per_ms), std.time.ns_per_us);
    try writer.print("{d}.{d:0>3}", .{ whole_ms, fractional_ms });
}

fn writeTimingReport(
    writer: *Io.Writer,
    title: []const u8,
    target: xirasm.Target,
    assembled: *const AssembledFlat,
    trace: *const TimingTrace,
    total_ns: i96,
    mode: TimingMode,
) !void {
    try writer.print("{s}_timings elapsed_ms=", .{title});
    try writeElapsedMilliseconds(writer, total_ns);
    try writer.print(
        " bytes={d} instruction_fragments={d} pending_fixups={d} target={s}\n",
        .{ assembled.bytes.len, assembled.encoded_count, assembled.pending_fixups, targetName(target) },
    );
    if (mode.tracePhases()) {
        for (trace.records[0..trace.record_count]) |record| {
            try writer.print("  phase={s} elapsed_ms=", .{timingStageName(record.stage)});
            try writeElapsedMilliseconds(writer, record.elapsed_ns);
            try writer.writeByte('\n');
        }
    }
}

fn runAssembleCommand(
    arena: Allocator,
    gpa: Allocator,
    io: Io,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    options: AssembleOptions,
) !void {
    if (options.show_help) {
        try writeHelpText(stdout);
        try stdout.flush();
        return;
    }
    if (options.show_version) {
        try writeVersionText(stdout);
        try stdout.flush();
        return;
    }

    const source_path = options.source_path orelse {
        try writeCliParseIssue(stderr, .missing_source_path);
        try writeHelpText(stderr);
        try stderr.flush();
        std.process.exit(2);
    };

    const progress_enabled = options.progress != .never;
    var progress_root = if (progress_enabled)
        std.Progress.start(io, .{ .root_name = "xirasm assemble", .estimated_total_items = 3 })
    else
        std.Progress.Node.none;
    defer progress_root.end();

    var timing_trace = TimingTrace.init(io);

    const source_bytes = source: {
        const node = progress_root.start("read source", 1);
        defer node.end();
        const stage_start = nowNs(io);
        const bytes = try readSourceFile(arena, io, source_path);
        timing_trace.add(.read_source, elapsedSince(stage_start, nowNs(io)));
        break :source bytes;
    };

    var assembled = assembled: {
        const node = progress_root.start("assemble flat", 1);
        defer node.end();
        break :assembled assembleFlatTimed(gpa, io, source_path, source_bytes, options.target, stderr, &timing_trace) catch |err| {
            if (progress_enabled) std.Progress.setStatus(.failure);
            if (err != error.FrontendDiagnostics) {
                try stderr.print("error: assembly failed: {s}\n", .{@errorName(err)});
            }
            try stderr.flush();
            std.process.exit(1);
        };
    };
    defer assembled.deinit(gpa);
    try stderr.flush();

    if (assembled.pending_fixups != 0) {
        if (progress_enabled) std.Progress.setStatus(.failure);
        try stderr.print("error: {d} unresolved fixup(s)\n", .{assembled.pending_fixups});
        try stderr.flush();
        std.process.exit(1);
    }

    const output_path = options.output_path orelse try defaultOutputPath(arena, source_path);
    {
        const node = progress_root.start("write output", 1);
        defer node.end();
        const stage_start = nowNs(io);
        try writeOutputFile(io, output_path, assembled.bytes);
        timing_trace.add(.write_output, elapsedSince(stage_start, nowNs(io)));
    }
    if (options.listing_path) |listing_path| {
        const node = progress_root.start("write listing", 1);
        defer node.end();
        const stage_start = nowNs(io);
        const listing_bytes = try renderListing(arena, source_path, &assembled);
        try writeOutputFile(io, listing_path, listing_bytes);
        timing_trace.add(.write_listing, elapsedSince(stage_start, nowNs(io)));
    }
    if (progress_enabled) std.Progress.setStatus(.success);
    try stdout.print(
        "assembled output ({d} bytes, {d} instruction fragments, target {s})\n",
        .{ assembled.bytes.len, assembled.encoded_count, targetName(assembled.module.target) },
    );
    if (options.timings.enabled()) {
        try writeTimingReport(stdout, "assemble", assembled.module.target, &assembled, &timing_trace, timing_trace.totalNs(io), options.timings);
    }
    try stdout.flush();
}

fn runBuildCommand(
    arena: Allocator,
    gpa: Allocator,
    io: Io,
    stdout: *Io.Writer,
    stderr: *Io.Writer,
    options: BuildOptions,
) !void {
    var project_config = try readOptionalProjectConfig(arena, io);
    defer project_config.deinit(arena);

    const resolved = try resolveBuildOptions(project_config, options);
    const progress_enabled = resolved.progress != .never;
    var progress_root = if (progress_enabled)
        std.Progress.start(io, .{ .root_name = "xirasm build", .estimated_total_items = 4 })
    else
        std.Progress.Node.none;
    defer progress_root.end();

    var timing_trace = TimingTrace.init(io);

    const include_inputs = try readIncludeInputs(arena, io, project_config.include.files, &progress_root, &timing_trace);
    const source_input = source: {
        const node = progress_root.start("read source", 1);
        defer node.end();
        const stage_start = nowNs(io);
        const bytes = try readSourceFile(arena, io, resolved.source_path);
        timing_trace.add(.read_source, elapsedSince(stage_start, nowNs(io)));
        break :source SourceInput{
            .path = resolved.source_path,
            .bytes = bytes,
        };
    };

    var assembled = assembled: {
        const node = progress_root.start("assemble flat", 1);
        defer node.end();
        break :assembled assembleProjectFlatTimed(
            gpa,
            io,
            stderr,
            resolved.target,
            project_config.defines,
            include_inputs,
            source_input,
            &timing_trace,
        ) catch |err| {
            if (progress_enabled) std.Progress.setStatus(.failure);
            if (err != error.FrontendDiagnostics) {
                try stderr.print("error: build failed: {s}\n", .{@errorName(err)});
            }
            try stderr.flush();
            std.process.exit(1);
        };
    };
    defer assembled.deinit(gpa);
    try stderr.flush();

    if (assembled.pending_fixups != 0) {
        if (progress_enabled) std.Progress.setStatus(.failure);
        try stderr.print("error: {d} unresolved fixup(s)\n", .{assembled.pending_fixups});
        try stderr.flush();
        std.process.exit(1);
    }

    {
        const node = progress_root.start("write output", 1);
        defer node.end();
        const stage_start = nowNs(io);
        try writeOutputFile(io, resolved.output_path, assembled.bytes);
        timing_trace.add(.write_output, elapsedSince(stage_start, nowNs(io)));
    }
    if (options.listing_path) |listing_path| {
        const node = progress_root.start("write listing", 1);
        defer node.end();
        const stage_start = nowNs(io);
        const listing_bytes = try renderListing(arena, resolved.source_path, &assembled);
        try writeOutputFile(io, listing_path, listing_bytes);
        timing_trace.add(.write_listing, elapsedSince(stage_start, nowNs(io)));
    }
    if (progress_enabled) std.Progress.setStatus(.success);
    try stdout.print(
        "built output ({d} bytes, {d} instruction fragments, target {s})\n",
        .{ assembled.bytes.len, assembled.encoded_count, targetName(assembled.module.target) },
    );
    if (resolved.timings.enabled()) {
        try writeTimingReport(stdout, "build", assembled.module.target, &assembled, &timing_trace, timing_trace.totalNs(io), resolved.timings);
    }
    try stdout.flush();
}

fn resolveBuildOptions(config: xirasm.data.ProjectConfig, options: BuildOptions) !ResolvedBuildOptions {
    return .{
        .source_path = options.source_path orelse config.build.source orelse "src/main.xir",
        .output_path = options.output_path orelse config.build.output orelse "build/app.bin",
        .target = try resolveBuildTarget(config, options),
        .progress = options.progress,
        .timings = options.timings,
    };
}

fn resolveBuildTarget(config: xirasm.data.ProjectConfig, options: BuildOptions) !xirasm.Target {
    if (explicitTarget(options)) return options.target;
    if (config.build.target) |target_text| {
        return parseTarget(target_text) orelse error.InvalidBuildConfig;
    }
    if (config.target.isa) |isa| {
        return targetFromProjectConfig(config.target, isa);
    }
    return options.target;
}

fn targetFromProjectConfig(config: xirasm.data.TargetConfig, isa: []const u8) !xirasm.Target {
    if (std.mem.eql(u8, isa, "x86-64") or
        std.mem.eql(u8, isa, "x86_64") or
        std.mem.eql(u8, isa, "x64"))
    {
        return xirasm.Target.initX86(config.bits orelse 64);
    }
    if (std.mem.eql(u8, isa, "x86") or std.mem.eql(u8, isa, "x86-32")) {
        return xirasm.Target.initX86(config.bits orelse 32);
    }
    if (std.mem.eql(u8, isa, "rv64") or
        std.mem.eql(u8, isa, "riscv64"))
    {
        return xirasm.Target.initRiscv(config.bits orelse 64);
    }
    if (std.mem.eql(u8, isa, "rv32") or std.mem.eql(u8, isa, "riscv32")) {
        return xirasm.Target.initRiscv(config.bits orelse 32);
    }
    return error.InvalidBuildConfig;
}

fn explicitTarget(options: BuildOptions) bool {
    return !options.target.isDefault();
}

fn readOptionalProjectConfig(allocator: Allocator, io: Io) !xirasm.data.ProjectConfig {
    const bytes = readSourceFile(allocator, io, "xirasm.toml") catch |err| switch (err) {
        error.FileNotFound => return .{},
        else => return err,
    };
    return xirasm.data.loadProjectConfig(allocator, bytes);
}

fn assembleFlat(
    allocator: Allocator,
    io: Io,
    source_path: []const u8,
    source_bytes: []const u8,
    target: xirasm.Target,
    diagnostics_writer: ?*Io.Writer,
) !AssembledFlat {
    var timing_trace = TimingTrace.init(io);
    return assembleFlatTimed(allocator, io, source_path, source_bytes, target, diagnostics_writer, &timing_trace);
}

fn assembleFlatTimed(
    allocator: Allocator,
    io: Io,
    source_path: []const u8,
    source_bytes: []const u8,
    target: xirasm.Target,
    diagnostics_writer: ?*Io.Writer,
    timing_trace: *TimingTrace,
) !AssembledFlat {
    var module = try xirasm.Module.init(allocator, target);
    var module_owned = true;
    errdefer if (module_owned) module.deinit();

    const project_root = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(project_root);
    const install_include_root = installed: {
        const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break :installed null,
        };
        errdefer allocator.free(exe_dir);
        const root = try std.fs.path.join(allocator, &.{ exe_dir, "include" });
        allocator.free(exe_dir);
        break :installed root;
    };
    defer if (install_include_root) |root| allocator.free(root);

    var include_context: FileIncludeResolver = .{
        .io = io,
        .project_root = project_root,
        .install_include_root = install_include_root,
    };
    const source_identity = try canonicalFileIdentity(allocator, io, source_path);
    defer if (source_identity) |identity| allocator.free(identity);
    const lower_start = nowNs(io);
    xirasm.lowerSourceIntoModuleWithPathOptions(allocator, &module, source_path, source_bytes, .{
        .target = target,
        .source_identity = source_identity,
        .include_resolver = .{
            .context = @ptrCast(&include_context),
            .resolve = resolveFileInclude,
        },
    }) catch |err| {
        if (!module.diagnostics.hasErrors()) return err;
    };
    timing_trace.add(.parse_lower, elapsedSince(lower_start, nowNs(io)));
    const assembled = try assembleModuleFlatChecked(allocator, io, &module, diagnostics_writer, timing_trace);
    return finishAssembledFlat(&module, assembled, &module_owned);
}

fn readIncludeInputs(
    allocator: Allocator,
    io: Io,
    paths: []const []const u8,
    progress_root: *std.Progress.Node,
    timing_trace: *TimingTrace,
) ![]const SourceInput {
    const inputs = try allocator.alloc(SourceInput, paths.len);
    for (paths, 0..) |path, index| {
        const node = progress_root.start("read include", 1);
        defer node.end();
        const stage_start = nowNs(io);
        const bytes = try readSourceFile(allocator, io, path);
        timing_trace.add(.read_source, elapsedSince(stage_start, nowNs(io)));
        inputs[index] = .{
            .path = path,
            .bytes = bytes,
        };
    }
    return inputs;
}

fn assembleProjectFlat(
    allocator: Allocator,
    io: Io,
    diagnostics_writer: ?*Io.Writer,
    target: xirasm.Target,
    defines: []const xirasm.data.Define,
    includes: []const SourceInput,
    main_source: SourceInput,
) !AssembledFlat {
    var timing_trace = TimingTrace.init(io);
    return assembleProjectFlatTimed(allocator, io, diagnostics_writer, target, defines, includes, main_source, &timing_trace);
}

fn assembleProjectFlatTimed(
    allocator: Allocator,
    io: Io,
    diagnostics_writer: ?*Io.Writer,
    target: xirasm.Target,
    defines: []const xirasm.data.Define,
    includes: []const SourceInput,
    main_source: SourceInput,
    timing_trace: *TimingTrace,
) !AssembledFlat {
    var module = try xirasm.Module.init(allocator, target);
    var module_owned = true;
    errdefer if (module_owned) module.deinit();

    try applyProjectDefines(allocator, &module, defines);
    const project_root = try std.process.currentPathAlloc(io, allocator);
    defer allocator.free(project_root);
    const install_include_root = installed: {
        const exe_dir = std.process.executableDirPathAlloc(io, allocator) catch |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            else => break :installed null,
        };
        errdefer allocator.free(exe_dir);
        const root = try std.fs.path.join(allocator, &.{ exe_dir, "include" });
        allocator.free(exe_dir);
        break :installed root;
    };
    defer if (install_include_root) |root| allocator.free(root);

    var include_context: FileIncludeResolver = .{
        .io = io,
        .project_root = project_root,
        .install_include_root = install_include_root,
    };
    const lower_options: xirasm.LowerOptions = .{
        .target = target,
        .include_resolver = .{
            .context = @ptrCast(&include_context),
            .resolve = resolveFileInclude,
        },
    };
    for (includes) |include| {
        const source_identity = try canonicalFileIdentity(allocator, io, include.path);
        defer if (source_identity) |identity| allocator.free(identity);
        var source_options = lower_options;
        source_options.source_identity = source_identity;
        const lower_start = nowNs(io);
        xirasm.lowerSourceIntoModuleWithPathOptions(allocator, &module, include.path, include.bytes, source_options) catch |err| {
            if (!module.diagnostics.hasErrors()) return err;
            timing_trace.add(.parse_lower, elapsedSince(lower_start, nowNs(io)));
            const assembled = try assembleModuleFlatChecked(allocator, io, &module, diagnostics_writer, timing_trace);
            return finishAssembledFlat(&module, assembled, &module_owned);
        };
        timing_trace.add(.parse_lower, elapsedSince(lower_start, nowNs(io)));
    }
    const main_source_identity = try canonicalFileIdentity(allocator, io, main_source.path);
    defer if (main_source_identity) |identity| allocator.free(identity);
    var main_source_options = lower_options;
    main_source_options.source_identity = main_source_identity;
    const lower_start = nowNs(io);
    xirasm.lowerSourceIntoModuleWithPathOptions(allocator, &module, main_source.path, main_source.bytes, main_source_options) catch |err| {
        if (!module.diagnostics.hasErrors()) return err;
    };
    timing_trace.add(.parse_lower, elapsedSince(lower_start, nowNs(io)));

    const assembled = try assembleModuleFlatChecked(allocator, io, &module, diagnostics_writer, timing_trace);
    return finishAssembledFlat(&module, assembled, &module_owned);
}

fn resolveFileInclude(
    context: *anyopaque,
    allocator: Allocator,
    request: xirasm.IncludeRequest,
) xirasm.LowerError!xirasm.IncludeSource {
    const resolver: *FileIncludeResolver = @ptrCast(@alignCast(context));
    return resolveFileIncludeFromRoots(resolver, allocator, request.parent_path, request.path);
}

fn resolveFileIncludeFromRoots(
    resolver: *const FileIncludeResolver,
    allocator: Allocator,
    parent_path: ?[]const u8,
    include_path: []const u8,
) xirasm.LowerError!xirasm.IncludeSource {
    if (isAbsolutePath(include_path)) {
        return readResolvedIncludePath(resolver, allocator, include_path);
    }

    if (parent_path) |parent| {
        const resolved_path = try resolveIncludePath(allocator, parent, include_path);
        defer allocator.free(resolved_path);
        if (readResolvedIncludePath(resolver, allocator, resolved_path)) |source_input| {
            return source_input;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.IncludeNotAvailable => {},
            else => return err,
        }
    }

    if (resolver.project_root) |project_root| {
        const resolved_path = try std.fs.path.join(allocator, &.{ project_root, "include", include_path });
        defer allocator.free(resolved_path);
        if (readResolvedIncludePath(resolver, allocator, resolved_path)) |source_input| {
            return source_input;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.IncludeNotAvailable => {},
            else => return err,
        }
    }

    if (resolver.install_include_root) |install_include_root| {
        const resolved_path = try std.fs.path.join(allocator, &.{ install_include_root, include_path });
        defer allocator.free(resolved_path);
        if (readResolvedIncludePath(resolver, allocator, resolved_path)) |source_input| {
            return source_input;
        } else |err| switch (err) {
            error.OutOfMemory => return error.OutOfMemory,
            error.IncludeNotAvailable => {},
            else => return err,
        }
    }

    return error.IncludeNotAvailable;
}

fn readResolvedIncludePath(
    resolver: *const FileIncludeResolver,
    allocator: Allocator,
    resolved_path: []const u8,
) xirasm.LowerError!xirasm.IncludeSource {
    const owned_path = try allocator.dupe(u8, resolved_path);
    errdefer allocator.free(owned_path);

    const real_identity = std.Io.Dir.cwd().realPathFileAlloc(resolver.io, resolved_path, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.IncludeNotAvailable,
    };
    defer allocator.free(real_identity);
    const identity = try allocator.dupe(u8, real_identity);
    errdefer allocator.free(identity);

    const bytes = readSourceFile(allocator, resolver.io, identity) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return error.IncludeNotAvailable,
    };
    errdefer allocator.free(bytes);

    return .{
        .path = owned_path,
        .identity = identity,
        .bytes = bytes,
    };
}

fn canonicalFileIdentity(allocator: Allocator, io: Io, path: []const u8) Allocator.Error!?[]u8 {
    const real_identity = std.Io.Dir.cwd().realPathFileAlloc(io, path, allocator) catch |err| switch (err) {
        error.OutOfMemory => return error.OutOfMemory,
        else => return null,
    };
    defer allocator.free(real_identity);
    return try allocator.dupe(u8, real_identity);
}

fn resolveIncludePath(
    allocator: Allocator,
    parent_path: []const u8,
    include_path: []const u8,
) ![]u8 {
    const separator_index = std.mem.lastIndexOfAny(u8, parent_path, "\\/") orelse return allocator.dupe(u8, include_path);
    const parent_dir = parent_path[0..separator_index];
    if (parent_dir.len == 0) return allocator.dupe(u8, include_path);
    return std.fs.path.join(allocator, &.{ parent_dir, include_path });
}

fn isAbsolutePath(path: []const u8) bool {
    if (std.mem.startsWith(u8, path, "/") or std.mem.startsWith(u8, path, "\\")) return true;
    return path.len >= 3 and std.ascii.isAlphabetic(path[0]) and path[1] == ':' and (path[2] == '\\' or path[2] == '/');
}

fn applyProjectDefines(
    allocator: Allocator,
    module: *xirasm.Module,
    defines: []const xirasm.data.Define,
) !void {
    for (defines) |define| {
        var stored_value = try projectDefineValue(allocator, define.value);
        errdefer stored_value.deinit(allocator);
        const symbol_id = try module.defineValue(define.name, stored_value, .@"const", .{});
        stored_value = .void;
        if (symbol_id.index >= module.symbols.items.items.len) return error.InvalidBuildConfig;
    }
}

fn projectDefineValue(allocator: Allocator, value: xirasm.data.ConfigValue) !xirasm.Value {
    return switch (value) {
        .integer => |integer| xirasm.Value.int(integer),
        .boolean => |boolean| .{ .boolean = boolean },
        .string => |string| .{ .string = try allocator.dupe(u8, string) },
    };
}

fn assembleModuleFlatChecked(
    allocator: Allocator,
    io: Io,
    module: *xirasm.Module,
    diagnostics_writer: ?*Io.Writer,
    timing_trace: *TimingTrace,
) !AssembledFlatCore {
    var reported_diagnostics: usize = 0;
    try writeNewDiagnostics(diagnostics_writer, module, &reported_diagnostics);
    if (module.diagnostics.hasErrors()) {
        return error.FrontendDiagnostics;
    }
    var assembled = assembleModuleFlat(allocator, io, module, timing_trace) catch |err| {
        try writeNewDiagnostics(diagnostics_writer, module, &reported_diagnostics);
        return err;
    };
    try writeNewDiagnostics(diagnostics_writer, module, &reported_diagnostics);
    if (module.diagnostics.hasErrors()) {
        assembled.deinit(allocator);
        return error.FrontendDiagnostics;
    }
    return assembled;
}

fn assembleModuleFlat(allocator: Allocator, io: Io, module: *xirasm.Module, timing_trace: *TimingTrace) !AssembledFlatCore {
    var observer_state: AssemblyTimingObserver = .{
        .io = io,
        .timing_trace = timing_trace,
    };
    return xirasm.assembly.assembleFlat(allocator, module, .{
        .context = @ptrCast(&observer_state),
        .begin = AssemblyTimingObserver.begin,
        .end = AssemblyTimingObserver.end,
    });
}

const AssemblyTimingObserver = struct {
    io: Io,
    timing_trace: *TimingTrace,
    started_at: i96 = 0,

    fn begin(context: *anyopaque, _: xirasm.assembly.Stage) void {
        const self: *AssemblyTimingObserver = @ptrCast(@alignCast(context));
        self.started_at = nowNs(self.io);
    }

    fn end(context: *anyopaque, stage: xirasm.assembly.Stage) void {
        const self: *AssemblyTimingObserver = @ptrCast(@alignCast(context));
        self.timing_trace.add(timingStageForAssembly(stage), elapsedSince(self.started_at, nowNs(self.io)));
    }
};

fn timingStageForAssembly(stage: xirasm.assembly.Stage) TimingStage {
    return switch (stage) {
        .encode => .encode,
        .fixup_resolve => .fixup_resolve,
        .layout => .layout,
        .materialize => .materialize,
        .patch => .patch,
        .defer_finalizers => .defer_finalizers,
    };
}

fn renderListing(allocator: Allocator, source_path: []const u8, assembled: *const AssembledFlat) ![]u8 {
    return xirasm.renderFlatListing(allocator, &assembled.module, &assembled.layout, .{
        .source_path = source_path,
        .output_bytes = assembled.bytes,
    });
}

fn writeDiagnostics(writer: *Io.Writer, module: *const xirasm.Module) !void {
    try writeDiagnosticsFrom(writer, module, 0);
}

fn writeNewDiagnostics(
    writer: ?*Io.Writer,
    module: *const xirasm.Module,
    reported_count: *usize,
) !void {
    if (module.diagnostics.items.items.len <= reported_count.*) return;
    if (writer) |diagnostics_writer| {
        try writeDiagnosticsFrom(diagnostics_writer, module, reported_count.*);
    }
    reported_count.* = module.diagnostics.items.items.len;
}

fn writeDiagnosticsFrom(writer: *Io.Writer, module: *const xirasm.Module, start_index: usize) !void {
    for (module.diagnostics.items.items[start_index..]) |item| {
        const severity = switch (item.severity) {
            .note => "note",
            .warning => "warning",
            .err => "error",
        };
        if (try module.sources.location(item.span)) |location| {
            try writer.print(
                "{s}:{d}:{d}: {s}: {s}\n",
                .{ location.path, location.line, location.column, severity, item.message },
            );
        } else {
            try writer.print("{s}: {s}\n", .{ severity, item.message });
        }
    }
}

fn sizeToUsize(value: u64) !usize {
    if (value > std.math.maxInt(usize)) return error.FileTooLarge;
    return @intCast(value);
}

fn readSourceFile(allocator: Allocator, io: Io, path: []const u8) ![]u8 {
    var file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var read_buffer: [4096]u8 = undefined;
    var reader = file.reader(io, &read_buffer);
    return reader.interface.allocRemaining(allocator, .limited(std.math.maxInt(usize)));
}

fn writeOutputFile(io: Io, path: []const u8, bytes: []const u8) !void {
    try ensureOutputParentPath(io, path);
    var file = try Io.Dir.cwd().createFile(io, path, .{ .truncate = true });
    defer file.close(io);
    try file.writeStreamingAll(io, bytes);
}

fn ensureOutputParentPath(io: Io, path: []const u8) !void {
    const separator_index = std.mem.lastIndexOfAny(u8, path, "\\/") orelse return;
    if (separator_index == 0) return;
    const parent = path[0..separator_index];
    if (parent.len == 0) return;
    try Io.Dir.cwd().createDirPath(io, parent);
}

fn defaultOutputPath(allocator: Allocator, source_path: []const u8) ![]const u8 {
    if (std.mem.lastIndexOfScalar(u8, source_path, '.')) |dot_index| {
        return std.fmt.allocPrint(allocator, "{s}.bin", .{source_path[0..dot_index]});
    }
    return std.fmt.allocPrint(allocator, "{s}.bin", .{source_path});
}

fn runInitCommand(arena: Allocator, io: Io, stdout: *Io.Writer, options: InitOptions) !void {
    const project_name = try initProjectName(arena, io, options);
    var project_dir = if (options.dir_path) |dir_path|
        try Io.Dir.cwd().createDirPathOpen(io, dir_path, .{})
    else
        Io.Dir.cwd();
    defer if (options.dir_path != null) project_dir.close(io);

    try scaffoldInitProject(arena, io, project_dir, options, project_name);
    try stdout.print("initialized XIRASM project {s}\n", .{project_name});
    try stdout.flush();
}

fn initProjectName(allocator: Allocator, io: Io, options: InitOptions) ![]const u8 {
    if (options.name) |name| return allocator.dupe(u8, name);
    if (options.dir_path) |dir_path| {
        const trimmed = std.mem.trim(u8, dir_path, "\\/");
        if (std.mem.lastIndexOfAny(u8, trimmed, "\\/")) |slash| {
            return allocator.dupe(u8, trimmed[slash + 1 ..]);
        }
        return allocator.dupe(u8, trimmed);
    }
    var buffer: [std.fs.max_path_bytes]u8 = undefined;
    const cwd_len = try std.process.currentPath(io, &buffer);
    const cwd = buffer[0..cwd_len];
    if (std.mem.lastIndexOfAny(u8, cwd, "\\/")) |slash| {
        return allocator.dupe(u8, cwd[slash + 1 ..]);
    }
    return allocator.dupe(u8, cwd);
}

const ScaffoldFile = struct {
    path: []const u8,
    bytes: []const u8,
};

fn scaffoldInitProject(
    allocator: Allocator,
    io: Io,
    dir: Io.Dir,
    options: InitOptions,
    project_name: []const u8,
) !void {
    const manifest = try initTomlTemplate(allocator, project_name, options.target);
    defer allocator.free(manifest);

    const files = [_]ScaffoldFile{
        .{ .path = "xirasm.toml", .bytes = manifest },
        .{ .path = "src/main.xir", .bytes = initMainTemplate(options.target) },
        .{ .path = "include/README.md", .bytes = initIncludeReadme() },
    };

    if (!options.force) try ensureScaffoldTargetsMissing(io, dir, &files);
    try dir.createDirPath(io, "include");
    try dir.createDirPath(io, "src");
    for (files) |file_info| {
        try writeScaffoldFile(io, dir, file_info, options.force);
    }
}

fn ensureScaffoldTargetsMissing(io: Io, dir: Io.Dir, files: []const ScaffoldFile) !void {
    for (files) |file_info| {
        var file = dir.openFile(io, file_info.path, .{}) catch |err| switch (err) {
            error.FileNotFound => continue,
            else => return err,
        };
        file.close(io);
        return error.PathAlreadyExists;
    }
}

fn writeScaffoldFile(io: Io, dir: Io.Dir, file_info: ScaffoldFile, force: bool) !void {
    var file = if (force)
        try dir.createFile(io, file_info.path, .{ .truncate = true })
    else
        try dir.createFile(io, file_info.path, .{ .exclusive = true });
    defer file.close(io);
    try file.writeStreamingAll(io, file_info.bytes);
}

fn initTomlTemplate(allocator: Allocator, project_name: []const u8, target: InitTargetConfig) ![]const u8 {
    return std.fmt.allocPrint(
        allocator,
        \\[project]
        \\name = "{s}"
        \\version = "0.1.0"
        \\
        \\[build]
        \\source = "src/main.xir"
        \\output = "{s}"
        \\
        \\[target]
        \\isa = "{s}"
        \\bits = {d}
        \\os = "{s}"
        \\abi = "{s}"
        \\
    ,
        .{ project_name, initOutputPath(target), target.isa, target.bits, target.os, target.abi },
    );
}

fn initMainTemplate(target: InitTargetConfig) []const u8 {
    return switch (initTemplateKind(target)) {
        .flat_x86_32 => init_flat_x86_32_template,
        .flat_x86_64 => init_flat_x86_64_template,
        .flat_riscv32 => init_flat_riscv32_template,
        .flat_riscv64 => init_flat_riscv64_template,
        .pe32 => init_pe32_template,
        .pe64 => init_pe64_template,
        .elf32 => init_elf32_template,
        .elf64 => init_elf64_template,
    };
}

fn initTemplateKind(target: InitTargetConfig) InitTemplateKind {
    const is_riscv = std.mem.eql(u8, target.isa, "riscv64") or
        std.mem.eql(u8, target.isa, "riscv32") or
        std.mem.eql(u8, target.isa, "rv64") or
        std.mem.eql(u8, target.isa, "rv32");
    if (is_riscv) return if (target.bits == 32) .flat_riscv32 else .flat_riscv64;

    if (std.mem.eql(u8, target.os, "windows")) {
        return if (target.bits == 32) .pe32 else .pe64;
    }
    if (std.mem.eql(u8, target.os, "linux")) {
        return if (target.bits == 32) .elf32 else .elf64;
    }
    return if (target.bits == 32) .flat_x86_32 else .flat_x86_64;
}

fn initOutputPath(target: InitTargetConfig) []const u8 {
    return switch (initTemplateKind(target)) {
        .pe32, .pe64 => "build/app.exe",
        .elf32, .elf64 => "build/app",
        else => "build/app.bin",
    };
}

fn initIncludeReadme() []const u8 {
    return
    \\Project-local XIRASM include files can live here.
    \\
    \\Use this directory for helpers specific to your project. Standard
    \\executable and object formats normally begin with:
    \\
    \\    import("format/format.inc");
    \\
    \\The ordinary facade derives format counts, rows, offsets, and common
    \\metadata. Advanced users can import a specific file under format/*.inc
    \\when implementing a specialized layout or another format layer.
    \\
    ;
}

const init_flat_x86_32_template =
    \\// Flat x86 binary starter.
    \\// Use --os windows or --os linux with xirasm init for an executable
    \\// template built through the ordinary format facade.
    \\
    \\x86.use32();
    \\origin(0);
    \\
    \\start:
    \\    mov eax, 1
    \\    ret
    \\
;

const init_flat_x86_64_template =
    \\// Flat x86-64 binary starter.
    \\// Use --os windows or --os linux with xirasm init for an executable
    \\// template built through the ordinary format facade.
    \\
    \\x86.use64();
    \\origin(0);
    \\
    \\start:
    \\    mov rax, 1
    \\    ret
    \\
;

const init_flat_riscv32_template =
    \\// Flat RISC-V 32-bit binary starter.
    \\// Standard executable facade templates currently target x86.
    \\
    \\riscv.use32();
    \\origin(0);
    \\
    \\start:
    \\    addi x1, x0, 1
    \\
;

const init_flat_riscv64_template =
    \\// Flat RISC-V 64-bit binary starter.
    \\// Standard executable facade templates currently target x86.
    \\
    \\riscv.use64();
    \\origin(0);
    \\
    \\start:
    \\    addi x1, x0, 1
    \\
;

const init_pe32_template =
    \\// PE32 console executable using the ordinary format facade.
    \\import("format/format.inc");
    \\x86.use32();
    \\
    \\let image: map = format_pe32(
    \\    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    \\    list.of(
    \\        format_section(".text", format_code | format_readable | format_executable)
    \\    )
    \\)
    \\format_begin(image);
    \\
    \\format_section_begin(image, ".text");
    \\start:
    \\    xor eax, eax
    \\    ret
    \\format_section_end(image, ".text");
    \\
    \\format_entry_mut(image, start)
    \\format_finish(image);
    \\
;

const init_pe64_template =
    \\// PE64 console executable using the ordinary format facade.
    \\import("format/format.inc");
    \\x86.use64();
    \\
    \\let image: map = format_pe64(
    \\    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    \\    list.of(
    \\        format_section(".text", format_code | format_readable | format_executable)
    \\    )
    \\)
    \\format_begin(image);
    \\
    \\format_section_begin(image, ".text");
    \\start:
    \\    xor eax, eax
    \\    ret
    \\format_section_end(image, ".text");
    \\
    \\format_entry_mut(image, start)
    \\format_finish(image);
    \\
;

const init_elf32_template =
    \\// ELF32 executable using the ordinary format facade.
    \\import("format/format.inc");
    \\x86.use32();
    \\
    \\let image: map = format_elf32(
    \\    format_elf_exec,
    \\    list.of(
    \\        format_segment(".text", format_load | format_readable | format_executable)
    \\    )
    \\)
    \\format_begin(image);
    \\
    \\format_segment_begin(image, ".text");
    \\start:
    \\    mov eax, 1
    \\    xor ebx, ebx
    \\    int 0x80
    \\format_segment_end(image, ".text");
    \\
    \\format_entry_mut(image, start)
    \\format_finish(image);
    \\
;

const init_elf64_template =
    \\// ELF64 executable using the ordinary format facade.
    \\import("format/format.inc");
    \\x86.use64();
    \\
    \\let image: map = format_elf64(
    \\    format_elf_exec,
    \\    list.of(
    \\        format_segment(".text", format_load | format_readable | format_executable)
    \\    )
    \\)
    \\format_begin(image);
    \\
    \\format_segment_begin(image, ".text");
    \\start:
    \\    mov eax, 60
    \\    xor edi, edi
    \\    syscall
    \\format_segment_end(image, ".text");
    \\
    \\format_entry_mut(image, start)
    \\format_finish(image);
    \\
;

fn isValidProjectName(value: []const u8) bool {
    if (value.len == 0) return false;
    if (std.mem.eql(u8, value, ".") or std.mem.eql(u8, value, "..")) return false;
    for (value) |byte| {
        if (std.ascii.isAlphanumeric(byte) or byte == '_' or byte == '-') continue;
        return false;
    }
    return true;
}

fn writeVersionText(writer: *Io.Writer) Io.Writer.Error!void {
    try writer.print("XIRASM {s}\n", .{build_options.version});
}

fn writeHelpText(writer: *Io.Writer) Io.Writer.Error!void {
    try writeVersionText(writer);
    try writer.writeByte('\n');
    try writer.writeAll(helpText());
}

fn writeHelpTopic(writer: *Io.Writer, topic: HelpTopic) Io.Writer.Error!void {
    try writeVersionText(writer);
    try writer.writeByte('\n');
    switch (topic) {
        .overview => try writer.writeAll(helpText()),
        .init => try writer.writeAll(initHelpText()),
        .targets => try writer.writeAll(targetsHelpText()),
    }
}

fn helpText() []const u8 {
    return
    \\Usage:
    \\  xirasm <source.xir> [options]
    \\  xirasm build [source.xir] [options]
    \\  xirasm init [dir] [--target <target>] [--name <name>] [--force]
    \\  xirasm init [dir] [--isa <isa>] [--bits <32|64>] [--os <os>] [--abi <abi>]
    \\  xirasm help [init|targets]
    \\
    \\Options:
    \\  -h, --help        Show this help text
    \\  -V, --version     Show the XIRASM version
    \\  -o <path>         Write assembled output bytes to the given file
    \\  --listing <path>  Write a source/bytes listing file
    \\  --lst <path>      Alias for --listing
    \\  --target <target> Select x86-64, x86, rv64, rv32, or spv
    \\  --timings         Print assembly timing summary
    \\  --trace-phases    Print timing summary plus per-phase timings
    \\  --isa, --arch     Set init template ISA without changing OS/ABI
    \\  --bits, --bit     Set init template bit width: 32 or 64
    \\  --os              Select init output model: bin, windows, or linux
    \\  --abi             Set init template ABI field
    \\  --progress        Force terminal progress while assembling
    \\  --no-progress     Disable terminal progress
    \\
    \\Examples:
    \\  xirasm demo.xir
    \\  xirasm demo.xir -o demo.bin
    \\  xirasm demo.xir --target rv64 -o demo.bin
    \\  xirasm build
    \\  xirasm init demo --target x86-64
    \\  xirasm init hello-win --isa x86-64 --os windows --abi msvc
    \\  xirasm init hello-linux --isa x86-64 --os linux --abi sysv
    \\  xirasm help init
    \\  xirasm help targets
    \\
    \\Notes:
    \\  - Subcommands come first: use `xirasm build --timings`, not `xirasm --timings build`
    \\  - build uses the source and output path from xirasm.toml
    \\  - x86 Windows/Linux init templates use import("format/format.inc")
    \\  - bin, none, and RISC-V init templates remain flat binary starters
    \\
    ;
}

fn initHelpText() []const u8 {
    return
    \\Create a project:
    \\  xirasm init [dir] [--target <target>] [--name <name>] [--force]
    \\  xirasm init [dir] [--isa <isa>] [--bits <32|64>] [--os <os>] [--abi <abi>]
    \\
    \\Template selection:
    \\  x86 + --os windows   PE32/PE64 executable, output build/app.exe
    \\  x86 + --os linux     ELF32/ELF64 executable, output build/app
    \\  --os bin or none     Flat binary source, output build/app.bin
    \\  RISC-V               Flat binary source, output build/app.bin
    \\
    \\Generated project:
    \\  xirasm.toml           Source, output, and target defaults
    \\  src/main.xir          Buildable starter source
    \\  include/README.md     Project include guidance
    \\
    \\Format layers:
    \\  Executable starters import format/format.inc for the ordinary facade.
    \\  Advanced sources may explicitly import a format-specific include.
    \\
    \\Examples:
    \\  xirasm init demo --target x86-64
    \\  xirasm init hello-win --isa x86-64 --os windows --abi msvc
    \\  xirasm init hello-linux --isa x86-64 --os linux --abi sysv
    \\
    ;
}

fn targetsHelpText() []const u8 {
    return
    \\Targets:
    \\  x86-64, x86_64, x64  64-bit x86
    \\  x86, x86-32          32-bit x86
    \\  rv64, riscv64        64-bit RISC-V
    \\  rv32, riscv32        32-bit RISC-V
    \\  spv, spirv           SPIR-V 1.6 module
    \\
    \\Init template selection:
    \\  x86 + --os windows   PE32/PE64 executable through format/format.inc
    \\  x86 + --os linux     ELF32/ELF64 executable through format/format.inc
    \\  --os bin or none     Flat binary source
    \\  RISC-V               Flat binary source
    \\
    \\Format layers:
    \\  ordinary users       import("format/format.inc")
    \\  advanced users       explicitly import a format-specific include
    \\
    ;
}

fn writeCliParseIssue(writer: *Io.Writer, issue: CliParseIssue) Io.Writer.Error!void {
    switch (issue) {
        .missing_source_path => try writer.writeAll("error: missing source path\n"),
        .missing_output_path => try writer.writeAll("error: -o requires an output path\n"),
        .missing_listing_path => try writer.writeAll("error: --listing requires a .lst output path\n"),
        .missing_init_value => |key| try writer.print("error: init option {s} requires a value\n", .{key}),
        .multiple_source_paths => |paths| try writer.print(
            "error: multiple source paths are not allowed: {s} and {s}\n",
            .{ paths.first, paths.second },
        ),
        .multiple_init_paths => |paths| try writer.print(
            "error: multiple init directories are not allowed: {s} and {s}\n",
            .{ paths.first, paths.second },
        ),
        .unknown_option => |option| try writer.print("error: unknown option {s}\n", .{option}),
        .unknown_help_topic => |topic| try writer.print("error: unknown help topic {s}\n", .{topic}),
        .invalid_target => |target| try writer.print("error: invalid target {s}\n", .{target}),
        .invalid_init_value => |item| try writer.print("error: invalid init value for {s}: {s}\n", .{ item.key, item.value }),
        .misplaced_subcommand => |subcommand| try writer.print("error: {s} subcommand must appear before its options; use `xirasm {s} [options]`\n", .{ subcommand, subcommand }),
    }
}

test "xirasm module is available to the executable" {
    _ = xirasm.Module;
}

test "parseCliArgs accepts assemble progress target output and timings" {
    const result = parseCliArgs(&.{ "xirasm", "demo.xir", "-o", "demo.bin", "--progress", "--trace-phases", "--target", "rv64" });
    switch (result) {
        .ok => |command| switch (command) {
            .assemble => |options| {
                try std.testing.expectEqualStrings("demo.xir", options.source_path.?);
                try std.testing.expectEqualStrings("demo.bin", options.output_path.?);
                try std.testing.expectEqual(ProgressMode.always, options.progress);
                try std.testing.expectEqual(TimingMode.phases, options.timings);
                try std.testing.expectEqual(xirasm.Isa.riscv64, options.target.isa());
                try std.testing.expectEqual(@as(u16, 64), options.target.bits().?);
            },
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "parseCliArgs accepts SPIR-V target aliases" {
    const aliases = [_][]const u8{ "spv", "spirv" };
    for (aliases) |target_arg| {
        const args = [_][]const u8{ "xirasm", "module.asm", "--target", target_arg };
        const result = parseCliArgs(&args);
        switch (result) {
            .ok => |command| switch (command) {
                .assemble => |options| {
                    try std.testing.expectEqual(xirasm.Isa.spirv, options.target.isa());
                    try std.testing.expectEqual(@as(?u16, null), options.target.bits());
                },
                else => return error.WrongCommand,
            },
            .err => return error.ParseFailed,
        }
    }
}

test "parseCliArgs rejects removed stdout option" {
    const result = parseCliArgs(&.{ "xirasm", "demo.xir", "--stdout" });
    switch (result) {
        .ok => return error.ExpectedParseFailure,
        .err => |issue| switch (issue) {
            .unknown_option => |option| try std.testing.expectEqualStrings("--stdout", option),
            else => return error.WrongParseIssue,
        },
    }
}

test "parseCliArgs rejects option token as assemble output path" {
    const result = parseCliArgs(&.{ "xirasm", "demo.xir", "-o", "--stdout" });
    switch (result) {
        .ok => return error.ExpectedParseFailure,
        .err => |issue| switch (issue) {
            .missing_output_path => {},
            else => return error.WrongParseIssue,
        },
    }
}

test "parseCliArgs accepts build defaults" {
    const result = parseCliArgs(&.{ "xirasm", "build" });
    switch (result) {
        .ok => |command| switch (command) {
            .build => |options| {
                try std.testing.expect(options.source_path == null);
                try std.testing.expect(options.output_path == null);
            },
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "parseCliArgs accepts build timing summary" {
    const result = parseCliArgs(&.{ "xirasm", "build", "--timings" });
    switch (result) {
        .ok => |command| switch (command) {
            .build => |options| {
                try std.testing.expectEqual(TimingMode.summary, options.timings);
            },
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "parseCliArgs rejects option token as build output path" {
    const result = parseCliArgs(&.{ "xirasm", "build", "-o", "--stdout" });
    switch (result) {
        .ok => return error.ExpectedParseFailure,
        .err => |issue| switch (issue) {
            .missing_output_path => {},
            else => return error.WrongParseIssue,
        },
    }
}

test "parseCliArgs rejects options before build subcommand" {
    const result = parseCliArgs(&.{ "xirasm", "--timings", "build" });
    switch (result) {
        .ok => return error.ExpectedParseFailure,
        .err => |issue| switch (issue) {
            .misplaced_subcommand => |subcommand| try std.testing.expectEqualStrings("build", subcommand),
            else => return error.WrongParseIssue,
        },
    }
}

test "parseCliArgs accepts init target and name" {
    const result = parseCliArgs(&.{ "xirasm", "init", "demo", "--target", "rv64", "--name", "kernel" });
    switch (result) {
        .ok => |command| switch (command) {
            .init => |options| {
                try std.testing.expectEqualStrings("demo", options.dir_path.?);
                try std.testing.expectEqualStrings("kernel", options.name.?);
                try std.testing.expectEqualStrings("riscv64", options.target.isa);
                try std.testing.expectEqual(@as(u16, 64), options.target.bits);
                try std.testing.expectEqualStrings("none", options.target.os);
                try std.testing.expectEqualStrings("none", options.target.abi);
            },
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "parseCliArgs accepts init target fields" {
    const result = parseCliArgs(&.{ "xirasm", "init", "demo", "--isa", "x86", "--bits", "32", "--os", "windows", "--abi", "msvc" });
    switch (result) {
        .ok => |command| switch (command) {
            .init => |options| {
                try std.testing.expectEqualStrings("demo", options.dir_path.?);
                try std.testing.expectEqualStrings("x86", options.target.isa);
                try std.testing.expectEqual(@as(u16, 32), options.target.bits);
                try std.testing.expectEqualStrings("windows", options.target.os);
                try std.testing.expectEqualStrings("msvc", options.target.abi);
            },
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "initTomlTemplate writes target table fields" {
    const manifest = try initTomlTemplate(std.testing.allocator, "demo", .{
        .isa = "riscv32",
        .bits = 32,
        .os = "none",
        .abi = "embedded",
    });
    defer std.testing.allocator.free(manifest);

    try std.testing.expect(std.mem.indexOf(u8, manifest, "output = \"build/app.bin\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "[target]\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "isa = \"riscv32\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "bits = 32\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "os = \"none\"\n") != null);
    try std.testing.expect(std.mem.indexOf(u8, manifest, "abi = \"embedded\"\n") != null);
}

test "init output paths follow generated template kind" {
    try std.testing.expectEqualStrings("build/app.exe", initOutputPath(.{
        .isa = "x86-64",
        .bits = 64,
        .os = "windows",
        .abi = "msvc",
    }));
    try std.testing.expectEqualStrings("build/app", initOutputPath(.{
        .isa = "x86",
        .bits = 32,
        .os = "linux",
        .abi = "sysv",
    }));
    try std.testing.expectEqualStrings("build/app.bin", initOutputPath(.{
        .isa = "riscv64",
        .bits = 64,
        .os = "linux",
        .abi = "none",
    }));
}

test "init executable templates use ordinary format facade" {
    const pe64 = initMainTemplate(.{
        .isa = "x86-64",
        .bits = 64,
        .os = "windows",
        .abi = "msvc",
    });
    try std.testing.expect(std.mem.indexOf(u8, pe64, "import(\"format/format.inc\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, pe64, "format_pe64(") != null);
    try std.testing.expect(std.mem.indexOf(u8, pe64, "format_entry_mut(image, start)") != null);
    try std.testing.expect(std.mem.indexOf(u8, pe64, "format_entry(image") == null);
    try std.testing.expect(std.mem.indexOf(u8, pe64, "format/pe64.inc") == null);

    const elf32 = initMainTemplate(.{
        .isa = "x86",
        .bits = 32,
        .os = "linux",
        .abi = "sysv",
    });
    try std.testing.expect(std.mem.indexOf(u8, elf32, "import(\"format/format.inc\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, elf32, "format_elf32(") != null);
    try std.testing.expect(std.mem.indexOf(u8, elf32, "format_entry_mut(image, start)") != null);
    try std.testing.expect(std.mem.indexOf(u8, elf32, "format_entry(image") == null);
    try std.testing.expect(std.mem.indexOf(u8, elf32, "format/elf32.inc") == null);
}

test "init RISC-V template remains flat" {
    const source = initMainTemplate(.{
        .isa = "riscv64",
        .bits = 64,
        .os = "linux",
        .abi = "none",
    });
    try std.testing.expect(std.mem.indexOf(u8, source, "riscv.use64();") != null);
    try std.testing.expect(std.mem.indexOf(u8, source, "format/format.inc") == null);
}

test "generated include readme explains format layers" {
    const readme = initIncludeReadme();
    try std.testing.expect(std.mem.indexOf(u8, readme, "import(\"format/format.inc\");") != null);
    try std.testing.expect(std.mem.indexOf(u8, readme, "Advanced users") != null);
}

test "help text describes executable facade templates" {
    try std.testing.expect(std.mem.indexOf(u8, helpText(), "import(\"format/format.inc\")") != null);
    try std.testing.expect(std.mem.indexOf(u8, initHelpText(), "output build/app.exe") != null);
    try std.testing.expect(std.mem.indexOf(u8, initHelpText(), "format/format.inc") != null);
    try std.testing.expect(std.mem.indexOf(u8, targetsHelpText(), "PE32/PE64 executable") != null);
    try std.testing.expect(std.mem.indexOf(u8, targetsHelpText(), "no object section headers") == null);
}

test "parseCliArgs accepts init help topic" {
    const result = parseCliArgs(&.{ "xirasm", "help", "init" });
    switch (result) {
        .ok => |command| switch (command) {
            .help => |topic| try std.testing.expectEqual(HelpTopic.init, topic),
            else => return error.WrongCommand,
        },
        .err => return error.ParseFailed,
    }
}

test "initProjectName trims directory separators" {
    const name = try initProjectName(std.testing.allocator, std.testing.io, .{
        .dir_path = "demo\\",
    });
    defer std.testing.allocator.free(name);

    try std.testing.expectEqualStrings("demo", name);
}

test "build config reads source output and target defaults" {
    const text =
        \\[build]
        \\source = "src/app.xir"
        \\output = "build/app.bin"
        \\target = "rv64"
        \\
    ;
    var config = try xirasm.data.loadBuildConfig(std.testing.allocator, text);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("src/app.xir", config.source.?);
    try std.testing.expectEqualStrings("build/app.bin", config.output.?);
    try std.testing.expectEqualStrings("rv64", config.target.?);
}

test "build options use target table when build target is absent" {
    var config = try xirasm.data.loadProjectConfig(std.testing.allocator,
        \\[build]
        \\source = "src/app.xir"
        \\output = "build/app.bin"
        \\
        \\[target]
        \\isa = "riscv64"
        \\bits = 32
        \\
    );
    defer config.deinit(std.testing.allocator);

    const resolved = try resolveBuildOptions(config, .{});
    try std.testing.expectEqualStrings("src/app.xir", resolved.source_path);
    try std.testing.expectEqualStrings("build/app.bin", resolved.output_path);
    try std.testing.expectEqual(xirasm.Isa.riscv64, resolved.target.isa());
    try std.testing.expectEqual(@as(u16, 32), resolved.target.bits().?);
}

test "build options prefer cli target over project config target" {
    var config = try xirasm.data.loadProjectConfig(std.testing.allocator,
        \\[build]
        \\source = "src/app.xir"
        \\
        \\[target]
        \\isa = "riscv64"
        \\bits = 64
        \\
    );
    defer config.deinit(std.testing.allocator);

    const resolved = try resolveBuildOptions(config, .{
        .target = .{ .x86 = .{ .mode_bits = 32 } },
    });
    try std.testing.expectEqual(xirasm.Isa.x86_64, resolved.target.isa());
    try std.testing.expectEqual(@as(u16, 32), resolved.target.bits().?);
}

test "project flat assembly applies defines and includes before main source" {
    const defines = [_]xirasm.data.Define{
        .{
            .name = "page_size",
            .value = .{ .integer = 4 },
        },
    };
    const includes = [_]SourceInput{
        .{
            .path = "include/project.xir",
            .bytes =
            \\emit.u8(page_size);
            \\const prefix: u64 = 2;
            \\emit.u8(prefix);
            \\
            ,
        },
    };
    const main_source = SourceInput{
        .path = "src/main.xir",
        .bytes =
        \\emit.u8(prefix + 1);
        \\ret
        \\
        ,
    };

    var assembled = try assembleProjectFlat(
        std.testing.allocator,
        std.testing.io,
        null,
        xirasm.Target.default,
        &defines,
        &includes,
        main_source,
    );
    defer assembled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), assembled.bytes.len);
    try std.testing.expectEqualSlices(u8, &.{ 4, 2, 3, 0xc3 }, assembled.bytes);
    try std.testing.expectEqual(@as(usize, 1), assembled.encoded_count);
    try std.testing.expectEqual(@as(usize, 0), assembled.pending_fixups);
}

test "project diagnostics report include source path" {
    const includes = [_]SourceInput{
        .{
            .path = "include/project.xir",
            .bytes =
            \\emit.u8(1);
            \\org 0x7c00
            \\
            ,
        },
    };
    const main_source = SourceInput{
        .path = "src/main.xir",
        .bytes =
        \\ret
        \\
        ,
    };

    var diagnostics: Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const result = assembleProjectFlat(
        std.testing.allocator,
        std.testing.io,
        &diagnostics.writer,
        xirasm.Target.default,
        &.{},
        &includes,
        main_source,
    );
    try std.testing.expectError(error.FrontendDiagnostics, result);
    try std.testing.expectEqualStrings(
        "include/project.xir:2:1: error: legacy assembler directive is not supported; use modern XIRASM API syntax\n",
        diagnostics.writer.buffered(),
    );
}

test "project diagnostics report main source path" {
    const main_source = SourceInput{
        .path = "src/main.xir",
        .bytes =
        \\emit.u8(1);
        \\db 0xff
        \\
        ,
    };

    var diagnostics: Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();

    const result = assembleProjectFlat(
        std.testing.allocator,
        std.testing.io,
        &diagnostics.writer,
        xirasm.Target.default,
        &.{},
        &.{},
        main_source,
    );
    try std.testing.expectError(error.FrontendDiagnostics, result);
    try std.testing.expectEqualStrings(
        "src/main.xir:2:1: error: legacy assembler directive is not supported; use modern XIRASM API syntax\n",
        diagnostics.writer.buffered(),
    );
}

test "project diagnostics report non-fatal Meta notes and warnings" {
    const main_source = SourceInput{
        .path = "src/main.asm",
        .bytes =
        \\print("building", 3);
        \\warn("check", here());
        \\emit.u8(0xaa);
        \\
        ,
    };

    var diagnostics: Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var assembled = try assembleProjectFlat(
        std.testing.allocator,
        std.testing.io,
        &diagnostics.writer,
        xirasm.Target.default,
        &.{},
        &.{},
        main_source,
    );
    defer assembled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), assembled.bytes.len);
    try std.testing.expectEqual(@as(u8, 0xaa), assembled.bytes[0]);
    try std.testing.expectEqualStrings(
        "src/main.asm:1:1: note: building 3\nsrc/main.asm:2:1: warning: check 0\n",
        diagnostics.writer.buffered(),
    );
}

test "project diagnostics report finalizer notes and warnings" {
    const main_source = SourceInput{
        .path = "src/main.asm",
        .bytes =
        \\emit.u8(0xaa);
        \\
        \\defer {
        \\    print("patched", load.u8(region_base()));
        \\    warn("done", load.bytes(region_base(), 1));
        \\}
        \\
        ,
    };

    var diagnostics: Io.Writer.Allocating = .init(std.testing.allocator);
    defer diagnostics.deinit();

    var assembled = try assembleProjectFlat(
        std.testing.allocator,
        std.testing.io,
        &diagnostics.writer,
        xirasm.Target.default,
        &.{},
        &.{},
        main_source,
    );
    defer assembled.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), assembled.bytes.len);
    try std.testing.expectEqual(@as(u8, 0xaa), assembled.bytes[0]);
    try std.testing.expectEqualStrings(
        "src/main.asm:4:5: note: patched 170\nsrc/main.asm:5:5: warning: done aa\n",
        diagnostics.writer.buffered(),
    );
}
