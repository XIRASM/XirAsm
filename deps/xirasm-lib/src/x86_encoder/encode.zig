//! x86 `asm/assemble.c` encode-stage translation.
//!
//! This file is the Zig landing point for the staged x86 encode runtime.
//! `prefix_byte`, `emit_prefixes`, `emit_rex`, and an incremental `gencode`
//! slice are ported here directly from `assemble.c`.

const std = @import("std");
const bytecode = @import("bytecode.zig");
const ea = @import("ea.zig");
const generated = @import("generated_match_tables.zig");
const generated_registers = @import("generated_registers.zig");
const match = @import("match.zig");
const regs = @import("regs.zig");
const size = @import("size.zig");
const types = @import("types.zig");

const Allocator = std.mem.Allocator;

pub const encode_stage_functions = [_][]const u8{ "prefix_byte", "emit_prefixes", "emit_rex", "gencode" };

const out_wrap: u8 = types.out_wrap;
const out_signed: u8 = types.out_signed;
const out_unsigned: u8 = types.out_unsigned;
const out_signmask: u8 = types.out_signmask;
const out_nowarn: u8 = types.out_nowarn;

const if_jcc_hint: u32 = types.if_jcc_hint;
const rex_mask: u32 = types.rex_mask;
const rex_b: u32 = types.rex_b;
const rex_x: u32 = types.rex_x;
const rex_r: u32 = types.rex_r;
const rex_w: u32 = types.rex_w;
const rex_l: u32 = types.rex_l;
const rex_p: u32 = types.rex_p;
const rex_v: u32 = types.rex_v;
const rex_ev: u32 = types.rex_ev;
const rex_2: u32 = types.rex_2;
const rex_b1: u32 = types.rex_b1;
const rex_x1: u32 = types.rex_x1;
const rex_r1: u32 = types.rex_r1;
const rex_bv: u32 = types.rex_bv;
const rex_xv: u32 = types.rex_xv;
const rex_bxr0: u32 = types.rex_bxr0;
const rex_bxr1: u32 = types.rex_bxr1;

const evex_w: u32 = types.evex_w;
const evex_aaa: u32 = types.evex_aaa;
const evex_nf: u32 = types.evex_nf;
const evex_v4: u32 = types.evex_v4;
const evex_b4: u32 = types.evex_b4;
const evex_nd: u32 = types.evex_nd;
const evex_x4: u32 = types.evex_x4;
const evex_r4: u32 = types.evex_r4;
const evex_x3: u32 = types.evex_x3;
const evex_z: u32 = types.evex_z;

const pfe_null: i32 = types.pfe_null;
const pfe_multi: i32 = types.pfe_multi;
const pfe_err: i32 = types.pfe_err;
const pfe_what: i32 = types.pfe_what;

const r_cs: i32 = exprRegByEnumName("R_CS");
const r_ds: i32 = exprRegByEnumName("R_DS");
const r_es: i32 = exprRegByEnumName("R_ES");
const r_fs: i32 = exprRegByEnumName("R_FS");
const r_gs: i32 = exprRegByEnumName("R_GS");
const r_ss: i32 = exprRegByEnumName("R_SS");

pub const PrefixEmitError = error{
    InvalidAddressSize,
    InvalidOperandSize,
    InvalidPrefixEncoding,
};

pub const PrefixWarning = enum(u8) {
    invalid_prefix_for_instruction,
    segment_override_ignored_64,
};

pub const PrefixDiagnostics = struct {
    const warning_count = @typeInfo(PrefixWarning).@"enum".field_names.len;

    warnings: [warning_count]u32 = @splat(@as(u32, 0)),

    pub fn record(self: *PrefixDiagnostics, warning: PrefixWarning) void {
        const index = @intFromEnum(warning);
        if (self.warnings[index] < std.math.maxInt(u32)) {
            self.warnings[index] += 1;
        }
    }

    pub fn count(self: *const PrefixDiagnostics, warning: PrefixWarning) u32 {
        return self.warnings[@intFromEnum(warning)];
    }
};

pub const PrefixBytes = struct {
    storage: [match.max_prefix]u8 = @splat(@as(u8, 0)),
    len: usize = 0,

    pub fn slice(self: *const PrefixBytes) []const u8 {
        return self.storage[0..self.len];
    }
};

pub const RexBytes = struct {
    storage: [4]u8 = @splat(@as(u8, 0)),
    len: usize = 0,

    pub fn slice(self: *const RexBytes) []const u8 {
        return self.storage[0..self.len];
    }
};

pub const GencodeError = Allocator.Error || bytecode.BytecodeError || regs.RegisterError || PrefixEmitError || error{
    MissingTemplate,
    MissingOperand,
    InvalidBytecodePayload,
    InvalidReserveOpcode,
    InvalidReserveSize,
    NonConstantReserve,
    OutputOverflow,
    ReserveOverflow,
    UnsupportedBytecode,
};

pub const FixupKind = enum {
    absolute,
    relative,
    segment,
};

pub const Fixup = struct {
    kind: FixupKind,
    size: u8,
    flags: u8,
    toffset: i64,
    tsegment: i32,
    twrt: i32,
    relbase: i64,
};

pub const EncodeUnit = struct {
    kind: []const u8,
    bytes: []const u8,
    fixup: ?Fixup = null,
    reserve_len: u64 = 0,
    bytecode: ?u8 = null,
    note: ?[]const u8 = null,
};

pub const OwnedEncodeResult = struct {
    loc: match.Location,
    bits: u8,
    inslen: usize,
    insoffs: usize = 0,
    itemp: ?match.TemplateRef = null,
    units: std.ArrayList(EncodeUnit) = .empty,
    warnings: std.ArrayList([]const u8) = .empty,

    pub fn deinit(self: *OwnedEncodeResult, allocator: Allocator) void {
        for (self.units.items) |unit| {
            if (unit.bytes.len != 0) allocator.free(unit.bytes);
        }
        self.units.deinit(allocator);
        self.warnings.deinit(allocator);
        self.* = .{
            .loc = .{},
            .bits = 0,
            .inslen = 0,
        };
    }

    fn outRawdata(self: *OwnedEncodeResult, allocator: Allocator, bytes: []const u8, note: ?[]const u8, opcode: ?u8) GencodeError!void {
        const next_loc = try checkedAddI64(self.loc.offset, try lenToI64(bytes.len));
        const next_insoffs = try checkedAddUsize(self.insoffs, bytes.len);
        const owned_bytes = try allocator.dupe(u8, bytes);
        errdefer allocator.free(owned_bytes);

        try self.units.append(allocator, .{
            .kind = "raw",
            .bytes = owned_bytes,
            .bytecode = opcode,
            .note = note,
        });
        self.loc.offset = next_loc;
        self.insoffs = next_insoffs;
    }

    fn outReserve(self: *OwnedEncodeResult, allocator: Allocator, size_bytes: u64, opcode: ?u8) GencodeError!void {
        const loc_delta = try reserveSizeToI64(size_bytes);
        const insoffs_delta = try reserveSizeToUsize(size_bytes);
        const next_loc = try checkedAddI64(self.loc.offset, loc_delta);
        const next_insoffs = try checkedAddUsize(self.insoffs, insoffs_delta);

        try self.units.append(allocator, .{
            .kind = "reserve",
            .bytes = &.{},
            .reserve_len = size_bytes,
            .bytecode = opcode,
            .note = "reserve",
        });
        self.loc.offset = next_loc;
        self.insoffs = next_insoffs;
    }

    fn outFixup(self: *OwnedEncodeResult, allocator: Allocator, kind: []const u8, size_bytes: usize, fixup: Fixup, note: ?[]const u8) GencodeError!void {
        const next_loc = try checkedAddI64(self.loc.offset, try lenToI64(size_bytes));
        const next_insoffs = try checkedAddUsize(self.insoffs, size_bytes);
        const owned_bytes = try allocator.alloc(u8, size_bytes);
        errdefer allocator.free(owned_bytes);
        @memset(owned_bytes, 0);

        try self.units.append(allocator, .{
            .kind = kind,
            .bytes = owned_bytes,
            .fixup = fixup,
            .note = note,
        });
        self.loc.offset = next_loc;
        self.insoffs = next_insoffs;
    }

    fn warn(self: *OwnedEncodeResult, allocator: Allocator, message: []const u8) GencodeError!void {
        try self.warnings.append(allocator, message);
    }
};

