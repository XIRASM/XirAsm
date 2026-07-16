# XIRASM

[简体中文](README.zh-CN.md) | [Website](https://xirasm-site.pages.dev/) | [What's New](https://xirasm-site.pages.dev/#updates)

**Assembly syntax for instructions. A real compile-time language for everything
around them.**

XIRASM is built for assembly programmers who want direct control without being
trapped in an old directive dialect or fragile text-macro tricks.

Write instructions normally. When the source needs calculation, generation,
reuse, or transformation, use typed values, functions, control flow,
collections, modules, file data, and token matching.

The result is one assembler language for handwritten instructions, generated
code, binary layouts, and native output formats across x86, RISC-V, and SPIR-V.

## The Difference

- **Normal ISA text stays normal.** Write labels and processor instructions
  directly; no function-call wrapper is required around assembly.
- **Compile-time programming replaces text-macro puzzles.** Typed values,
  functions, lexical scope, `if`/`else if`, `while`, `for`, `break`, and
  `continue` express generation logic directly.
- **Data and formats use the same language.** Structs, unions, float and integer
  emission, reserve operations, modules, files, JSON, TOML, lists, maps, and
  token matching compose without a second directive dialect.
- **The frontend owns assembly semantics.** Source spans, symbols, fragments,
  fixups, layout, relaxation, diagnostics, and output remain explicit; ISA
  encoders are narrow leaf backends.
- **One project model covers multiple instruction sets.** The same compile-time
  language drives x86, x86-64, RV32, RV64, and SPIR-V sources.

## See It

Instructions remain assembly. Repetitive work becomes normal compile-time
code:

```asm
x86.use64();

fn emit_square_table(count: u8) {
    for value in range(0, count) {
        dd(value * value);
    }
}

const answer: u32 = 40 + 2;

entry:
    mov eax, answer
    ret

table:
emit_square_table(4);
```

The function and loop execute only while assembling. The output contains the
machine code and generated table, not a runtime interpreter.

The language also provides:

- typed constants and variables;
- reusable functions and lexical scope;
- lists, maps, strings, and byte sequences;
- structs, unions, packing, alignment, and reserved data;
- modules and imports;
- JSON, TOML, and file-driven generation;
- token matching for compact source DSLs;
- assertions with source-positioned diagnostics.

## Quick Start

Build with Zig 0.17:

```text
zig build -Doptimize=ReleaseSafe
```

Create `hello.asm`:

```asm
x86.use64();

entry:
    mov eax, 42
    ret
```

Assemble a flat binary from the repository build:

```text
./zig-out/bin/xirasm hello.asm --target x86-64 -o hello.bin
```

On Windows, run `zig-out\bin\xirasm.exe`. An installed `xirasm` can be used
directly from `PATH`.

Create a ready-to-build native project:

```text
xirasm init hello-win --isa x86-64 --os windows --abi msvc
xirasm init hello-linux --isa x86-64 --os linux --abi sysv
```

Each generated project contains `xirasm.toml`; run `xirasm build` inside that
project to assemble its configured source and output.

CLI subcommands come before their options. For example, use
`xirasm build --timings`, not `xirasm --timings build`.

## Supported Targets

| CLI target | Instruction set |
| --- | --- |
| `x86-64`, `x64`, `x86_64` | 64-bit x86 |
| `x86`, `x86-32` | 32-bit x86 |
| `rv64`, `riscv64` | 64-bit RISC-V |
| `rv32`, `riscv32` | 32-bit RISC-V |
| `spv`, `spirv` | SPIR-V 1.6 module |

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
The [Format Tutorial](document/format-tutorial.md) covers complete PE, COFF,
and ELF workflows.

## Editor Support

The standalone [XIRASM VS Code extension](https://codeberg.org/kukuyun/xirasm-vscode)
provides highlighting, completion, navigation, and compiler-backed diagnostics.

## Documentation

- [Language Guide](document/language.md) - learn the compile-time language and
  assembler model.
- [Format Tutorial](document/format-tutorial.md) - choose PE, COFF, and ELF
  templates and build files with the user-facing facade APIs.
- [Advanced Format Construction Guide](document/advanced-formats.md) - use
  direct format helpers when manual control is required.
- [Language API Reference](document/api-reference.md) - look up syntax and
  built-in APIs.

## Status

Current version: **0.2.15**

XIRASM is pre-1.0 software: the assembler, language API, format library, CLI,
and editor integration are usable now, while public contracts may still be
refined before 1.0.

## License

Apache-2.0.
