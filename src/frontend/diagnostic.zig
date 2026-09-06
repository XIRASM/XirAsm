const std = @import("std");

const source = @import("source.zig");

const Allocator = std.mem.Allocator;

pub const Severity = enum {
    note,
    warning,
    err,
};

pub const Diagnostic = struct {
    severity: Severity,
    span: source.SourceSpan,
    message: []u8,

    pub fn deinit(self: *Diagnostic, allocator: Allocator) void {
        allocator.free(self.message);
        self.* = undefined;
    }
};

pub const DiagnosticStore = struct {
    items: std.ArrayList(Diagnostic) = .empty,
    expansions: std.ArrayList(Expansion) = .empty,
    active_expansion: ?u32 = null,

    pub const Expansion = struct {
        invocation: source.SourceSpan,
        definition: source.SourceSpan,
    };

    pub fn beginExpansion(self: *DiagnosticStore, allocator: Allocator, invocation: source.SourceSpan, definition: source.SourceSpan) Allocator.Error!u32 {
        if (self.expansions.items.len >= std.math.maxInt(u32)) return error.OutOfMemory;
        const index: u32 = @intCast(self.expansions.items.len);
        var caller = invocation;
        caller.expansion = self.active_expansion;
        try self.expansions.append(allocator, .{ .invocation = caller, .definition = definition });
        return index;
    }

    pub fn deinit(self: *DiagnosticStore, allocator: Allocator) void {
        for (self.items.items) |*diagnostic| {
            diagnostic.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.expansions.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(
        self: *DiagnosticStore,
        allocator: Allocator,
        severity: Severity,
        span: source.SourceSpan,
        message: []const u8,
    ) !void {
        try self.addSingle(allocator, severity, span, message);
        var origin = span.expansion orelse self.active_expansion;
        while (origin) |index| {
            if (index >= self.expansions.items.len) break;
            const expansion = self.expansions.items[index];
            try self.addSingle(allocator, .note, expansion.invocation, "macro invoked here");
            try self.addSingle(allocator, .note, expansion.definition, "macro defined here");
            origin = expansion.invocation.expansion;
        }
    }

    fn addSingle(self: *DiagnosticStore, allocator: Allocator, severity: Severity, span: source.SourceSpan, message: []const u8) Allocator.Error!void {
        const owned_message = try allocator.dupe(u8, message);
        errdefer allocator.free(owned_message);

        try self.items.append(allocator, .{
            .severity = severity,
            .span = span,
            .message = owned_message,
        });
    }

    pub fn hasErrors(self: *const DiagnosticStore) bool {
        for (self.items.items) |item| {
            if (item.severity == .err) return true;
        }
        return false;
    }
};