pub fn prefixByte(prefix: i32, bits: u8) i32 {
    return types.prefixByte(prefix, bits);
}

pub fn emitStandalonePrefix(allocator: Allocator, prefix: i32, bits: u8, output_position: i64) GencodeError!OwnedEncodeResult {
    const byte = prefixByte(prefix, bits);
    if (byte == pfe_err) return prefixByteError(prefix);
    if (byte == pfe_multi or byte == pfe_what) return error.InvalidPrefixEncoding;

    var result: OwnedEncodeResult = .{
        .loc = .{ .offset = output_position },
        .bits = bits,
        .inslen = if (byte >= 0) 1 else 0,
    };
    errdefer result.deinit(allocator);

    if (byte >= 0) {
        if (byte > std.math.maxInt(u8)) return error.InvalidPrefixEncoding;
        try result.outRawdata(allocator, &.{@intCast(byte)}, "standalone legacy prefix", null);
    }

    return result;
}

pub fn emitPrefixes(diagnostics: ?*PrefixDiagnostics, ins: *const match.Instruction) PrefixEmitError!PrefixBytes {
    var out: PrefixBytes = .{};

    for (ins.prefixes, ins.need_pfx) |prefix, required| {
        const prefix_raw = prefix.raw();
        var byte = prefixByte(prefix_raw, ins.bits);

        if (required != 0 and required != byte and !(required <= 0 and byte <= 0)) {
            switch (prefix_raw) {
                match.p_none, match.p_o16, match.p_o32, match.p_o64, match.p_a16, match.p_a32, match.p_a64 => {
                    byte = required;
                },
                else => if (diagnostics) |state| {
                    state.record(.invalid_prefix_for_instruction);
                },
            }
        }

        switch (prefix_raw) {
            r_cs, r_ds => {
                if (!templateHasJccHint(ins) and ins.bits == 64) {
                    if (diagnostics) |state| state.record(.segment_override_ignored_64);
                }
            },
            r_es, r_ss => {
                if (ins.bits == 64) {
                    if (diagnostics) |state| state.record(.segment_override_ignored_64);
                }
            },
            match.p_a16 => {
                if (ins.bits == 64) return error.InvalidAddressSize;
            },
            match.p_a64 => {
                if (ins.bits != 64) return error.InvalidAddressSize;
            },
            match.p_o64 => {
                if (ins.bits != 64) return error.InvalidOperandSize;
            },
            else => switch (byte) {
                0x66, 0xf2, 0xf3 => {
                    if ((ins.rex & (rex_v | rex_ev)) != 0) {
                        byte = pfe_null;
                    }
                },
                pfe_err => return prefixByteError(prefix_raw),
                pfe_what => return error.InvalidPrefixEncoding,
                else => {},
            },
        }

        if (byte >= 0) {
            if (byte > std.math.maxInt(u8)) return error.InvalidPrefixEncoding;
            if (out.len >= out.storage.len) return error.InvalidPrefixEncoding;
            out.storage[out.len] = @intCast(byte);
            out.len += 1;
        }
    }

    return out;
}

pub fn emitRex(ins: *match.Instruction) PrefixEmitError!RexBytes {
    var out: RexBytes = .{};

    if (ins.rex_done) return out;
    ins.rex_done = true;

    if ((ins.rex & (rex_v | rex_ev)) != 0) return out;

    if ((ins.rex & rex_2) != 0) {
        out.storage[0] = 0xd5;
        out.storage[1] = @intCast(ins.rex & (rex_bxr0 | rex_w));
        out.storage[1] |= @intCast((ins.rex & rex_bxr1) >> 8);
        out.storage[1] |= ins.vex_cm << 7;
        out.len = 2;
        return out;
    }

    const rex = @as(u8, @intCast(ins.rex & (rex_mask | rex_l)));
    if (rex == @as(u8, @intCast(rex_l | rex_r))) {
        out.storage[out.len] = 0xf0;
        out.len += 1;
    } else if ((rex & @as(u8, @intCast(rex_p))) != 0) {
        out.storage[out.len] = rex;
        out.len += 1;
    } else if ((rex & ~@as(u8, @intCast(rex_l))) != 0) {
        return error.InvalidPrefixEncoding;
    }

    if (ins.vex_cm != 0) {
        out.storage[out.len] = 0x0f;
        out.len += 1;
        if (ins.vex_cm > 1) {
            out.storage[out.len] = 0x34 +% (ins.vex_cm << 1);
            out.len += 1;
        }
    }

    return out;
}

