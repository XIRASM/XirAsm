const root = @import("lower/root.zig");

pub const LowerError = root.LowerError;
pub const LowerOptions = root.LowerOptions;
pub const LateLayoutResult = root.LateLayoutResult;
pub const IncludeResolver = root.IncludeResolver;
pub const IncludeRequest = root.IncludeRequest;
pub const IncludeSource = root.IncludeSource;
pub const LowerContext = root.LowerContext;
pub const max_finalizer_loop_iterations = root.max_finalizer_loop_iterations;

pub const lowerSource = root.lowerSource;
pub const lowerSourceIntoModule = root.lowerSourceIntoModule;
pub const lowerSourceIntoModuleWithPath = root.lowerSourceIntoModuleWithPath;
pub const lowerSourceIntoModuleWithPathOptions = root.lowerSourceIntoModuleWithPathOptions;
pub const lowerStatements = root.lowerStatements;
pub const lowerStatementsIntoModule = root.lowerStatementsIntoModule;
pub const runLateLayoutPhase = root.runLateLayoutPhase;
pub const evalModuleValueFunction = root.evalModuleValueFunction;
pub const evalModuleStructLiteralValue = root.evalModuleStructLiteralValue;
pub const pushMetaScope = root.pushMetaScope;
pub const popMetaScope = root.popMetaScope;
pub const defineFinalLocalValue = root.defineFinalLocalValue;
pub const setFinalLocalValue = root.setFinalLocalValue;
pub const resolveLocalValue = root.resolveLocalValue;
