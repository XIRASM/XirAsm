const std = @import("std");

const toml = @import("toml_parser.zig");

const Allocator = std.mem.Allocator;

pub const ConfigError = Allocator.Error || toml.ParseError || error{
    InvalidBuildConfig,
    InvalidTargetConfig,
    InvalidDefineValue,
};

pub const ConfigValue = union(enum) {
    integer: u64,
    boolean: bool,
    string: []const u8,
};

pub const Define = struct {
    name: []const u8,
    value: ConfigValue,

    pub fn deinit(self: *Define, allocator: Allocator) void {
        allocator.free(self.name);
        switch (self.value) {
            .integer, .boolean => {},
            .string => |text| allocator.free(text),
        }
        self.* = undefined;
    }
};

pub const TargetConfig = struct {
    isa: ?[]const u8 = null,
    bits: ?u16 = null,
    os: ?[]const u8 = null,
    abi: ?[]const u8 = null,

    pub fn deinit(self: *TargetConfig, allocator: Allocator) void {
        if (self.isa) |value| allocator.free(value);
        if (self.os) |value| allocator.free(value);
        if (self.abi) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const IncludeConfig = struct {
    files: []const []const u8 = &.{},

    pub fn deinit(self: *IncludeConfig, allocator: Allocator) void {
        for (self.files) |file| {
            allocator.free(file);
        }
        allocator.free(self.files);
        self.* = undefined;
    }
};

pub const BuildConfig = struct {
    source: ?[]const u8 = null,
    output: ?[]const u8 = null,
    target: ?[]const u8 = null,

    pub fn deinit(self: *BuildConfig, allocator: Allocator) void {
        if (self.source) |value| allocator.free(value);
        if (self.output) |value| allocator.free(value);
        if (self.target) |value| allocator.free(value);
        self.* = undefined;
    }
};

pub const ProjectConfig = struct {
    build: BuildConfig = .{},
    target: TargetConfig = .{},
    defines: []const Define = &.{},
    include: IncludeConfig = .{},

    pub fn deinit(self: *ProjectConfig, allocator: Allocator) void {
        self.build.deinit(allocator);
        self.target.deinit(allocator);
        for (self.defines) |*define| {
            var owned = define.*;
            owned.deinit(allocator);
        }
        allocator.free(self.defines);
        self.include.deinit(allocator);
        self.* = undefined;
    }
};

pub fn loadBuildConfig(allocator: Allocator, source: []const u8) ConfigError!BuildConfig {
    var config = try loadProjectConfig(allocator, source);
    errdefer config.deinit(allocator);
    const build = config.build;
    config.target.deinit(allocator);
    for (config.defines) |*define| {
        var owned = define.*;
        owned.deinit(allocator);
    }
    allocator.free(config.defines);
    config.include.deinit(allocator);
    return build;
}

pub fn loadProjectConfig(allocator: Allocator, source: []const u8) ConfigError!ProjectConfig {
    var parsed = try toml.parse(allocator, source);
    defer parsed.deinit();

    var config = ProjectConfig{};
    errdefer config.deinit(allocator);

    if (getEntry(parsed.node, "build")) |build| {
        if (build.tag != .table) return error.InvalidBuildConfig;
        config.build = .{
            .source = try optionalString(allocator, build, "source"),
            .output = try optionalString(allocator, build, "output"),
            .target = try optionalString(allocator, build, "target"),
        };
    }

    if (getEntry(parsed.node, "target")) |target| {
        if (target.tag != .table) return error.InvalidTargetConfig;
        config.target = try parseTargetConfig(allocator, target);
    }
    if (getEntry(parsed.node, "defines")) |defines| {
        if (defines.tag != .table) return error.InvalidDefineValue;
        config.defines = try parseDefines(allocator, defines);
    }
    if (getEntry(parsed.node, "include")) |include| {
        if (include.tag != .table) return error.InvalidBuildConfig;
        config.include = .{ .files = try stringArray(allocator, include, "files") };
    }

    return config;
}

fn parseTargetConfig(allocator: Allocator, table: toml.Node) ConfigError!TargetConfig {
    return .{
        .isa = try optionalString(allocator, table, "isa"),
        .bits = try optionalU16(table, "bits"),
        .os = try optionalString(allocator, table, "os"),
        .abi = try optionalString(allocator, table, "abi"),
    };
}

fn parseDefines(allocator: Allocator, table: toml.Node) ConfigError![]const Define {
    const entries = table.data.table;
    const defines = try allocator.alloc(Define, entries.len);
    errdefer allocator.free(defines);

    var count: usize = 0;
    errdefer {
        for (defines[0..count]) |*define| {
            define.deinit(allocator);
        }
    }

    for (entries) |entry| {
        defines[count] = try defineFromTomlEntry(allocator, entry);
        count += 1;
    }

    return defines;
}

fn defineFromTomlEntry(allocator: Allocator, entry: toml.Node.Entry) ConfigError!Define {
    const name = try allocator.dupe(u8, entry.key);
    errdefer allocator.free(name);

    const value = try configValueFromToml(allocator, entry.value);
    return .{ .name = name, .value = value };
}

fn configValueFromToml(allocator: Allocator, node: toml.Node) ConfigError!ConfigValue {
    switch (node.tag) {
        .int64 => {
            if (node.data.int64 < 0) return error.InvalidDefineValue;
            return .{ .integer = @intCast(node.data.int64) };
        },
        .boolean => return .{ .boolean = node.data.boolean },
        .string => return .{ .string = try allocator.dupe(u8, node.data.string) },
        .fp64, .timestamp, .array, .table => return error.InvalidDefineValue,
    }
}

fn optionalString(allocator: Allocator, table: toml.Node, key: []const u8) ConfigError!?[]const u8 {
    const node = getEntry(table, key) orelse return null;
    if (node.tag != .string) return error.InvalidBuildConfig;
    const owned = try allocator.dupe(u8, node.data.string);
    return owned;
}

fn optionalU16(table: toml.Node, key: []const u8) ConfigError!?u16 {
    const node = getEntry(table, key) orelse return null;
    if (node.tag != .int64) return error.InvalidTargetConfig;
    if (node.data.int64 < 0 or node.data.int64 > std.math.maxInt(u16)) return error.InvalidTargetConfig;
    return @intCast(node.data.int64);
}

fn stringArray(allocator: Allocator, table: toml.Node, key: []const u8) ConfigError![]const []const u8 {
    const node = getEntry(table, key) orelse return &.{};
    if (node.tag != .array) return error.InvalidBuildConfig;
    const files = try allocator.alloc([]const u8, node.data.array.len);
    errdefer allocator.free(files);

    var count: usize = 0;
    errdefer {
        for (files[0..count]) |file| {
            allocator.free(file);
        }
    }

    for (node.data.array) |item| {
        if (item.tag != .string) return error.InvalidBuildConfig;
        files[count] = try allocator.dupe(u8, item.data.string);
        count += 1;
    }

    return files;
}

fn getEntry(node: toml.Node, key: []const u8) ?toml.Node {
    if (node.tag != .table) return null;
    for (node.data.table) |entry| {
        if (std.mem.eql(u8, entry.key, key)) return entry.value;
    }
    return null;
}

test "config reads build defaults from toml" {
    const text =
        \\[project]
        \\name = "demo"
        \\
        \\[build]
        \\source = "src/main.xir"
        \\output = "build/app.bin"
        \\target = "rv64"
        \\
    ;

    var config = try loadBuildConfig(std.testing.allocator, text);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("src/main.xir", config.source.?);
    try std.testing.expectEqualStrings("build/app.bin", config.output.?);
    try std.testing.expectEqualStrings("rv64", config.target.?);
}

test "config allows missing build table" {
    var config = try loadBuildConfig(std.testing.allocator, "name = \"demo\"\n");
    defer config.deinit(std.testing.allocator);
    try std.testing.expect(config.source == null);
    try std.testing.expect(config.output == null);
    try std.testing.expect(config.target == null);
}

test "project config reads target defines and include files" {
    const text =
        \\[build]
        \\source = "src/main.xir"
        \\output = "build/app.bin"
        \\
        \\[target]
        \\isa = "x86-64"
        \\bits = 64
        \\os = "bin"
        \\abi = "none"
        \\
        \\[defines]
        \\page_size = 4096
        \\debug = true
        \\name = "demo"
        \\
        \\[include]
        \\files = ["include/project.xir", "include/memory.xir"]
        \\
    ;

    var config = try loadProjectConfig(std.testing.allocator, text);
    defer config.deinit(std.testing.allocator);

    try std.testing.expectEqualStrings("x86-64", config.target.isa.?);
    try std.testing.expectEqual(@as(u16, 64), config.target.bits.?);
    try std.testing.expectEqualStrings("bin", config.target.os.?);
    try std.testing.expectEqualStrings("none", config.target.abi.?);
    try std.testing.expectEqual(@as(usize, 3), config.defines.len);
    try std.testing.expectEqualStrings("page_size", config.defines[0].name);
    try std.testing.expectEqual(@as(u64, 4096), config.defines[0].value.integer);
    try std.testing.expectEqual(true, config.defines[1].value.boolean);
    try std.testing.expectEqualStrings("demo", config.defines[2].value.string);
    try std.testing.expectEqual(@as(usize, 2), config.include.files.len);
    try std.testing.expectEqualStrings("include/project.xir", config.include.files[0]);
    try std.testing.expectEqualStrings("include/memory.xir", config.include.files[1]);
}