pub fn gencode(allocator: Allocator, ins: *match.Instruction, inslen: usize) GencodeError!OwnedEncodeResult {
    const temp = ins.itemp orelse return error.MissingTemplate;
    var cursor = try bytecode.BytecodeCursor.init(temp);
    var result: OwnedEncodeResult = .{
        .loc = ins.loc,
        .bits = ins.bits,
        .inslen = inslen,
        .itemp = temp,
    };
    errdefer result.deinit(allocator);

    ins.rex_done = false;

    var prefix_diagnostics: PrefixDiagnostics = .{};
    const prefix_bytes = try emitPrefixes(&prefix_diagnostics, ins);
    try appendPrefixWarnings(&result, allocator, &prefix_diagnostics);
    if (prefix_bytes.len != 0) {
        try result.outRawdata(allocator, prefix_bytes.slice(), "legacy prefixes", null);
    }

    while (true) {
        const code = try cursor.nextRequired();
        if (code == 0) break;
        const indices = cursor.operandIndices(code);
        cursor.clearOpex();

        switch (code) {
            0o001...0o004 => {
                const rex_bytes = try emitRex(ins);
                if (rex_bytes.len != 0) {
                    try result.outRawdata(allocator, rex_bytes.slice(), "emit_rex", null);
                }

                var literal_storage: [4]u8 = undefined;
                for (0..code) |index| {
                    literal_storage[index] = try cursor.nextRequired();
                }
                try result.outRawdata(allocator, literal_storage[0..code], "literal opcode", code);
            },
            0o005...0o007 => {
                cursor.setOpex(code);
            },
            0o010...0o013 => {
                const rex_bytes = try emitRex(ins);
                if (rex_bytes.len != 0) {
                    try result.outRawdata(allocator, rex_bytes.slice(), "emit_rex", null);
                }

                const opx = try getOperand(ins, indices.primary);
                const base = try cursor.nextRequired();
                const reg = try regs.regval(opx);
                const encoded = base +% @as(u8, @intCast(reg & 7));
                try result.outRawdata(allocator, &.{encoded}, "+r opcode", code);
            },
            0o020...0o023 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 1, out_wrap, "ib");
            },
            0o024...0o027 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 1, out_unsigned, "ib,u");
            },
            0o030...0o033 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 2, out_wrap, "iw");
            },
            0o034...0o037 => {
                const opx = try getOperand(ins, indices.primary);
                const immediate_size: usize = if ((opx.type_bits & (match.bits16 | match.bits32)) != 0)
                    if ((opx.type_bits & match.bits16) != 0) 2 else 4
                else if (ins.op_size == 16) 2 else 4;
                try outImm(&result, allocator, opx, @intCast(immediate_size), out_wrap, "iwd");
            },
            0o040...0o043 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 4, out_wrap, "id");
            },
            0o044...0o047 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, ins.addr_size >> 3, out_wrap, "iwdq");
            },
            0o050...0o053 => {
                const opx = try getOperand(ins, indices.primary);
                if (opx.segment == result.loc.segment) {
                    const relbase = try checkedAddI64(result.loc.offset, try remainingInsnLenToI64(&result));
                    const delta = sext(try checkedSubI64(opx.offset, relbase), ins.op_size);
                    if (delta < std.math.minInt(i8) or delta > std.math.maxInt(i8)) {
                        try result.warn(allocator, "short jump is out of range");
                    }
                }
                try outReladdr(&result, allocator, opx, 1, "rel8");
            },
            0o054...0o057 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 8, out_wrap, "iq");
            },
            0o060...0o063 => {
                const opx = try getOperand(ins, indices.primary);
                try outReladdr(&result, allocator, opx, 2, "rel16");
            },
            0o064...0o067 => {
                const opx = try getOperand(ins, indices.primary);
                const relative_size: usize = if ((opx.type_bits & (match.bits16 | match.bits32 | match.bits64)) != 0)
                    if ((opx.type_bits & match.bits16) != 0) 2 else 4
                else if (ins.op_size == 16) 2 else 4;
                try outReladdr(&result, allocator, opx, @intCast(relative_size), "rel");
            },
            0o070...0o073 => {
                const opx = try getOperand(ins, indices.primary);
                try outReladdr(&result, allocator, opx, 4, "rel32");
            },
            0o074...0o077 => {
                const opx = try getOperand(ins, indices.primary);
                if (opx.segment == match.no_seg) {
                    try result.warn(allocator, "value referenced by FAR is not relocatable");
                }
                try outFarseg(&result, allocator, opx);
            },
            0o254...0o257 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 4, out_signed, "id,s");
            },
            0o264...0o267 => {
                const opx = try getOperand(ins, indices.primary);
                try outImm(&result, allocator, opx, 4, out_unsigned, "id,u");
            },
            0o260...0o263,
            0o270,
            => {
                try consumeBytecodeBytes(&cursor, 2);
                try emitVexPrefixOutput(&result, allocator, ins, code);
            },
            0o171 => {
                const raw = try cursor.nextRequired();
                const operand_index = ((@as(usize, indices.secondary)) & ~@as(usize, 3)) | @as(usize, (raw >> 3) & 3);
                const opx = try getOperandAt(ins, operand_index);
                const reg = try regs.regval(opx);
                const encoded = (raw & ~@as(u8, 0o70)) | (@as(u8, @intCast(reg & 7)) << 3);
                try result.outRawdata(allocator, &.{encoded}, "/mrb", code);
            },
            0o172 => {
                const mask: i64 = if (ins.prefixes[match.PrefixSlot.rex.index()].raw() == match.p_evex) 7 else 15;
                const raw = try cursor.nextRequired();
                const lhs = try getOperandAt(ins, (raw >> 3) & 7);
                const rhs = try getOperandAt(ins, raw & 7);
                if (!absoluteOp(rhs)) {
                    try result.warn(allocator, "non-absolute expression not permitted as is4 argument");
                } else if ((rhs.offset & ~mask) != 0) {
                    try result.warn(allocator, "is4 argument exceeds bounds");
                }
                const reg = try regs.regval(lhs);
                const imm = truncateU8(rhs.offset) & @as(u8, @intCast(mask));
                const encoded = (@as(u8, @intCast(reg)) << 4) | (((@as(u8, @intCast(reg)) & 0x10) >> 1)) | imm;
                try result.outRawdata(allocator, &.{encoded}, "/is4", code);
            },
            0o173 => {
                const raw = try cursor.nextRequired();
                const lhs = try getOperandAt(ins, raw >> 4);
                const reg = try regs.regval(lhs);
                const imm = raw & 0x0f;
                const encoded = (@as(u8, @intCast(reg)) << 4) | (((@as(u8, @intCast(reg)) & 0x10) >> 1)) | imm;
                try result.outRawdata(allocator, &.{encoded}, "/is4=NN", code);
            },
            0o174...0o177 => {
                const opx = try getOperand(ins, indices.primary);
                const reg = try regs.regval(opx);
                const encoded = (@as(u8, @intCast(reg)) << 4) | (((@as(u8, @intCast(reg)) & 0x10) >> 1));
                try result.outRawdata(allocator, &.{encoded}, "/is4 implicit", code);
            },
            0o240...0o243,
            0o250,
            => {
                try consumeBytecodeBytes(&cursor, 4);
                try emitEvexPrefixOutput(&result, allocator, ins, temp, code);
            },
            0o100...0o103,
            0o110...0o113,
            0o120...0o123,
            0o130...0o133,
            0o200...0o203,
            0o204...0o207,
            0o210...0o213,
            0o214...0o217,
            0o220...0o223,
            0o224...0o227,
            0o230...0o233,
            0o234...0o237,
            => {
                const opy = try getOperand(ins, indices.secondary);
                try emitEaEncoding(&result, allocator, ins, opy, code);
            },
            0o274...0o277 => {
                const opx = try getOperand(ins, indices.primary);
                try emitSignedByteImmediate(&result, allocator, ins, opx, code);
            },
            0o300...0o303 => {
                const rex_bytes = try emitRex(ins);
                if (rex_bytes.len != 0) {
                    try result.outRawdata(allocator, rex_bytes.slice(), "emit_rex", null);
                }
                const opx = try getOperand(ins, indices.primary);
                try emitHintNopImmediate(&result, allocator, opx, code);
            },
            0o304...0o307 => {
                const opx = try getOperand(ins, indices.primary);
                const kind = try cursor.nextRequired();
                const modifier = try cursor.nextRequired();
                try emitXorImmediate(&result, allocator, opx, kind, modifier, code);
            },
            0o340 => {
                const reserve_size = try reserveByteSize(ins, try getOperand(ins, indices.primary));
                try result.outReserve(allocator, reserve_size, code);
            },
            0o373 => {
                try emitJumpLengthByte(&result, allocator, ins.bits, code);
            },
            0o014...0o017,
            0o271...0o273,
            0o310...0o317,
            0o320...0o327,
            0o330...0o337,
            0o341,
            0o342,
            0o344...0o351,
            0o355...0o357,
            0o360,
            0o361,
            0o364...0o367,
            0o370...0o372,
            0o374...0o376,
            => {},
            else => return error.UnsupportedBytecode,
        }
    }

    return result;
}

fn absoluteOp(operand: *const match.Operand) bool {
    return operand.segment == match.no_seg and operand.wrt == match.no_seg and
        (operand.opflags & types.opflag_relative) == 0 and !operand.symbolic;
}

fn emitValueBytes(storage: *[8]u8, value: i64, size_bytes: usize) []const u8 {
    const raw: u64 = @bitCast(value);
    for (0..size_bytes) |index| {
        const shift: u6 = @intCast(index * 8);
        storage[index] = @truncate(raw >> shift);
    }
    return storage[0..size_bytes];
}

fn sext(value: i64, bits: u8) i64 {
    if (bits == 0 or bits >= 64) return value;
    const shift: u6 = @intCast(64 - bits);
    const raw: u64 = @bitCast(value);
    const shifted: i64 = @bitCast(raw << shift);
    return shifted >> shift;
}

fn overflowSigned(value: i64, size_bytes: usize) bool {
    const bits = size_bytes * 8;
    if (bits >= 64) return false;
    return sext(value, @intCast(bits)) != value;
}

fn checkedAddI64(lhs: i64, rhs: i64) GencodeError!i64 {
    const result = @addWithOverflow(lhs, rhs);
    if (result[1] != 0) return error.OutputOverflow;
    return result[0];
}

