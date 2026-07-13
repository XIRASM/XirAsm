const expr = @import("../expr.zig");
const module_mod = @import("../module.zig");
const pass = @import("../pass.zig");
const contracts = @import("contracts.zig");
const layout_cursor = @import("layout_cursor.zig");

const ActiveOutput = contracts.ActiveOutput;
const LowerError = contracts.LowerError;

pub fn forExpression(module: *module_mod.Module, node: *const expr.Node) LowerError!void {
    if (!expr.usesOutputLoad(node)) return;
    try forOutputAccess(module);
}

pub fn forOutputAccess(module: *module_mod.Module) LowerError!void {
    const result = pass.encodeInstructionFragments(module.allocator, module) catch |err| return mapPassError(err);
    if (result.changed_count > result.encoded_count) return error.InvalidApiArgument;
}

pub fn syncActiveOutput(module: *module_mod.Module, active: *ActiveOutput) LowerError!void {
    try forOutputAccess(module);
    active.offset = try layout_cursor.sectionCursor(module, active.section_id);
    active.file_offset = try layout_cursor.sectionFileCursor(module, active.section_id);
}

fn mapPassError(err: pass.PassError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.FragmentTooLarge => error.FragmentTooLarge,
        error.InvalidFragment => error.InvalidFragment,
        error.InvalidSection => error.InvalidSection,
        error.InvalidModeBits => error.InvalidModeBits,
        error.OffsetOverflow => error.OffsetOverflow,
        error.TooManyFixups => error.TooManyFixups,
        error.FrontendDiagnostics => error.FrontendDiagnostics,
        error.InstructionTooLarge,
        error.InvalidFixupTarget,
        error.InvalidInstructionText,
        => error.InvalidApiArgument,
    };
}
