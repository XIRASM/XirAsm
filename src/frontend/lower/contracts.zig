const std = @import("std");

const diagnostic = @import("../diagnostic.zig");
const fragment = @import("../fragment.zig");
const meta_io = @import("../meta_io.zig");
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
    UndefinedSymbol,
    InvalidValueDeclaration,
    InvalidAlignment,
    InvalidStructDeclaration,
    InvalidStructField,
    StatementNestingTooDeep,
    StructNestingTooDeep,
    ExpressionNestingTooDeep,
    NestingTooDeep,
    UnionFieldDefaultNotAllowed,
    DuplicateMetaFunction,
    InvalidMetaBlock,
    InvalidMetaStatement,
    InvalidMetaDefer,
    InvalidLateLayout,
    InvalidMetaFor,
    InvalidMetaFunction,
    InvalidMacro,
    DuplicateMacro,
    InvalidMacroOperands,
    MacroArityMismatch,
    MacroExpansionLimitExceeded,
    MacroCaptureDepthExceeded,
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
    TrailingTextAfterCall,
};

pub const IncludeResolver = struct {
    context: *anyopaque,
    resolve: *const fn (context: *anyopaque, allocator: Allocator, request: IncludeRequest) LowerError!IncludeSource,
    /// Resolves a path to an existing directory and lists it. Hosts that cannot
    /// enumerate directories leave these null; the frontend then reports the
    /// directory as unavailable instead of guessing.
    list_directory: ?*const fn (context: *anyopaque, allocator: Allocator, request: IncludeRequest) LowerError!meta_io.DirListing = null,
    is_directory: ?*const fn (context: *anyopaque, allocator: Allocator, request: IncludeRequest) LowerError!bool = null,
};

pub const IncludeRequest = struct {
    path: []const u8,
    parent_path: ?[]const u8,
    span: source.SourceSpan,
};

pub const IncludeSource = struct {
    path: []u8,
    identity: ?[]u8 = null,
    bytes: []u8,

    pub fn deinit(self: *IncludeSource, allocator: Allocator) void {
        allocator.free(self.bytes);
        if (self.identity) |identity| allocator.free(identity);
        allocator.free(self.path);
        self.* = undefined;
    }
};

pub const LowerOptions = struct {
    target: target.Target = target.Target.default,
    include_resolver: ?IncludeResolver = null,
    source_identity: ?[]const u8 = null,
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
    /// The `virtual.begin` call that opened this scratch region. End-of-input
    /// finds an unclosed region long after the statement that opened it, so the
    /// span has to travel with the output to report the failure where a reader
    /// can see it instead of as a bare `assembly failed: UnclosedVirtualOutput`.
    opened_at: ?source.SourceSpan = null,
};

pub const OutputStoreTarget = struct {
    section: fragment.SectionId,
    address: u64,
};

pub const SectionId = fragment.SectionId;
pub const Fragment = fragment.Fragment;
pub const DiagnosticSeverity = diagnostic.Severity;