fn checkedSubI64(lhs: i64, rhs: i64) GencodeError!i64 {
    const result = @subWithOverflow(lhs, rhs);
    if (result[1] != 0) return error.OutputOverflow;
    return result[0];
}

fn checkedAddUsize(lhs: usize, rhs: usize) GencodeError!usize {
    const result = @addWithOverflow(lhs, rhs);
    if (result[1] != 0) return error.OutputOverflow;
    return result[0];
}

fn lenToI64(value: usize) GencodeError!i64 {
    if (value > @as(usize, @intCast(std.math.maxInt(i64)))) return error.OutputOverflow;
    return @intCast(value);
}

fn remainingInsnLenToI64(result: *const OwnedEncodeResult) GencodeError!i64 {
    if (result.insoffs > result.inslen) return error.OutputOverflow;
    return lenToI64(result.inslen - result.insoffs);
}

fn reserveSizeToI64(value: u64) GencodeError!i64 {
    if (value > @as(u64, @intCast(std.math.maxInt(i64)))) return error.OutputOverflow;
    return @intCast(value);
}

fn reserveSizeToUsize(value: u64) GencodeError!usize {
    if (value > @as(u64, std.math.maxInt(usize))) return error.OutputOverflow;
    return @intCast(value);
}

fn reserveByteSize(ins: *const match.Instruction, operand: *const match.Operand) GencodeError!u64 {
    if (operand.segment != match.no_seg) return error.NonConstantReserve;
    if (operand.offset < 0) return error.InvalidReserveSize;

    const count: u64 = @intCast(operand.offset);
    const unit_size = generated.reserveUnitBytes(ins.opcode);
    if (unit_size == 0) return error.InvalidReserveOpcode;
    const result = @mulWithOverflow(count, unit_size);
    if (result[1] != 0) return error.ReserveOverflow;
    return result[0];
}

fn appendPrefixWarnings(result: *OwnedEncodeResult, allocator: Allocator, diagnostics: *const PrefixDiagnostics) GencodeError!void {
    if (diagnostics.count(.invalid_prefix_for_instruction) != 0) {
        try result.warn(allocator, "invalid prefix for instruction");
    }
    if (diagnostics.count(.segment_override_ignored_64) != 0) {
        try result.warn(allocator, "segment override ignored in 64-bit mode");
    }
}

fn overflowUnsigned(value: i64, size_bytes: usize) bool {
    if (value < 0) return true;
    const bits = size_bytes * 8;
    if (bits >= 64) return false;
    const unsigned: u64 = @intCast(value);
    return unsigned > ((@as(u64, 1) << @intCast(bits)) - 1);
}

fn overflowGeneral(value: i64, size_bytes: usize) bool {
    return overflowSigned(value, size_bytes) and overflowUnsigned(value, size_bytes);
}

fn fixedAddressFlags(bits: u8, size_bytes: usize, flags: u8) u8 {
    const mode_bytes = bits >> 3;
    if (mode_bytes != 0 and size_bytes >= mode_bytes) {
        return flags & ~out_signmask;
    }
    return flags;
}

fn warnOverflowOut(result: *OwnedEncodeResult, allocator: Allocator, value: i64, size_bytes: usize, flags: u8, what: []const u8) GencodeError!void {
    if ((flags & out_nowarn) != 0) return;

    const overflow = if ((flags & out_signed) != 0)
        overflowSigned(value, size_bytes)
    else if ((flags & out_unsigned) != 0)
        overflowUnsigned(value, size_bytes)
    else
        overflowGeneral(value, size_bytes);

    if (overflow) {
        if (std.mem.eql(u8, what, "byte")) {
            try result.warn(allocator, "byte exceeds bounds");
        } else if (std.mem.eql(u8, what, "word")) {
            try result.warn(allocator, "word exceeds bounds");
        } else if (std.mem.eql(u8, what, "dword")) {
            try result.warn(allocator, "dword exceeds bounds");
        } else if (std.mem.eql(u8, what, "qword")) {
            try result.warn(allocator, "qword exceeds bounds");
        } else {
            try result.warn(allocator, "value exceeds bounds");
        }
    }
}

fn outImm(result: *OwnedEncodeResult, allocator: Allocator, operand: *const match.Operand, size_bytes: u8, flags: u8, note: ?[]const u8) GencodeError!void {
    const size_usize: usize = size_bytes;

    if (operand.segment != match.no_seg and (operand.segment & 1) != 0) {
        if (size_usize < 2) {
            try result.warn(allocator, "segment reference must be 16 bits");
        }
        try result.outFixup(allocator, "imm", size_usize, .{
            .kind = .segment,
            .size = size_bytes,
            .flags = flags,
            .toffset = operand.offset,
            .tsegment = operand.segment,
            .twrt = operand.wrt,
            .relbase = 0,
        }, note);
        return;
    }

    if ((operand.opflags & types.opflag_relative) != 0) {
        if (operand.segment == result.loc.segment and operand.wrt == match.no_seg) {
            const effective_flags = fixedAddressFlags(result.bits, size_usize, flags);
            try warnOverflowOut(result, allocator, operand.offset, size_usize, effective_flags, note orelse "value");
            var storage: [8]u8 = undefined;
            try result.outRawdata(allocator, emitValueBytes(&storage, operand.offset, size_usize), note, null);
            return;
        }

        try result.outFixup(allocator, "imm", size_usize, .{
            .kind = .relative,
            .size = size_bytes,
            .flags = flags,
            .toffset = operand.offset,
            .tsegment = operand.segment,
            .twrt = operand.wrt,
            .relbase = 0,
        }, note);
        return;
    }

    if (operand.segment == match.no_seg and operand.wrt == match.no_seg and !operand.symbolic) {
        const effective_flags = fixedAddressFlags(result.bits, size_usize, flags);
        try warnOverflowOut(result, allocator, operand.offset, size_usize, effective_flags, note orelse "value");
        var storage: [8]u8 = undefined;
        try result.outRawdata(allocator, emitValueBytes(&storage, operand.offset, size_usize), note, null);
        return;
    }

    try result.outFixup(allocator, "imm", size_usize, .{
        .kind = .absolute,
        .size = size_bytes,
        .flags = flags,
        .toffset = operand.offset,
        .tsegment = operand.segment,
        .twrt = operand.wrt,
        .relbase = 0,
    }, note);
}

fn outReladdr(result: *OwnedEncodeResult, allocator: Allocator, operand: *const match.Operand, size_bytes: u8, note: ?[]const u8) GencodeError!void {
    const size_usize: usize = size_bytes;

    if ((operand.opflags & types.opflag_relative) != 0) {
        try result.warn(allocator, "invalid use of self-relative expression");
    }

    const relbase = try checkedAddI64(result.loc.offset, try remainingInsnLenToI64(result));
    if (operand.segment == result.loc.segment and operand.wrt == match.no_seg and !operand.symbolic) {
        const value = try checkedSubI64(operand.offset, relbase);
        const effective_flags = fixedAddressFlags(result.bits, size_usize, out_signed);
        try warnOverflowOut(result, allocator, value, size_usize, effective_flags, note orelse "value");
        var storage: [8]u8 = undefined;
        try result.outRawdata(allocator, emitValueBytes(&storage, value, size_usize), note, null);
        return;
    }

    try result.outFixup(allocator, "rel", size_usize, .{
        .kind = .relative,
        .size = size_bytes,
        .flags = out_signed,
        .toffset = operand.offset,
        .tsegment = operand.segment,
        .twrt = operand.wrt,
        .relbase = relbase,
    }, note);
}

fn outFarseg(result: *OwnedEncodeResult, allocator: Allocator, operand: *const match.Operand) GencodeError!void {
    if ((operand.opflags & types.opflag_relative) != 0) {
        try result.warn(allocator, "segment references cannot be relative");
    }

    try result.outFixup(allocator, "farseg", 2, .{
        .kind = .segment,
        .size = 2,
        .flags = out_unsigned,
        .toffset = 0,
        .tsegment = operand.segment | 1,
        .twrt = operand.wrt,
        .relbase = 0,
    }, "far segment");
}

