const expr = @import("../expr.zig");
const fragment_mod = @import("../fragment.zig");
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

/// Make the cursor current for an expression that reads the current address:
/// the instruction fragments written before it only get a size when they are
/// encoded, so the cursor has to be recomputed from them first.
pub fn syncForExpression(
    module: *module_mod.Module,
    active: *ActiveOutput,
    node: *const expr.Node,
) LowerError!void {
    if (!expr.usesCurrentAddress(node)) return;
    try syncActiveOutput(module, active);
}

pub fn forOutputAccess(module: *module_mod.Module) LowerError!void {
    // Instruction fragments are only appended while lowering, so everything
    // before the watermark already has a size and only the new ones are encoded.
    // Encoding all of them on every call would be quadratic over a source that
    // reads the current address once per generated row.
    const start_index = module.materialized_fragment_count;
    if (start_index >= module.fragments.items.items.len) return;

    const result = pass.encodeInstructionFragmentsFrom(module.allocator, module, start_index) catch |err| return mapPassError(err);
    if (result.changed_count > result.encoded_count) return error.InvalidApiArgument;
    module.materialized_fragment_count = module.fragments.items.items.len;
}

pub fn syncActiveOutput(module: *module_mod.Module, active: *ActiveOutput) LowerError!void {
    try forOutputAccess(module);

    // The cursor is rebuilt from the fragments rather than adjusted in place: the
    // active output a caller holds is a copy, and instruction fragments were
    // appended while their size was still unknown, so no copy can be trusted to
    // have accounted for them. The walk is linear in the region, and only
    // statements that read the current address pay for it.
    active.offset = try layout_cursor.sectionCursor(module, active.section_id);
    active.file_offset = try layout_cursor.sectionFileCursor(module, active.section_id);
}

fn mapPassError(err: pass.PassError) LowerError {
    return switch (err) {
        error.OutOfMemory => error.OutOfMemory,
        error.ExpressionNestingTooDeep => error.ExpressionNestingTooDeep,
        error.NestingTooDeep => error.NestingTooDeep,
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
