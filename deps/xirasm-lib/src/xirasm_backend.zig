const build_opts = @import("build_opts");

pub const x86 = @import("x86_encoder/root.zig");
pub const riscv = if (!build_opts.exclude_riscv) @import("riscv_encoder/root.zig") else struct {};
pub const spirv = if (!build_opts.exclude_spirv) @import("spirv_encoder/root.zig") else struct {};