fn emitEaEncoding(result: *OwnedEncodeResult, allocator: Allocator, ins: *match.Instruction, operand: *const match.Operand, opcode: u8) GencodeError!void {
    const rex_bytes = try emitRex(ins);
    if (rex_bytes.len != 0) {
        try result.outRawdata(allocator, rex_bytes.slice(), "emit_rex", null);
    }

    var ea_storage: [2]u8 = undefined;
    ea_storage[0] = ins.ea.modrm;
    var ea_len: usize = 1;
    if (ins.ea.sib_present) {
        ea_storage[1] = ins.ea.sib;
        ea_len += 1;
    }
    try result.outRawdata(allocator, ea_storage[0..ea_len], "modrm/sib", opcode);

    switch (ins.ea.bytes) {
        0 => {},
        1 => {
            try result.outRawdata(allocator, &.{truncateU8(ins.ea.disp8)}, "disp8", opcode);
            if (!ins.ea.disp8_ok) {
                try result.warn(allocator, "displacement exceeds bounds");
            }
        },
        else => |disp_size| {
            if (ins.ea.rip) {
                try outReladdr(result, allocator, operand, disp_size, "rip-relative displacement");
            } else {
                const asize: usize = ins.addr_size >> 3;
                const flags: u8 = if (asize > disp_size) out_signed | out_nowarn else out_wrap | out_nowarn;
                try outImm(result, allocator, operand, disp_size, flags, "displacement");
                const displacement_overflow = overflowGeneral(operand.offset, asize) or
                    sext(operand.offset, ins.addr_size) != sext(operand.offset, @intCast(disp_size * 8));
                if (displacement_overflow) {
                    try result.warn(allocator, "displacement exceeds bounds");
                }
            }
        },
    }
}

fn consumeBytecodeBytes(cursor: *bytecode.BytecodeCursor, count: usize) GencodeError!void {
    for (0..count) |_| {
        try cursor.consumeRequiredByte();
    }
}

fn emitEvexPrefixOutput(result: *OwnedEncodeResult, allocator: Allocator, ins: *match.Instruction, temp: match.TemplateRef, opcode: u8) GencodeError!void {
    const vregbits = ins.vexreg | ins.veximm;
    ins.evex ^= ea.opEvexflags(&ins.oprs[0], evex_z | evex_aaa);
    ins.evex ^= (ins.rex & rex_bxr0) << 13;

    if ((ins.rex & rex_b1) != 0) {
        ins.evex ^= if ((ins.rex & rex_bv) != 0) evex_x3 else evex_b4;
    }
    if ((ins.rex & rex_x1) != 0) {
        ins.evex ^= if ((ins.rex & rex_xv) != 0) evex_v4 else evex_x4;
    }
    if ((ins.rex & rex_r1) != 0) {
        ins.evex ^= evex_r4;
    }
    if ((ins.rex & rex_w) != 0) {
        ins.evex |= evex_w;
    }

    ins.evex ^= @as(u32, vregbits & 15) << 19;
    ins.evex ^= @as(u32, vregbits & 16) << 23;

    const policy_bits = templateIflagPolicyBits(temp);
    if (ins.prefixes[match.PrefixSlot.nf.index()].raw() == match.p_nf) {
        if ((policy_bits & generated.iflag_policy_nf_e) != 0) {
            ins.evex ^= evex_nf;
        }
        if ((policy_bits & generated.iflag_policy_nf_n) != 0) {
            try result.warn(allocator, "this instruction doesn't allow {nf}");
        }
    }
    if (ins.prefixes[match.PrefixSlot.zu.index()].raw() == match.p_zu and
        (policy_bits & generated.iflag_policy_zu_e) != 0)
    {
        ins.evex ^= evex_nd;
    }

    var storage: [8]u8 = undefined;
    try result.outRawdata(allocator, emitValueBytes(&storage, @intCast(ins.evex), 4), "evex prefix", opcode);
}

fn emitVexPrefixOutput(result: *OwnedEncodeResult, allocator: Allocator, ins: *const match.Instruction, opcode: u8) GencodeError!void {
    var bytes: [3]u8 = undefined;
    const force_vex3 = ins.vex_cm != 1 or
        (ins.rex & (rex_w | rex_x | rex_b)) != 0 or
        ins.prefixes[match.PrefixSlot.rex.index()].raw() == match.p_vex3;

    if (force_vex3) {
        bytes[0] = if ((ins.vex_cm >> 6) != 0) 0x8f else 0xc4;
        bytes[1] = @intCast((@as(u32, ins.vex_cm) & 31) | (((~ins.rex) & rex_bxr0) << 5));
        bytes[2] = @intCast(((ins.rex & rex_w) << 4) |
            ((@as(u32, (~ins.vexreg) & 15)) << 3) |
            (@as(u32, ins.vex_wlp) & 0x07));
        try result.outRawdata(allocator, bytes[0..3], "vex3/xop", opcode);
        return;
    }

    bytes[0] = 0xc5;
    bytes[1] = @intCast((((~ins.rex) & rex_r) << 5) |
        ((@as(u32, (~ins.vexreg) & 15)) << 3) |
        (@as(u32, ins.vex_wlp) & 0x07));
    try result.outRawdata(allocator, bytes[0..2], "vex2", opcode);
}

fn emitSignedByteImmediate(result: *OwnedEncodeResult, allocator: Allocator, ins: *const match.Instruction, operand: *const match.Operand, opcode: u8) GencodeError!void {
    if (absoluteOp(operand)) {
        const s = ins.op_size;
        const uv: u64 = @bitCast(operand.offset);
        const um: u64 = @as(u64, 2) << @intCast(@max(@as(u8, 0), s -| 1));
        if (uv > 127 and uv < ~@as(u64, 127) and (uv < um -| 128 or uv > um -| 1)) {
            try result.warn(allocator, signedImmOverflowName(operand, s));
        }
        try result.outRawdata(allocator, &.{truncateU8(operand.offset)}, "ib,s", opcode);
        return;
    }

    try outImm(result, allocator, operand, 1, out_wrap, "ib,s");
}

fn emitHintNopImmediate(result: *OwnedEncodeResult, allocator: Allocator, operand: *const match.Operand, opcode: u8) GencodeError!void {
    if (absoluteOp(operand)) {
        if (!isHintNop(operand.offset)) {
            try result.warn(allocator, "not a valid hint-NOP opcode (0D, 18-1F)");
        }
        try result.outRawdata(allocator, &.{truncateU8(operand.offset)}, "ibn", opcode);
        return;
    }

    try outImm(result, allocator, operand, 1, out_unsigned, "ibn");
}

fn emitXorImmediate(result: *OwnedEncodeResult, allocator: Allocator, operand: *const match.Operand, kind: u8, modifier: u8, opcode: u8) GencodeError!void {
    if (!absoluteOp(operand)) return error.InvalidOperandSize;
    if (kind > 2) return error.InvalidBytecodePayload;

    const flags = kind & 3;
    try warnOverflowOut(result, allocator, operand.offset, 1, flags, "byte");
    try result.outRawdata(allocator, &.{truncateU8(operand.offset) ^ modifier}, "ib^XX", opcode);
}

fn emitJumpLengthByte(result: *OwnedEncodeResult, allocator: Allocator, bits: u8, opcode: u8) GencodeError!void {
    const encoded: u8 = if (bits == 16) 3 else 5;
    try result.outRawdata(allocator, &.{encoded}, "jlen", opcode);
}

fn isHintNop(value: i64) bool {
    return value == 0x0d or (value >= 0x18 and value <= 0x1f);
}

