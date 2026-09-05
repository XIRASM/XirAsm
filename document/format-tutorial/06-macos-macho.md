# 6. macOS Mach-O

The Mach-O helpers are a direct XIRASM DSL layer for macOS images. They emit
records and bytes for a selected CPU type; they do not add a second instruction
encoder or a native ARM text parser.

## Quick Start

Choose the product first: use `macho_obj.inc` for a `.o` consumed by a linker,
`macho_exe.inc` for a direct executable, and `macho_dylib.inc` for a shared
library. Add `macho_import.inc` only for direct executable dyld imports. The
checked `tests/format/macho64_*` files are complete layouts for `arm64` and
`x86_64`; copy one and change its labels, addresses, and emitted ISA bytes.
The format helpers do not assemble instruction text.

## Public Entry

Import the normal format entry point when you want all format helpers:

```asm
import("format/format.inc");
```

The Mach-O helpers are also available directly:

```asm
import("format/macho_obj.inc");
```

## Three Products

| Product | Helper | Intended next tool |
| --- | --- | --- |
| Relocatable object | `macho_obj.inc` | `ld64` or `ld64.lld` |
| Executable | `macho_exe.inc` | macOS loader; signing is external |
| Shared library | `macho_dylib.inc` | dyld; imports and signing are external |

## Capability Matrix

| Capability | arm64 | x86_64 | Owner |
| --- | --- | --- | --- |
| Mach-O 64 header/segments/sections | yes | yes | `macho_obj.inc` |
| Direct `MH_EXECUTE` | yes | yes | `macho_exe.inc` |
| `LC_LOAD_DYLINKER` | yes | yes | `macho_exe_load_dylinker64` |
| `MH_DYLIB` install name | yes | yes | `macho_dylib.inc` |
| Ordinary function export trie | yes | yes | `macho_export.inc` |
| Object relocations | `BRANCH26`, `PAGE21`, `PAGEOFF12` | `BRANCH`, `UNSIGNED` | ISA-specific wrappers |
| Direct executable function imports | yes | yes | `macho_import.inc` |

The object helper writes `MH_OBJECT`, section and symbol tables, and explicit
AArch64 `BRANCH26`, `PAGE21`, and `PAGEOFF12` relocation records plus the
x86_64 external `BRANCH` relocation. The executable
and dylib headers are CPU-neutral; ARM64 and x86_64 wrappers are provided. The
executable helper writes a small `MH_EXECUTE` with `__PAGEZERO`,
`__TEXT,__text`, `LC_LOAD_DYLINKER` for `/usr/lib/dyld`, `LC_MAIN`, and
`LC_BUILD_VERSION`. The dylib helper writes a
minimal `MH_DYLIB` with an install name. `macho_export_new` and
`macho_export_use64` collect ordinary function exports; after their target
labels are laid out, `macho_export_trie_size64` and
`macho_export_trie_emit64` generate the export trie. Its load-command size
fields are placeholders owned by the source and are backfilled in `defer`.

## Importing Functions In A Direct Executable

`macho_import.inc` provides the small direct-executable path. It emits classic
non-lazy dyld binding metadata rather than chained fixups: undefined `nlist_64`
symbols, `LC_SYMTAB`, `LC_DYSYMTAB`, an indirect symbol table,
`__TEXT,__stubs`, and `__DATA,__got`. Generic records and binding opcodes are
shared; only the stub bytes differ between arm64 and x86_64.

```asm
import("format/macho_import.inc");

let imports: list = macho_import_new()
imports = macho_import_use64(imports, "@executable_path/libmath.dylib", "_add7")

// Layout owns the segment VAs and FOAs. Emit the selected ISA's stubs after
// __text, and emit slots plus dyld/link-edit tables in their declared regions.
macho_import_emit_stubs_arm64(imports, stubs_vaddr, slots_vaddr);
// or: macho_import_emit_stubs_x86_64(imports, stubs_vaddr, slots_vaddr);
macho_import_emit_slots64(imports);
macho_import_emit_bind64(imports, data_segment_index);
macho_import_emit_symbols64(imports);
macho_import_emit_indirect64(imports);
macho_import_emit_strings64(imports);
```

