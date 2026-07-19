# XIRASM Format Tutorial

This tutorial is the practical starting point for building executable files,
dynamic libraries, and object files with XIRASM.

If you have mostly written inline assembly inside C, C++, Rust, or another
language, the surrounding toolchain has usually handled the file format for you.
A loadable program still needs answers to these questions:

- where execution starts;
- which bytes are code and which bytes are data;
- which ranges become readable, writable, or executable memory;
- which ranges occupy memory but do not occupy initialized file bytes;
- which external functions are imported or exported;
- which absolute addresses must be fixed if the loader chooses another base;
- which fields an external linker must patch later.

`format.inc` turns those answers into file headers, tables, offsets, RVAs,
alignment, and final backfills. Normal PE, COFF, and ELF programs start here:

```asm
// Import the common PE/COFF/ELF format API.
import("format/format.inc");
```

The files under `include/format/` serve different jobs:

- `format.inc` is the common entry point for format configuration, named
  sections or segments, imports, exports, resources, relocations, symbols, and
  finalization.
- `pe32.inc`, `pe64.inc`, `elf32.inc`, and `elf64.inc` are thin width-specific
  entry points for existing sources or specialized format code.
- `pe.inc`, `elfexe.inc`, `elfobj.inc`, and related files are direct
  construction helpers for advanced control over fields and table rows.

This tutorial covers `format.inc`. Use the
[Advanced Format Construction Guide](advanced-formats.md) only when a standard
configuration cannot express the file you need.

## Chapters

1. [Choose a Template](format-tutorial/01-choose-a-template.md)
2. [Windows PE and DLLs](format-tutorial/02-windows-pe.md)
3. [Linux ELF Executables and Shared Objects](format-tutorial/03-linux-elf.md)
4. [COFF and ELF Object Files](format-tutorial/04-object-files.md)
5. [Common Rules and Mistakes](format-tutorial/05-common-rules.md)

## Quick Choice Table

| Goal | Start with | Main calls |
| --- | --- | --- |
| Windows executable | `format_pe32` or `format_pe64` | `format_section_begin`, `format_pe_import_section`, `format_pe_resource_section`, `format_pe_reloc_section` |
| Windows DLL | `format_pe32` or `format_pe64` with `format_pe_dll` | `format_pe_export_section`, optional imports, resources, relocations |
| Linux executable | `format_elf32` or `format_elf64` with `format_elf_exec` | `format_segment_begin`, `format_entry_mut`, `format_finish` |
| Linux PIE | `format_elf64` with `format_elf_pie` | `format_segment_begin`, `format_entry_mut`, `format_finish` |
| Linux shared object | `format_elf64_so` | `format_elfso_tables_mut`, `format_segment_begin`, `format_finish` |
| COFF object | `format_coff32` or `format_coff64` | `format_coff_tables_mut`, `format_section_begin`, `format_finish` |
| ELF object | `format_elfobj32` or `format_elfobj64` | `format_elfobj_tables_mut`, `format_section_begin`, `format_finish` |

## Lifecycle

Format configurations all follow the same shape:

```text
import("format/format.inc");

// 1. Create a configuration: file family, width, permissions, sections or segments.
let image: map = ...

// 2. Optional: attach imports, exports, symbols, or relocations.
format_*_tables_mut(image, ...)

// 3. Start the output file. Headers and table rows are reserved here.
format_begin(image);

// 4. Emit code or data inside a declared name.
format_section_begin(image, ".text");
start:
    ret
format_section_end(image, ".text");

// 5. Executables set an entry point, then finish the file.
format_entry_mut(image, start)
format_finish(image);
```

Configuration and declaration mutators are statements. Their mutable argument
must be a direct `let` binding:

```text
let image: map = format_pe64(options, sections)
format_entry_mut(image, start)
format_finish(image);
```

Constructors and descriptors still return values. Functions ending in `_mut`
update the named configuration or declaration collection in place.