fn signedImmOverflowName(operand: *const match.Operand, op_size: u8) []const u8 {
    if ((operand.type_bits & match.bits8) != 0) return "signed byte exceeds bounds";
    if (op_size == 16) return "word exceeds bounds";
    if (op_size == 32) return "dword exceeds bounds";
    return "signed dword exceeds bounds";
}

fn prefixByteError(prefix: i32) PrefixEmitError {
    return switch (prefix) {
        match.p_a16, match.p_a64 => error.InvalidAddressSize,
        match.p_o64 => error.InvalidOperandSize,
        else => error.InvalidPrefixEncoding,
    };
}

fn templateHasJccHint(ins: *const match.Instruction) bool {
    const temp = ins.itemp orelse return false;
    return temp.iflagTest(if_jcc_hint);
}

fn templateIflagPolicyBits(temp: match.TemplateRef) u32 {
    return generated.iflag_policy_bits[temp.raw().iflag_index];
}

fn exprRegByEnumName(comptime enum_name: []const u8) i32 {
    inline for (generated_registers.all) |register| {
        if (std.mem.eql(u8, register.enum_name, enum_name)) {
            return register.expr_reg;
        }
    }
    @compileError("missing generated register " ++ enum_name);
}

fn getOperand(ins: *const match.Instruction, index: u8) GencodeError!*const match.Operand {
    if (index >= ins.operands) return error.MissingOperand;
    return &ins.oprs[index];
}

fn getOperandAt(ins: *const match.Instruction, index: usize) GencodeError!*const match.Operand {
    if (index >= ins.operands) return error.MissingOperand;
    return &ins.oprs[index];
}

fn truncateU8(value: anytype) u8 {
    switch (@typeInfo(@TypeOf(value))) {
        .int, .comptime_int => {
            const raw: u64 = @bitCast(@as(i64, value));
            return @truncate(raw);
        },
        else => {
            const raw: u64 = @bitCast(@as(i8, value));
            return @truncate(raw);
        },
    }
}

fn firstTemplateWithIflag(iflag: u32) ?match.TemplateRef {
    for (generated.templates, 0..) |_, index| {
        const temp = match.TemplateRef{ .index = index };
        if (temp.iflagTest(iflag)) return temp;
    }
    return null;
}

test "prefixByte mirrors x86 legacy prefix mapping" {
    const testing = std.testing;

    try testing.expectEqual(@as(i32, 0x9b), prefixByte(match.p_wait, 64));
    try testing.expectEqual(@as(i32, 0x64), prefixByte(r_fs, 64));
    try testing.expectEqual(@as(i32, 0x67), prefixByte(match.p_a16, 32));
    try testing.expectEqual(@as(i32, pfe_err), prefixByte(match.p_a16, 64));
    try testing.expectEqual(@as(i32, pfe_err), prefixByte(match.p_o64, 32));
    try testing.expectEqual(@as(i32, pfe_multi), prefixByte(match.p_vex2, 64));
}

test "emitPrefixes allows x86 override bytes for address or operand size prefixes" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o32 };
    ins.need_pfx[match.PrefixSlot.operand_size.index()] = 0x66;

    const bytes = try emitPrefixes(null, &ins);
    try testing.expectEqualSlices(u8, &.{0x66}, bytes.slice());
}

test "emitPrefixes suppresses embedded legacy prefixes under VEX or EVEX" {
    const testing = std.testing;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o16 };
    ins.rex = rex_v;
    try testing.expectEqual(@as(usize, 0), (try emitPrefixes(null, &ins)).len);

    ins.rex = rex_ev;
    try testing.expectEqual(@as(usize, 0), (try emitPrefixes(null, &ins)).len);
}

test "emitPrefixes records invalid nonoverridable prefix mismatch" {
    const testing = std.testing;
    var diagnostics: PrefixDiagnostics = .{};
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);

    ins.prefixes[match.PrefixSlot.lock.index()] = match.PrefixToken.lock;
    ins.need_pfx[match.PrefixSlot.lock.index()] = 0x66;

    const bytes = try emitPrefixes(&diagnostics, &ins);
    try testing.expectEqualSlices(u8, &.{0xf0}, bytes.slice());
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.invalid_prefix_for_instruction));
}

test "emitPrefixes records 64-bit segment override warning outside hintable jcc" {
    const testing = std.testing;
    var diagnostics: PrefixDiagnostics = .{};
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = r_es };
    const bytes = try emitPrefixes(&diagnostics, &ins);
    try testing.expectEqualSlices(u8, &.{0x26}, bytes.slice());
    try testing.expectEqual(@as(u32, 1), diagnostics.count(.segment_override_ignored_64));
}

test "emitPrefixes keeps hintable jcc cs or ds prefixes warning-free" {
    const testing = std.testing;
    const temp = firstTemplateWithIflag(if_jcc_hint) orelse return error.UnexpectedTestResult;
    var diagnostics: PrefixDiagnostics = .{};
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.itemp = temp;
    ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = r_cs };

    const bytes = try emitPrefixes(&diagnostics, &ins);
    try testing.expectEqualSlices(u8, &.{0x2e}, bytes.slice());
    try testing.expectEqual(@as(u32, 0), diagnostics.count(.segment_override_ignored_64));
}

test "emitPrefixes returns explicit errors for illegal address or operand size prefixes" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a16 };
    try testing.expectError(error.InvalidAddressSize, emitPrefixes(null, &ins));

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.prefixes[match.PrefixSlot.address_size.index()] = .{ .value = match.p_a64 };
    try testing.expectError(error.InvalidAddressSize, emitPrefixes(null, &ins));

    ins.prefixes[match.PrefixSlot.address_size.index()] = match.PrefixToken.none;
    ins.prefixes[match.PrefixSlot.operand_size.index()] = .{ .value = match.p_o64 };
    try testing.expectError(error.InvalidOperandSize, emitPrefixes(null, &ins));
}

test "emitRex mirrors x86 REX REX2 and opmap byte emission" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.rex = rex_p | 0x09;
    var bytes = try emitRex(&ins);
    try testing.expectEqualSlices(u8, &.{0x49}, bytes.slice());
    try testing.expect(ins.rex_done);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_2 | rex_w | 0x0003 | 0x2000;
    ins.vex_cm = 1;
    bytes = try emitRex(&ins);
    try testing.expectEqualSlices(u8, &.{ 0xd5, 0xab }, bytes.slice());

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.vex_cm = 3;
    bytes = try emitRex(&ins);
    try testing.expectEqualSlices(u8, &.{ 0x0f, 0x3a }, bytes.slice());
}

test "emitRex respects rex_done and VEX or EVEX handled elsewhere" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);

    ins.rex_done = true;
    try testing.expectEqual(@as(usize, 0), (try emitRex(&ins)).len);

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_v;
    try testing.expectEqual(@as(usize, 0), (try emitRex(&ins)).len);
    try testing.expect(ins.rex_done);
}

test "emitRex preserves x86 lock-as-rex-r branch and rejects inconsistent state" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);

    ins.rex = rex_l | rex_r;
    try testing.expectEqualSlices(u8, &.{0xf0}, (try emitRex(&ins)).slice());

    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.rex = rex_r;
    try testing.expectError(error.InvalidPrefixEncoding, emitRex(&ins));
}

test "gencode emits x86 literal opcode template bytes without root shortcut logic" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));
    const inslen: usize = @intCast(try size.calcSize(&ins));

    var encoded = try gencode(testing.allocator, &ins, inslen);
    defer encoded.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), encoded.units.items.len);
    try testing.expectEqualSlices(u8, &.{0x90}, encoded.units.items[0].bytes);
    try testing.expectEqual(@as(usize, 1), encoded.insoffs);
}