The default labels are `<symbol>_stub` and `<symbol>_got`; use
`macho_import_use64_as` when local label names must differ. One import list may
contain multiple dependent dylibs and multiple functions per dylib. Library
ordinals are assigned by first appearance (1..15) and emitted in the bind
stream and undefined-symbol descriptors. Use
`macho_import_load_dylibs_size64` and `macho_import_emit_load_dylibs64` to
declare each unique dependency once. This covers compact CLI/FFI
consumers without implementing lazy binding, a stub helper, chained fixups, or
a general linker. See the checked fixtures
`tests/format/macho64_arm64_exe_import.asm` and
`tests/format/macho64_x86_64_exe_import.asm` for complete layouts.
The current helper is for `MH_EXECUTE`; a dylib that itself imports symbols
still belongs on the linker-backed path.

For an import-bearing executable, derive the dylib-command, bind, and string
sizes from the same import list used by the emitters. Such an executable must
not set `MH_NOUNDEFS`, because its undefined symbols are intentional.

## Exporting FFI Functions

The export helper follows the same collect-then-emit pattern as the PE export
helpers. Target names are strings while declarations are collected; the
export trie is emitted only after the target labels have been laid out:

```asm
import("format/macho_dylib.inc");

let exports: list = macho_export_new()
exports = macho_export_use64(exports, "add7", "_add7")

// Emit the Mach-O header, __TEXT segment, and load commands here.
// Define add7 before measuring or emitting the trie.
add7:
    emit.u32(0xd28000e0)
    emit.u32(0xd65f03c0)

let export_size: u64 = macho_export_trie_size64(exports, 0)
exports_data:
macho_export_trie_emit64(exports, 0);

defer {
    // Store export_size into the already-emitted
    // LC_DYLD_EXPORTS_TRIE.datasize and __LINKEDIT.filesize fields.
}
```

The example is intentionally a direct-layout sketch: the source owns command
offsets and must reserve fixed-width fields before `defer` patches them. The
helper emits ordinary defined exports only; re-exports, weak definitions,
stub/resolver entries, chained fixups, and code signatures are separate
features.

## Coordinates And Delayed Fields

Direct Mach-O construction has two coordinate systems:

- labels and `here()` are logical addresses (the value used for `vmaddr` and
  symbol values);
- file offsets in `segment_64`, `section_64`, and dyld data commands are FOAs.

Use explicit layout math or `region_file_offset(label)` for a final FOA. A
`store.u32`/`store.u64` target is a logical address, not a raw FOA. When a
header field depends on a later region, emit the field at its final width,
emit the region during ordinary source or `late_layout`, and patch only the
value in `defer`. `defer` cannot create bytes, labels, regions, or alignment.

## Boundary With the Linker

Use the object form for multi-object programs. A direct executable or dylib is
useful for small images, but it does not replace Apple's linker or code signing.
The direct import helper generates the dyld metadata for its limited non-lazy
function-import model. Validate generated files with LLVM's
Mach-O readers and an independent AArch64 disassembler before distributing them.

The current direct layer intentionally does not claim universal binaries,
arm64e, chained fixups, lazy binding, more than 15 import libraries per table,
UUIDs, code signatures, or runtime loading on a non-macOS host. dyld still
resolves the declared dependency and symbols at load time. Apple Silicon
executables normally require an external ad-hoc or production signature.

## Validation

On Windows or another non-macOS host, use LLVM and radare2 as structural
oracles:

```text
llvm-readobj --file-headers --sections --symbols --relocs file.o
llvm-objdump --macho --private-headers --exports-trie file.dylib
llvm-objdump --macho --private-headers --bind --indirect-symbols file
ld64.lld -arch arm64 -platform_version macos 14.0 14.0 ...
radare2 -q -n -a arm -b 64 -c "pd 4 @ <text-address>" file
```

These checks prove Mach-O structure, relocation records, export names, and
linker interoperability. Running the final arm64 image and testing `dlopen`
or `dlsym` still requires an Apple Silicon macOS host or an arm64 macOS CI
runner.
