const std = @import("std");

const diagnostic = @import("../diagnostic.zig");
const fragment = @import("../fragment.zig");
const source = @import("../source.zig");
const target = @import("../target.zig");

const Allocator = std.mem.Allocator;

pub const LowerError = Allocator.Error || error{
    SourceTooLarge,
    TooManySources,
    FrontendDiagnostics,
    InvalidLabel,
    InvalidApiCall,
    InvalidApiArgument,
    InvalidApiArity,
    InvalidApiInteger,
    FileNotAvailable,
    IncludeNotAvailable,
    IncludeCycle,
    IncludeTooDeep,
    InvalidExpression,
    InvalidValueDeclaration,
    InvalidAlignment,
    InvalidStructDeclaration,
    InvalidStructField,
    UnionFieldDefaultNotAllowed,
    DuplicateMetaFunction,
    InvalidMetaBlock,
    InvalidMetaDefer,
    InvalidLateLayout,
    InvalidMetaFor,
    InvalidMetaFunction,
    InvalidMetaIf,
    InvalidMetaWhile,
    MetaCallDepthExceeded,
    MetaLoopLimitExceeded,
    InvalidModeBits,
    UnexpectedEndOfMetaBlock,
    UnexpectedEndOfMetaDefer,
    UnexpectedEndOfLateLayout,
    UnexpectedEndOfMetaFor,
    UnexpectedEndOfMetaFunction,
    UnexpectedEndOfStruct,
    UnexpectedEndOfMetaIf,
    UnexpectedEndOfMetaWhile,
    UnexpectedEndOfStatement,
    LegacyDirectiveSyntax,
    InvalidFieldName,
    InvalidIntegerBits,
    InvalidType,
    IntegerOverflow,
    DuplicateFieldName,
    DuplicateTypeName,
    TooManyTypes,
    UnknownTypeName,
    UnknownField,
    ExpectedStruct,
    MissingStructFieldValue,
    UnknownApiCall,
    UnknownMetaFunction,
    UnknownMetaCondition,
    MetaFunctionReturned,
    MetaLoopBreak,
    MetaLoopContinue,
    MissingMetaReturn,
    SideEffectInValueFunction,
    UnmatchedVirtualEnd,
    UnclosedVirtualOutput,
    DivisionByZero,
    TooManyStatements,
    TooManySections,
    TooManyFragments,
    TooManyFixups,
    TooManySymbols,
    InvalidFixup,
    InvalidSymbol,
    InvalidSection,
    InvalidFragment,
    LateLayoutDidNotConverge,
    DuplicateSymbol,
    FragmentTooLarge,
    OffsetOverflow,
    OutputRegionClosed,
    FinalizerCannotChangeLayout,
};

pub const IncludeResolver = struct {
    context: *anyopaque,
    resolve: *const fn (context: *anyopaque, allocator: Allocator, request: IncludeRequest) LowerError!IncludeSource,
};

pub const IncludeRequest = struct {
    path: []const u8,
    parent_path: ?[]const u8,
    span: source.SourceSpan,
};

pub const IncludeSource = struct {
    path: []u8,
    bytes: []u8,

    pub fn deinit(self: *IncludeSource, allocator: Allocator) void {
        allocator.free(self.bytes);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const LowerOptions = struct {
    target: target.Target = target.Target.default,
    include_resolver: ?IncludeResolver = null,
};

pub const LateLayoutResult = struct {
    iterations: usize,
    executed_blocks: usize,
};

pub const ActiveOutput = struct {
    section_id: fragment.SectionId,
    offset: u64,
    file_offset: u64,
    file_aligned: bool = false,
    target: target.Target,
};

pub const OutputStoreTarget = struct {
    section: fragment.SectionId,
    address: u64,
};

pub const SectionId = fragment.SectionId;
pub const Fragment = fragment.Fragment;
pub const DiagnosticSeverity = diagnostic.Severity;