test "gencode emits x86 plus-r opcode with source-backed REX staging" {
    const testing = std.testing;
    const r8 = registerByName("r8") orelse return error.UnexpectedTestResult;
    var ins = match.Instruction.init(match.opcodeByMnemonic("push") orelse return error.UnexpectedTestResult, 64);
    ins.operands = 1;
    ins.oprs[0] = .{
        .kind = .register,
        .type_bits = @intCast(r8.flags),
        .basereg = r8.expr_reg,
    };

    const inslen: usize = switch (try size.insnSize(SizeTestContext{}, .{}, &ins)) {
        .size => |value| @intCast(value),
        .no_match => return error.UnexpectedTestResult,
    };

    var encoded = try gencode(testing.allocator, &ins, inslen);
    defer encoded.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 2), encoded.units.items.len);
    try testing.expectEqualSlices(u8, &.{0x41}, encoded.units.items[0].bytes);
    try testing.expectEqualSlices(u8, &.{0x50}, encoded.units.items[1].bytes);
    try testing.expectEqual(@as(usize, 2), encoded.insoffs);
}

test "gencode preserves emitPrefixes warning diagnostics" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    try testing.expectEqual(match.MatchResult.ok_good, match.findMatch(SizeTestContext{}, &ins));
    ins.prefixes[match.PrefixSlot.segment.index()] = .{ .value = r_es };

    var encoded = try gencode(testing.allocator, &ins, 2);
    defer encoded.deinit(testing.allocator);

    try testing.expectEqual(@as(usize, 1), encoded.warnings.items.len);
    try testing.expectEqualStrings("segment override ignored in 64-bit mode", encoded.warnings.items[0]);
    try testing.expectEqualSlices(u8, &.{0x26}, encoded.units.items[0].bytes);
    try testing.expectEqualSlices(u8, &.{0x90}, encoded.units.items[1].bytes);
}

test "outImm emits raw bytes for absolute immediate and fixup for symbolic immediate" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 64, .inslen = 0 };
    defer result.deinit(testing.allocator);

    const absolute: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 0x1234,
    };
    try outImm(&result, testing.allocator, &absolute, 2, out_wrap, "iw");
    try testing.expectEqual(@as(usize, 1), result.units.items.len);
    try testing.expectEqualSlices(u8, &.{ 0x34, 0x12 }, result.units.items[0].bytes);

    const symbolic: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .segment = 4,
        .wrt = 7,
        .offset = 99,
        .symbolic = true,
    };
    try outImm(&result, testing.allocator, &symbolic, 4, out_wrap, "id");
    try testing.expectEqual(FixupKind.absolute, result.units.items[1].fixup.?.kind);
    try testing.expectEqual(@as(i64, 99), result.units.items[1].fixup.?.toffset);
}

test "outReladdr emits raw local delta and fixup for external target" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{
        .loc = .{ .segment = 3, .offset = 10 },
        .bits = 64,
        .inslen = 5,
        .insoffs = 1,
    };
    defer result.deinit(testing.allocator);

    const local: match.Operand = .{
        .kind = .immediate,
        .segment = 3,
        .wrt = match.no_seg,
        .offset = 20,
    };
    try outReladdr(&result, testing.allocator, &local, 1, "rel8");
    try testing.expectEqualSlices(u8, &.{0x06}, result.units.items[0].bytes);

    const external: match.Operand = .{
        .kind = .immediate,
        .segment = 9,
        .wrt = 1,
        .offset = 0x44,
    };
    try outReladdr(&result, testing.allocator, &external, 4, "rel32");
    try testing.expectEqual(FixupKind.relative, result.units.items[1].fixup.?.kind);
    try testing.expectEqual(@as(i64, 0x44), result.units.items[1].fixup.?.toffset);
}

test "outReladdr preserves symbolic local target as relative fixup" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{
        .loc = .{ .segment = 3, .offset = 10 },
        .bits = 64,
        .inslen = 6,
        .insoffs = 2,
    };
    defer result.deinit(testing.allocator);

    const symbolic: match.Operand = .{
        .kind = .immediate,
        .segment = 3,
        .wrt = match.no_seg,
        .offset = 0,
        .symbolic = true,
    };
    try outReladdr(&result, testing.allocator, &symbolic, 4, "rel32");

    try testing.expectEqual(@as(usize, 1), result.units.items.len);
    const fixup = result.units.items[0].fixup orelse return error.UnexpectedTestResult;
    try testing.expectEqual(FixupKind.relative, fixup.kind);
    try testing.expectEqual(@as(u8, 4), fixup.size);
}

test "outReladdr reports checked output-position overflow" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{
        .loc = .{ .segment = 3, .offset = std.math.maxInt(i64) },
        .bits = 64,
        .inslen = 1,
        .insoffs = 0,
    };
    defer result.deinit(testing.allocator);

    const local: match.Operand = .{
        .kind = .immediate,
        .segment = 3,
        .wrt = match.no_seg,
        .offset = 20,
    };
    try testing.expectError(error.OutputOverflow, outReladdr(&result, testing.allocator, &local, 1, "rel8"));
}

test "sext avoids signed left-shift overflow" {
    const testing = std.testing;

    try testing.expectEqual(@as(i64, -128), sext(0x80, 8));
    try testing.expectEqual(@as(i64, -1), sext(std.math.maxInt(i64), 1));
}

test "outFarseg emits segment fixup and warning surface" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 64, .inslen = 0 };
    defer result.deinit(testing.allocator);

    const operand: match.Operand = .{
        .kind = .immediate,
        .segment = 6,
        .wrt = 2,
        .opflags = types.opflag_relative,
    };
    try outFarseg(&result, testing.allocator, &operand);
    try testing.expectEqual(FixupKind.segment, result.units.items[0].fixup.?.kind);
    try testing.expectEqual(@as(i32, 7), result.units.items[0].fixup.?.tsegment);
    try testing.expectEqual(@as(usize, 1), result.warnings.items.len);
    try testing.expectEqualStrings("segment references cannot be relative", result.warnings.items[0]);
}

test "emitEaEncoding emits modrm bytes and displacement state" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{
        .loc = .{},
        .bits = 32,
        .inslen = 2,
    };
    defer result.deinit(testing.allocator);

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.ea.modrm = 0x03;
    ins.ea.bytes = 0;
    const operand: match.Operand = .{
        .kind = .memory,
        .type_bits = match.memory | match.bits8,
        .basereg = match.r_none,
    };
    try emitEaEncoding(&result, testing.allocator, &ins, &operand, 0o100);
    try testing.expectEqual(@as(usize, 1), result.units.items.len);
    try testing.expectEqualSlices(u8, &.{0x03}, result.units.items[0].bytes);

    result.deinit(testing.allocator);
    result = .{ .loc = .{}, .bits = 64, .inslen = 6 };
    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.ea.modrm = 0x05;
    ins.ea.bytes = 4;
    ins.ea.rip = true;
    const rip_operand: match.Operand = .{
        .kind = .memory,
        .segment = 2,
        .wrt = match.no_seg,
        .offset = 0x30,
    };
    try emitEaEncoding(&result, testing.allocator, &ins, &rip_operand, 0o100);
    try testing.expectEqual(@as(usize, 2), result.units.items.len);
    try testing.expectEqualSlices(u8, &.{0x05}, result.units.items[0].bytes);
    try testing.expectEqual(FixupKind.relative, result.units.items[1].fixup.?.kind);
}

test "emitSignedByteImmediate warns and writes low byte for out-of-range absolute input" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 32, .inslen = 0 };
    defer result.deinit(testing.allocator);
    const operand: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate | match.bits32,
        .offset = 200,
    };
    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 32);
    ins.op_size = 32;

    try emitSignedByteImmediate(&result, testing.allocator, &ins, &operand, 0o274);
    try testing.expectEqualSlices(u8, &.{0xC8}, result.units.items[0].bytes);
    try testing.expectEqualStrings("dword exceeds bounds", result.warnings.items[0]);
}

