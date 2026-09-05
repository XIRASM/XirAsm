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

// The facade accepts arm64 (16 KiB pages) and x86_64 (4 KiB pages).
const version: u64 = macho_exe_macos_version(14, 0, 0)
let image: map = format_macho64_exe(
    format_macho64_target_x86_64(version, version),
    list.of(format_macho64_segment(
        "__TEXT",
        format_load | format_readable | format_executable,
        list.of(format_section("__text", format_code | format_readable | format_executable))
    ))
)

format_begin(image);
format_section_begin(image, "__text");
entry:
db(0x31, 0xc0, 0xc3);
format_section_end(image, "__text");
format_entry_mut(image, entry);
format_finish(image);
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

The higher-level `format_macho64_object`, `format_macho64_exe`, and
`format_macho64_dylib` constructors use the same section lifecycle. A section
is identified by `(segment_name, section_name)`; when two segments contain the
same section name, use `format_macho64_section_begin/end` with both names.
The facade's `MH_OBJECT` form has one implicit segment and therefore requires
unique section names.
The facade emits ordinary code, data, and zerofill sections. For objects it
also owns the symbol table, relocations, and `LC_SYMTAB` end to end — see
[Object Symbols And Relocations](#object-symbols-and-relocations) below. Dyld
imports, code signatures, and chained fixups remain explicit lower-level
helpers or linker responsibilities.

## Object Symbols And Relocations

`format_macho64_object` reserves the `LC_SYMTAB` load command when the header
is emitted and backfills its offsets at `format_finish`. You never compute
symbol indexes or string-table offsets; you declare symbols and relocations by
name and attach them with `format_macho64_tables_mut`:

```asm
import("format/format.inc");

const version: u64 = macho_exe_macos_version(14, 0, 0)
let object: map = format_macho64_object(
    format_macho64_target_arm64(version, version),
    list.of(
        format_section("__text", format_code | format_readable | format_executable),
        format_section("__data", format_data | format_readable | format_writeable)
    )
)

format_begin(object);

// Placeholder words whose immediate fields the linker patches.
format_section_begin(object, "__text");
text_start:
call_site:
    emit.u32(0x94000000);
page_site:
    emit.u32(0x90000000);
lo12_site:
    emit.u32(0x91000000);
format_section_end(object, "__text");

format_section_begin(object, "__data");
data_start:
answer:
    emit.u64(42);
pointer_slot:
    emit.u64(0);
format_section_end(object, "__data");

const symbols: list = list.of(
    format_macho64_public("_entry", "__text", text_start, call_site, macho_n_sect | macho_n_ext),
    format_macho64_public("_answer", "__data", data_start, answer, macho_n_sect | macho_n_ext),
    format_macho64_extern("_printf")
)
const relocs: list = list.of(
    format_macho64_arm64_reloc("__text", text_start, call_site, "_printf", macho_arm64_reloc_branch26),
    format_macho64_arm64_reloc("__text", text_start, page_site, "_answer", macho_arm64_reloc_page21),
    format_macho64_arm64_reloc("__text", text_start, lo12_site, "_answer", macho_arm64_reloc_pageoff12),
    format_macho64_arm64_reloc("__data", data_start, pointer_slot, "_printf", macho_arm64_reloc_unsigned)
)
format_macho64_tables_mut(object, symbols, relocs)
format_finish(object);
```

Symbol semantics:

- `format_macho64_public(name, section_name, section_start, address, symbol_type)`
  defines a symbol in a section. `symbol_type` is the complete `n_type`; a
  normal global is `macho_n_sect | macho_n_ext`. The emitted record gets
  `n_value = address - section_start` and `n_sect` set to the section's
  1-based index.
- `format_macho64_extern(name)` declares an undefined external
  (`N_UNDF | N_EXT`, zero value) that the linker resolves.
- Names go into the string table; the facade computes every `n_strx`.

Relocation semantics:

- A relocation address is an offset inside its section
  (`address - section_start`), which is what `r_address` means in an object
  file.
- The target symbol is resolved by name against the attached symbol list, and
  `r_extern` is always 1 with `r_symbolnum` set to the nlist index. For the
  constructs above the encoding is bit-identical to what clang emits for
  arm64 object files.
- `format_macho64_reloc` takes the explicit `pcrel` flag, the `length` power
  (0 = 1 byte, 1 = 2, 2 = 4, 3 = 8), and the relocation type.
  `format_macho64_arm64_reloc` derives both from the AArch64 type:
  `macho_arm64_reloc_unsigned` is a non-pcrel 8-byte field,
  `branch26`, `page21`, and `got_load_page21`/`tlvp_load_page21` are pcrel
  4-byte fields, and `pageoff12`, `got_load_pageoff12`, and
  `tlvp_load_pageoff12` are non-pcrel 4-byte fields.
- Paired records (`ARM64_RELOC_SUBTRACTOR` with its `ADDEND` follower),
  `POINTER_TO_GOT`, and the arm64e types are outside the facade; emit them
  with the direct `macho_relocation_info` helper.

`format_macho64_tables_mut` validates both lists — names must be unique, and
every relocation section and symbol must be declared. An object that never
attaches tables is still valid; it simply carries an empty symbol table.

## Capability Matrix

| Capability | arm64 | x86_64 | Owner |
| --- | --- | --- | --- |
| Mach-O 64 header/segments/sections | yes | yes | `macho_obj.inc` |
| Facade object with symbols, relocations, and `LC_SYMTAB` | yes | yes | `format.inc` |
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
