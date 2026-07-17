# XIRASM

[简体中文](README.zh-CN.md) | [Website](https://xirasm-site.pages.dev/) | [What's New](https://xirasm-site.pages.dev/#updates)

**One modern assembler for x86, RISC-V, and SPIR-V. Write real assembly, emit
usable binaries, and make the build programmable when you need more.**

XIRASM assembles natural ISA text and directly produces flat binaries, Windows
PE/COFF, Linux ELF, and complete SPIR-V modules. Start with ordinary assembly.
Reach for its typed compile-time language only when a project needs generated
code, reusable format logic, or precise binary layout.

- **Three ISA families:** x86 in 16/32/64-bit modes, RV32/RV64, and SPIR-V 1.6.
- **Useful output, not an intermediate experiment:** executables, DLLs, shared
  libraries, object files, flat binaries, and SPIR-V modules.
- **Modern metaprogramming:** typed values, functions, collections, modules,
  structured control flow, and source-located diagnostics instead of a fragile
  text-macro layer.
- **A short path to native output:** project templates provide ready-to-build
  Windows and Linux programs; format facades handle ordinary PE, COFF, and ELF
  work without requiring users to construct every header by hand.

## Build a Native Program

Build XIRASM with Zig 0.17:

```text
zig build -Doptimize=ReleaseSafe
```

Put the resulting `xirasm` executable on `PATH`, then create and build a native
project:

```text
xirasm init hello --isa x86-64 --os windows --abi msvc
cd hello
xirasm build
```

For Linux, use `--os linux --abi sysv`. The generated project contains its
source and `xirasm.toml`, so the next build is just `xirasm build`.

CLI subcommands precede their options: use `xirasm build --timings`, not
`xirasm --timings build`.

## Assembly Stays Assembly

Labels and processor instructions use their normal text form. Compile-time code
appears only where it earns its place:

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

The function and loop run while assembling. The output contains only the
machine code and generated data, with no runtime interpreter and no instruction
wrapper syntax.

For a minimal flat binary, a source file can be as small as:

```asm
x86.use64();

entry:
    mov eax, 42
    ret
```

```text
xirasm hello.asm --target x86-64 -o hello.bin
```

## One Tool, Multiple Targets

| CLI target | Output model |
| --- | --- |
| `x86-64`, `x64`, `x86_64` | 64-bit x86 instructions and native/flat outputs |
| `x86`, `x86-32` | 32-bit x86 instructions and native/flat outputs |
| `rv64`, `riscv64` | RV64 instructions |
| `rv32`, `riscv32` | RV32 instructions |
| `spv`, `spirv` | Complete SPIR-V 1.6 modules |

The same project model and compile-time language apply across targets. You do
not have to learn one macro system for x86 and another generation language for
RISC-V or SPIR-V.

## Output Formats

XIRASM can directly produce:

| Platform or use | Formats |
| --- | --- |
| Windows | PE32/PE64 executables and DLLs; COFF32/COFF64 objects |
| Linux | ELF32/ELF64 executables; ELF64 PIE and shared libraries; ELF32/ELF64 objects |
| Bare metal and tooling | Flat and application-specific binaries |
| GPU and IR tooling | Complete SPIR-V 1.6 modules |

Normal PE, COFF, and ELF projects use the format library's high-level facades:

```asm
import("format/format.inc");
```

When a loader, file format, or research tool needs an unusual layout, the same
language also exposes regions, labels, alignment, finalizers, and direct format
helpers. The common path stays short; low-level control remains available.

## More Than a Macro Assembler

XIRASM's compile-time language is designed for assembly projects that outgrow
copy-and-paste and textual substitution:

- typed constants, mutable bindings, functions, and lexical scope;
- `if`/`else if`, `while`, `for`, `break`, and `continue`;
- strings, byte sequences, mutable lists and maps;
- structs, unions, packing, alignment, and reserve operations;
- modules, imports, JSON, TOML, and file-driven generation;
- token matching for compact domain-specific source forms;
- assertions and diagnostics tied to the original source location.

This makes XIRASM useful for systems programs, executable-format work,
embedded binaries, code generators, and instruction-level experiments without
turning ordinary instruction text into a programming-language API.

## Validation

The regression suite checks final encoded bytes and boundary behavior, not only
whether source text parses. It includes x86 layout and fixup cases, RISC-V byte
comparisons with LLVM tooling, SPIR-V assembly/disassembly and validation, and
structural, linker, loader, and native-runtime checks for supported binary
formats.

## Editor and Documentation

The standalone [XIRASM VS Code extension](https://github.com/XIRASM/xir-vscode)
provides highlighting, completion, navigation, and compiler-backed diagnostics.

- [Language Guide](document/language.md) - learn the assembly and compile-time
  language model.
- [Format Tutorial](document/format-tutorial.md) - build PE, COFF, and ELF files
  with user-facing facade APIs.
- [Language API Reference](document/api-reference.md) - look up syntax and
  built-in APIs.
- [Advanced Format Construction](document/advanced-formats.md) - take direct
  control of uncommon binary layouts.

## Status

Current version: **0.2.16**

XIRASM is pre-1.0 software. The assembler, language APIs, format library, CLI,
and editor support are usable now, while public contracts may still be refined
before 1.0.

## License

Apache-2.0.
