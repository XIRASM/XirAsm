const std = @import("std");

const image = @import("image.zig");
const source = @import("../source.zig");
const value_mod = @import("../value.zig");

const Allocator = std.mem.Allocator;

pub const image_mod = image;
pub const result = @import("result.zig");
pub const writer = @import("writer.zig");

pub const Error = image.Error;
pub const Image = image.Image;
pub const ImageRegion = image.ImageRegion;
pub const RegionFacts = image.RegionFacts;
pub const regionFactsForAddress = image.regionFactsForAddress;
pub const regionFactsForSection = image.regionFactsForSection;
pub const WriterResult = result.WriterResult;

pub const DeferredStatement = union(enum) {
    api_call: ApiCall,
    meta_if: MetaIf,
    // api-matrix-output: DeferredStatement.value_decl
    value_decl: ValueDeclaration,
    // api-matrix-output: DeferredStatement.assignment
    assignment: Assignment,
    // api-matrix-output: DeferredStatement.meta_while
    meta_while: MetaWhile,
    meta_break: source.SourceSpan,
    meta_continue: source.SourceSpan,

    pub fn deinit(self: *DeferredStatement, allocator: Allocator) void {
        switch (self.*) {
            .api_call => |*call| call.deinit(allocator),
            .meta_if => |*meta_if| meta_if.deinit(allocator),
            .value_decl => |*declaration| declaration.deinit(allocator),
            .assignment => |*assignment| assignment.deinit(allocator),
            .meta_while => |*meta_while| meta_while.deinit(allocator),
            .meta_break, .meta_continue => {},
        }
        self.* = undefined;
    }

    pub fn span(self: DeferredStatement) source.SourceSpan {
        return switch (self) {
            .api_call => |call| call.span,
            .meta_if => |meta_if| meta_if.span,
            .value_decl => |declaration| declaration.span,
            .assignment => |assignment| assignment.span,
            .meta_while => |meta_while| meta_while.span,
            .meta_break, .meta_continue => |statement_span| statement_span,
        };
    }
};

pub const ApiCall = struct {
    text: []u8,
    span: source.SourceSpan,

    pub fn deinit(self: *ApiCall, allocator: Allocator) void {
        allocator.free(self.text);
        self.* = undefined;
    }
};

pub const ValueDeclaration = struct {
    name: []u8,
    type_name: ?[]u8 = null,
    mutability: value_mod.Mutability,
    value_text: []u8,
    span: source.SourceSpan,

    pub fn deinit(self: *ValueDeclaration, allocator: Allocator) void {
        allocator.free(self.name);
        if (self.type_name) |type_name| {
            allocator.free(type_name);
        }
        allocator.free(self.value_text);
        self.* = undefined;
    }
};

pub const Assignment = struct {
    name: []u8,
    value_text: []u8,
    span: source.SourceSpan,

    pub fn deinit(self: *Assignment, allocator: Allocator) void {
        allocator.free(self.name);
        allocator.free(self.value_text);
        self.* = undefined;
    }
};

pub const MetaIf = struct {
    condition: []u8,
    body: []DeferredStatement,
    else_body: []DeferredStatement = &.{},
    span: source.SourceSpan,

    pub fn deinit(self: *MetaIf, allocator: Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        for (self.else_body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.else_body);
        self.* = undefined;
    }
};

pub const MetaWhile = struct {
    condition: []u8,
    body: []DeferredStatement,
    span: source.SourceSpan,

    pub fn deinit(self: *MetaWhile, allocator: Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const DeferredBlock = struct {
    body: []DeferredStatement,
    span: source.SourceSpan,

    pub fn deinit(self: *DeferredBlock, allocator: Allocator) void {
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const DeferredStore = struct {
    items: std.ArrayList(DeferredBlock) = .empty,

    pub fn deinit(self: *DeferredStore, allocator: Allocator) void {
        for (self.items.items) |*block| {
            block.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn append(self: *DeferredStore, allocator: Allocator, block: DeferredBlock) Allocator.Error!void {
        try self.items.append(allocator, block);
    }
};

pub const LateLayoutStatement = union(enum) {
    api_call: ApiCall,
    meta_if: LateLayoutMetaIf,

    pub fn deinit(self: *LateLayoutStatement, allocator: Allocator) void {
        switch (self.*) {
            .api_call => |*call| call.deinit(allocator),
            .meta_if => |*meta_if| meta_if.deinit(allocator),
        }
        self.* = undefined;
    }

    pub fn span(self: LateLayoutStatement) source.SourceSpan {
        return switch (self) {
            .api_call => |call| call.span,
            .meta_if => |meta_if| meta_if.span,
        };
    }
};

pub const LateLayoutMetaIf = struct {
    condition: []u8,
    body: []LateLayoutStatement,
    else_body: []LateLayoutStatement = &.{},
    span: source.SourceSpan,

    pub fn deinit(self: *LateLayoutMetaIf, allocator: Allocator) void {
        allocator.free(self.condition);
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        for (self.else_body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.else_body);
        self.* = undefined;
    }
};

pub const LateLayoutBlock = struct {
    body: []LateLayoutStatement,
    span: source.SourceSpan,

    pub fn deinit(self: *LateLayoutBlock, allocator: Allocator) void {
        for (self.body) |*statement| {
            statement.deinit(allocator);
        }
        allocator.free(self.body);
        self.* = undefined;
    }
};

pub const LateLayoutStore = struct {
    items: std.ArrayList(LateLayoutBlock) = .empty,

    pub fn deinit(self: *LateLayoutStore, allocator: Allocator) void {
        for (self.items.items) |*block| {
            block.deinit(allocator);
        }
        self.items.deinit(allocator);
        self.* = undefined;
    }

    pub fn append(self: *LateLayoutStore, allocator: Allocator, block: LateLayoutBlock) Allocator.Error!void {
        try self.items.append(allocator, block);
    }
};
