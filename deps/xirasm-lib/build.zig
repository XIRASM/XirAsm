const std = @import("std");

pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    const exclude_spirv = b.option(bool, "exclude-spirv", "Exclude SPIR-V encoder") orelse false;
    const exclude_riscv = b.option(bool, "exclude-riscv", "Exclude RISC-V encoder") orelse false;

    const build_opts = b.addOptions();
    build_opts.addOption(bool, "exclude_spirv", exclude_spirv);
    build_opts.addOption(bool, "exclude_riscv", exclude_riscv);

    const backend_mod = b.addModule("xirasm_backend", .{
        .root_source_file = b.path("src/xirasm_backend.zig"),
        .target = target,
        .optimize = optimize,
    });
    backend_mod.addOptions("build_opts", build_opts);

    const static_lib = b.addLibrary(.{
        .linkage = .static,
        .name = "xirasm_backend",
        .root_module = backend_mod,
    });
    b.installArtifact(static_lib);

    const test_step = b.step("test", "Run ISA backend tests");

    const isa_coverage_mod = b.createModule(.{
        .root_source_file = b.path("tests/isa_coverage.zig"),
        .target = b.graph.host,
        .optimize = optimize,
    });
    isa_coverage_mod.addImport("xirasm_backend", backend_mod);
    const isa_coverage_test = b.addTest(.{ .root_module = isa_coverage_mod });
    test_step.dependOn(&b.addRunArtifact(isa_coverage_test).step);

    if (!exclude_riscv) {
        const riscv_source_parser_mod = b.createModule(.{
            .root_source_file = b.path("tests/isa/riscv/source_text_parser.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        });
        riscv_source_parser_mod.addImport("xirasm_backend", backend_mod);
        const riscv_source_parser_test = b.addTest(.{ .root_module = riscv_source_parser_mod });
        test_step.dependOn(&b.addRunArtifact(riscv_source_parser_test).step);

        const riscv_source_fixtures_mod = b.createModule(.{
            .root_source_file = b.path("tests/isa/riscv/source_text_fixtures.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        });
        riscv_source_fixtures_mod.addImport("xirasm_backend", backend_mod);
        const riscv_source_fixtures_test = b.addTest(.{ .root_module = riscv_source_fixtures_mod });
        test_step.dependOn(&b.addRunArtifact(riscv_source_fixtures_test).step);
    }

    if (!exclude_spirv) {
        const spirv_encoder_mod = b.createModule(.{
            .root_source_file = b.path("tests/spirv_encoder.zig"),
            .target = b.graph.host,
            .optimize = optimize,
        });
        spirv_encoder_mod.addImport("xirasm_backend", backend_mod);
        const spirv_encoder_test = b.addTest(.{ .root_module = spirv_encoder_mod });
        test_step.dependOn(&b.addRunArtifact(spirv_encoder_test).step);
    }
}
