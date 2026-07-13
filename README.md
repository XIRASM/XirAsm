# XIRASM

[简体中文](README.zh-CN.md)

**A modern assembler for x86, x86-64, RV32, and RV64, with a real
compile-time programming language.**

XIRASM is built for assembly programmers who want direct control without being
trapped in an old directive dialect or fragile text-macro tricks.

Write instructions normally. When the source needs calculation, generation,
reuse, or transformation, use typed values, functions, control flow,
collections, modules, file data, and token matching.

One assembler. One language. Multiple instruction sets and native output
formats.

## Why XIRASM

- **x86 and RISC-V in one assembler.** Use the same language and project model
  for x86, x86-64, RV32, and RV64.
- **Compile-time programming instead of macro puzzles.** Use functions,
  expressions, `if`, `while`, and `for` to express intent directly.
- **Code and data generation are ordinary language features.** Generate
  instruction families, tables, declarations, constants, and binary data
  without building a second source generator.
- **Reusable libraries and small DSLs.** Modules, lists, maps, strings, bytes,
  JSON, TOML, file APIs, and token matching are available during assembly.
- **Useful output from the same tool.** Build flat binaries, Windows
  executables and DLLs, COFF objects, Linux executables and PIEs, ELF objects,
  and ELF shared libraries.

## Assembly with a Real Language

Instructions remain assembly. Repetitive work becomes normal compile-time
code:

```asm
x86.use64();

fn emit_square_table(count: u8) {
    for value in range(0, count) {
        dd(value * value);
    }
}

const answer: u32 = 40 + 2

entry:
    mov eax, answer
    ret

table:
emit_square_table(4);
```

The function and loop run while assembling. The output contains only the
machine code and generated table.

The same language also provides:

- typed constants and variables;
- reusable functions and lexical scope;
- lists, maps, strings, and byte sequences;
- structs, unions, packing, alignment, and reserved data;
- modules and imports;
- JSON, TOML, and file-driven generation;
- token matching for compact source DSLs;
- assertions and diagnostics.

## Supported Targets

| CLI target | Instruction set |
| --- | --- |
| `x86-64`, `x64`, `x86_64` | 64-bit x86 |
| `x86`, `x86-32` | 32-bit x86 |
| `rv64`, `riscv64` | 64-bit RISC-V |
| `rv32`, `riscv32` | 32-bit RISC-V |

The compile-time language and project structure stay consistent across targets.

## Output Formats

XIRASM can directly produce:

- flat and application-specific binaries;
- PE32 and PE64 Windows executables and DLLs;
- COFF32 and COFF64 object files;
- ELF32 and ELF64 executables;
- ELF64 position-independent executables;
- ELF32 and ELF64 object files;
- ELF64 shared libraries.

Executable-format projects use the ordinary format library:

```asm
import("format/format.inc");
```

The CLI can also create ready-to-build Windows and Linux starter projects.
Detailed PE, COFF, and ELF examples belong in the
[Executable Formats Guide](document/formats.md).

## Quick Start

Build XIRASM with Zig 0.17:

```powershell
zig build -Doptimize=ReleaseFast
```

Assemble a flat binary:

```powershell
xirasm hello.asm --target x86-64 -o hello.bin
```

Create and build a Windows executable project:

```powershell
xirasm init hello-win --isa x86-64 --os windows --abi msvc
cd hello-win
xirasm build
```

Create and build a Linux executable project:

```powershell
xirasm init hello-linux --isa x86-64 --os linux --abi sysv
cd hello-linux
xirasm build
```

## Editor Support

The standalone [XIRASM VS Code extension](https://codeberg.org/kukuyun/xirasm-vscode)
provides highlighting, completion, navigation, and compiler-backed diagnostics.

## Documentation

- [Language Guide](document/language.md) - learn the compile-time language and
  assembler model.
- [Executable Formats Guide](document/formats.md) - build PE, COFF, and ELF
  programs with the ordinary format API.
- [Advanced Format Construction Guide](document/advanced-formats.md) - use
  direct format helpers when manual control is required.
- [Language API Reference](document/api-reference.md) - look up syntax and
  built-in APIs.

## Status

Current version: **0.2.6**

XIRASM is pre-1.0 software. Public APIs may still be refined before the stable
release.

## License

Apache-2.0.
