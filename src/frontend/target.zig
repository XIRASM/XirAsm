pub const Isa = enum {
    x86_64,
    aarch64,
    riscv64,
    spirv,
};

pub const X86Target = struct {
    mode_bits: u16 = 64,
};

/// AArch64 has no mode bits and no encoder in this assembler: its instructions
/// are produced by the generated A64 macro library, which emits bytes directly.
/// The target exists so a source can ask `target.isa == "aarch64"` and so the CLI
/// and project file can name the platform honestly instead of borrowing x86-64.
pub const ArmTarget = struct {
    bits: u16 = 64,
};

pub const RiscvTarget = struct {
    xlen: u8 = 64,
};

pub const SpirvTarget = struct {
    version: u32 = 0x00010600,
};

pub const Target = union(enum) {
    x86: X86Target,
    arm: ArmTarget,
    riscv: RiscvTarget,
    spirv: SpirvTarget,

    pub const default: Target = .{ .x86 = .{} };

    pub fn initX86(bit_width: u16) !Target {
        return switch (bit_width) {
            16, 32, 64 => .{ .x86 = .{ .mode_bits = bit_width } },
            else => error.InvalidModeBits,
        };
    }

    pub fn initArm() Target {
        return .{ .arm = .{} };
    }

    pub fn initRiscv(xlen_bits: u16) !Target {
        return switch (xlen_bits) {
            32, 64 => .{ .riscv = .{ .xlen = @intCast(xlen_bits) } },
            else => error.InvalidModeBits,
        };
    }

    pub fn spv() Target {
        return .{ .spirv = .{} };
    }

    pub fn isa(self: Target) Isa {
        return switch (self) {
            .x86 => .x86_64,
            .arm => .aarch64,
            .riscv => .riscv64,
            .spirv => .spirv,
        };
    }

    pub fn bits(self: Target) ?u16 {
        return switch (self) {
            .x86 => |cfg| cfg.mode_bits,
            .arm => |cfg| cfg.bits,
            .riscv => |cfg| cfg.xlen,
            .spirv => null,
        };
    }

    pub fn isDefault(self: Target) bool {
        return switch (self) {
            .x86 => |cfg| cfg.mode_bits == 64,
            .arm, .riscv, .spirv => false,
        };
    }
};