test "emitHintNopImmediate warns on invalid opcode and raw-encodes absolute byte" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 32, .inslen = 0 };
    defer result.deinit(testing.allocator);
    const operand: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 0x20,
    };

    try emitHintNopImmediate(&result, testing.allocator, &operand, 0o300);
    try testing.expectEqualSlices(u8, &.{0x20}, result.units.items[0].bytes);
    try testing.expectEqualStrings("not a valid hint-NOP opcode (0D, 18-1F)", result.warnings.items[0]);
}

test "emitXorImmediate requires absolute operand and applies xor modifier" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 32, .inslen = 0 };
    defer result.deinit(testing.allocator);
    const absolute: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 0x5a,
    };
    try emitXorImmediate(&result, testing.allocator, &absolute, 1, 0xff, 0o304);
    try testing.expectEqualSlices(u8, &.{0xA5}, result.units.items[0].bytes);

    const symbolic: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .segment = 3,
    };
    try testing.expectError(error.InvalidOperandSize, emitXorImmediate(&result, testing.allocator, &symbolic, 1, 0, 0o304));
    try testing.expectError(error.InvalidBytecodePayload, emitXorImmediate(&result, testing.allocator, &absolute, 3, 0, 0o304));
}

test "gencode emits x86 reserve tail bytecode" {
    const testing = std.testing;
    const reserve_temp = firstTemplateWithBytecodeLead(0o340) orelse return error.UnexpectedTestResult;

    var reserve_ins = match.Instruction.init(match.opcodeByMnemonic("resw") orelse return error.UnexpectedTestResult, 64);
    reserve_ins.itemp = reserve_temp;
    reserve_ins.operands = 1;
    reserve_ins.oprs[0] = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 4,
    };

    var reserve_encoded = try gencode(testing.allocator, &reserve_ins, 8);
    defer reserve_encoded.deinit(testing.allocator);
    try testing.expectEqual(@as(usize, 1), reserve_encoded.units.items.len);
    try testing.expectEqualStrings("reserve", reserve_encoded.units.items[0].kind);
    try testing.expectEqual(@as(u64, 8), reserve_encoded.units.items[0].reserve_len);
    try testing.expectEqual(@as(i64, 8), reserve_encoded.loc.offset);
    try testing.expectEqual(@as(usize, 8), reserve_encoded.insoffs);
}

test "emitJumpLengthByte mirrors x86 0373 output" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 16, .inslen = 1 };
    defer result.deinit(testing.allocator);

    try emitJumpLengthByte(&result, testing.allocator, 16, 0o373);
    try testing.expectEqualSlices(u8, &.{3}, result.units.items[0].bytes);

    result.deinit(testing.allocator);
    result = .{ .loc = .{}, .bits = 64, .inslen = 1 };
    try emitJumpLengthByte(&result, testing.allocator, 64, 0o373);
    try testing.expectEqualSlices(u8, &.{5}, result.units.items[0].bytes);

    result.loc.offset = std.math.maxInt(i64);
    try testing.expectError(error.OutputOverflow, emitJumpLengthByte(&result, testing.allocator, 64, 0o373));
}

test "reserveByteSize preserves recoverable error surface and checked math" {
    const testing = std.testing;
    var ins = match.Instruction.init(match.opcodeByMnemonic("resq") orelse return error.UnexpectedTestResult, 64);
    const absolute: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = 2,
    };
    try testing.expectEqual(@as(u64, 16), try reserveByteSize(&ins, &absolute));

    var non_constant = absolute;
    non_constant.segment = 7;
    try testing.expectError(error.NonConstantReserve, reserveByteSize(&ins, &non_constant));

    var negative = absolute;
    negative.offset = -1;
    try testing.expectError(error.InvalidReserveSize, reserveByteSize(&ins, &negative));

    ins.opcode = match.opcodeByMnemonic("resz") orelse return error.UnexpectedTestResult;
    const oversized: match.Operand = .{
        .kind = .immediate,
        .type_bits = match.immediate,
        .offset = std.math.maxInt(i64),
    };
    try testing.expectError(error.ReserveOverflow, reserveByteSize(&ins, &oversized));

    ins.opcode = match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult;
    try testing.expectError(error.InvalidReserveOpcode, reserveByteSize(&ins, &absolute));
}

test "emitVexPrefixOutput selects x86 two-byte and three-byte VEX forms" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 64, .inslen = 0 };
    defer result.deinit(testing.allocator);

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.vex_cm = 1;
    ins.vexreg = 0;
    ins.vex_wlp = 1;
    try emitVexPrefixOutput(&result, testing.allocator, &ins, 0o260);
    try testing.expectEqualSlices(u8, &.{ 0xc5, 0xf9 }, result.units.items[0].bytes);

    result.deinit(testing.allocator);
    result = .{ .loc = .{}, .bits = 64, .inslen = 0 };
    ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.vex_cm = 3;
    ins.rex = rex_w | rex_x;
    ins.vexreg = 2;
    ins.vex_wlp = 2;
    try emitVexPrefixOutput(&result, testing.allocator, &ins, 0o260);
    try testing.expectEqualSlices(u8, &.{ 0xc4, 0xa3, 0xea }, result.units.items[0].bytes);
}

test "emitEvexPrefixOutput mirrors x86 EVEX bit assembly and NF/ZU policy" {
    const testing = std.testing;
    var result: OwnedEncodeResult = .{ .loc = .{}, .bits = 64, .inslen = 0 };
    defer result.deinit(testing.allocator);
    const temp = firstTemplateWithPolicy(generated.iflag_policy_nf_e | generated.iflag_policy_zu_e) orelse return error.UnexpectedTestResult;

    var ins = match.Instruction.init(match.opcodeByMnemonic("nop") orelse return error.UnexpectedTestResult, 64);
    ins.itemp = temp;
    ins.operands = 1;
    ins.evex = 0x62;
    ins.rex = rex_b | rex_w;
    ins.vexreg = 1;
    ins.oprs[0].decoflags = 0x10 | 3;
    ins.prefixes[match.PrefixSlot.nf.index()] = match.PrefixToken.nf;
    ins.prefixes[match.PrefixSlot.zu.index()] = match.PrefixToken.zu;

    try emitEvexPrefixOutput(&result, testing.allocator, &ins, temp, 0o240);
    try testing.expectEqualSlices(u8, &.{ 0x62, 0x20, 0x88, 0x97 }, result.units.items[0].bytes);
}

const SizeTestContext = struct {
    pub fn cpuIflagField(context: @This(), field_index: usize) u32 {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return types.defaultCpuIflagField(field_index);
    }

    pub fn calcSizeSpeculative(context: @This(), ins: *const match.Instruction, temp: match.TemplateRef) match.SpeculativeSize {
        if (@sizeOf(@TypeOf(context)) > 0) {}
        return size.calcSizeSpeculative(ins, temp);
    }
};

fn registerByName(name: []const u8) ?@import("tables.zig").RegisterInfo {
    const registers = @import("generated_registers.zig");
    for (registers.all) |reg| {
        if (std.ascii.eqlIgnoreCase(reg.name, name)) return reg;
    }
    return null;
}

fn firstTemplateWithBytecodeLead(lead: u8) ?match.TemplateRef {
    for (generated.templates, 0..) |_, index| {
        const temp = match.TemplateRef{ .index = index };
        const code = generated.bytecodeForTemplate(temp.raw()) orelse continue;
        if (code.len != 0 and code[0] == lead) return temp;
    }
    return null;
}

fn firstTemplateWithPolicy(required_bits: u32) ?match.TemplateRef {
    for (generated.templates, 0..) |template, index| {
        if ((generated.iflag_policy_bits[template.iflag_index] & required_bits) == required_bits) {
            return .{ .index = index };
        }
    }
    return null;
}
