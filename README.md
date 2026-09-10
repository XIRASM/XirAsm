# XIRASM

[简体中文](README.zh-CN.md) | [Website](https://xirasm-site.pages.dev/) | [What's New](https://xirasm-site.pages.dev/#updates)

**One modern assembler for x86, AArch64, RISC-V, and SPIR-V. Write real
assembly, emit usable binaries for Windows, Linux, macOS, and Android, and make
the build programmable when you need more.**

XIRASM assembles natural ISA text and directly produces flat binaries, Windows
PE/COFF, Linux ELF, macOS Mach-O, and complete SPIR-V modules. It also builds
the Android APK around the code it just assembled. Start with ordinary assembly.
Reach for its typed compile-time language only when a project needs generated
code, reusable format logic, or precise binary layout.

- **Four instruction sets:** x86 in 16/32/64-bit modes, AArch64, RV32/RV64, and
  SPIR-V 1.6.
- **Useful output, not an intermediate experiment:** executables, DLLs, shared
  libraries, object files, Mach-O images, flat binaries, SPIR-V modules, and
  installable Android APKs.
- **AArch64 that reaches a real device:** `arm/a64-macros.inc` brings AArch64
  instruction text, and the format layer carries the encoded bytes into ELF64
  executables, PIE, objects, and Android shared libraries, PE64/COFF64 images,
  and Mach-O arm64 executables, dylibs, and objects, with the relocations and
  import stubs each of those needs.
- **Android without a Java build:** the APK writer emits the ZIP container, the
  binary `AndroidManifest.xml`, and a `resources.arsc` compiled from a resource
  tree, and it can carry the NativeActivity shared library assembled from the
  same source. Platform resource IDs such as
  `@android:style/Theme.DeviceDefault` come from a generated framework catalog.
- **Modern metaprogramming:** typed values, functions, collections, modules,
  structured control flow, and source-located diagnostics instead of a fragile
  text-macro layer.
- **A short path to native output:** project templates provide ready-to-build
  Windows and Linux programs; format facades handle ordinary PE, COFF, ELF, and
  Mach-O work without requiring users to construct every header by hand.

## Download

Every release is also published as prebuilt packages, so a toolchain is only
needed to change XIRASM itself:

- Windows x86-64 (ZIP) and Linux x86-64 (statically linked TAR.GZ);
- macOS Apple Silicon (TAR.GZ);
- the VS Code extension and language server (VSIX).

Get the current release from [the project site](https://xirasm-site.pages.dev/#downloads)
or from the [GitHub release](https://github.com/XIRASM/XirAsm/releases/latest), which
lists the SHA-256 of every package. Each archive carries the executable, the
`include` library, the test corpus, and the English and Chinese documentation.

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

AArch64 instruction text comes from the generated include layer rather than a
CLI target: `import("arm/a64-macros.inc")` makes `mov x8, #93` and `svc #0`
assemble, and the format facade decides whether the result becomes an ELF64
image, a PE64 image, an object file, or a Mach-O image.

The same project model and compile-time language apply across targets. You do
not have to learn one macro system for x86 and another generation language for
RISC-V or SPIR-V.

## Output Formats

XIRASM can directly produce:

| Platform or use | Formats |
| --- | --- |
| Windows | PE32/PE64 executables and DLLs for x86 and ARM64; COFF32/COFF64 objects for x86 and ARM64 |
| Linux | ELF32/ELF64 executables; ELF64 PIE and shared libraries (x86-64 and AArch64); ELF32/ELF64 objects |
| macOS | Mach-O 64 executables, dylibs, and objects for x86_64 and arm64, with dyld imports, stubs, and export tables |
| Android | APK archives: ZIP container, binary manifest, compiled resource table, assets, and per-ABI native libraries |
| Bare metal and tooling | Flat and application-specific binaries |
| GPU and IR tooling | Complete SPIR-V 1.6 modules |

Normal PE, COFF, and ELF projects use the format library's high-level facades:

```asm
import("format/format.inc");
```

When a loader, file format, or research tool needs an unusual layout, the same
language also exposes regions, labels, alignment, finalizers, and direct format
helpers. The common path stays short; low-level control remains available.

## Build an Android APK

An APK is a ZIP archive holding a binary manifest and a compiled resource table.
XIRASM writes all three, and the native library inside can come from the same
project:

```asm
import("format/apk.inc");

origin(0)

let app: map = apk_new("com.example.tool", 1, "1.0", "demo")
app = apk_res_dir(app, "res")
app = apk_native_lib(app, "arm64-v8a", "libdemo.so", "build/arm64-v8a/libdemo.so")
apk_emit(app)
```

The archive installs and runs with no DEX, no Java source, and no third-party
runtime: the activity is a NativeActivity whose entry point is the shared
library's own `ANativeActivity_onCreate`. `tests/format/android_gl_demo/` is a
complete GLES2 renderer and the archive around it, both written by the
assembler, and it builds to a 39 KB APK that reads back cleanly through `aapt2`
and `zipalign`. Signing stays outside the assembler; see the
[Android guide](document/apk.md) for the SDK command sequence.

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
whether source text parses. It includes x86 layout and fixup cases, RISC-V and
AArch64 byte comparisons with LLVM tooling, SPIR-V assembly/disassembly and
validation, and structural, linker, loader, and native-runtime checks for
supported binary formats. Independent readers verify the results: LLVM tools for
instruction encodings and ELF, COFF, and Mach-O structure, and Android SDK tools
(`aapt2`, `zipalign`) plus a separate decompressor for the APK.

## Editor and Documentation

The standalone [XIRASM VS Code extension](https://github.com/XIRASM/xir-vscode)
provides highlighting, completion, navigation, and compiler-backed diagnostics.

- [Language Guide](document/language.md) - learn the assembly and compile-time
  language model.
- [Format Tutorial](document/format-tutorial.md) - build PE, COFF, ELF, and
  Mach-O files with user-facing facade APIs.
- [Android Guide](document/apk.md) - assemble a NativeActivity library and the
  APK, resource table, and manifest around it.
- [Language API Reference](document/api-reference.md) - look up syntax and
  built-in APIs.
- [Advanced Format Construction](document/advanced-formats.md) - take direct
  control of uncommon binary layouts.

## Status

Current version: **0.2.21**. See the [release notes](document/releases/0.2.21.md).

XIRASM is pre-1.0 software. The assembler, language APIs, format library, CLI,
and editor support are usable now, while public contracts may still be refined
before 1.0.

## License

Apache-2.0.
