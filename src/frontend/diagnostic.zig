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

    pub fn deinit(self: *DiagnosticStore, allocator: Allocator) void {
        for (self.items.items) |*diagnostic| {
            diagnostic.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn add(
        self: *DiagnosticStore,
        allocator: Allocator,
        severity: Severity,
        span: source.SourceSpan,
        message: []const u8,
    ) !void {
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
