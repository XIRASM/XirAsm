# A64 DSL Encoding Tests

These tests validate `arm/a64.inc` and `arm/a64-macros.inc` using the existing
release executable. Python maintains the generation and verification pipeline;
the assembler consumes shipped includes without Python or architecture data.

```text
python tools/arm64/generate_a64.py --check
python tests/isa/arm/test_a64_generation.py
python tests/isa/arm/check_a64_generated.py --sync --clang <clang> --objcopy <llvm-objcopy>
python tests/isa/arm/check_a64_b3_edges.py --clang <clang> --objcopy <llvm-objcopy>
python tests/isa/arm/check_a64_b4_edges.py --clang <clang> --objcopy <llvm-objcopy>
python tests/isa/arm/check_a64_extension_edges.py --clang <clang> --objcopy <llvm-objcopy>
python tests/isa/arm/test_official_inventory.py
```

`--xirasm <release-executable>` selects a compiler; the default is
`zig-out/bin/xirasm.exe`. `--sync` installs and verifies only new A64 includes
beside that executable. DSL changes do not require a compiler rebuild.

The differential runner compares direct API and natural macro bytes against
Clang. `--batch B1` through `B4` or `E1` through `E4` selects a batch; repeat `--mnemonic` to select
specific owners. `--phase rejections` checks only rejections and captures, and
does not claim positive coverage. `--phase smoke` checks one case per form.
`--output <new-directory>` retains evidence.

The B3 edge runner independently checks labels, deferred captures, single
evaluation, memory offsets, register lists and invalid operand shapes. It
records the exact official-source exceptions where Clang accepts an operand
that XIRASM rejects. Generation regressions check structural rules; inventory
tests exercise the pinned source reader separately.

B1-B4 cover 1144 source records and 3592 forms. E1-E4 add 599 source records
and 766 forms, for 1743 records and 4358 forms in total. The extension edge
runner checks fixed crypto, LSE register-pair, FP16, grouped-lane, PAC/MTE and
capture cases. The B4 edge runner independently
checks scalar aliases, register roles, system access, branches and page targets.
Source feature metadata and
Clang byte comparisons do not establish execution on a particular A64 device.

See `tools/arm64/README.md` for the pinned-source production workflow.
