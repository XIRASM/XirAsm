# 1. Choose a Template

Start from the output file you want. Do not begin with PE or ELF header fields.

## One Include

```asm
// Import the common format API.
import("format/format.inc");
```

Direct includes such as `pe.inc`, `elfexe.inc`, and `elfobj.inc` expose lower
header and table helpers. Use them only when you intentionally need manual
construction.

## Configuration Functions

| Output | Configuration function | Content descriptor |
| --- | --- | --- |
| PE32 executable or DLL | `format_pe32(options, sections)` | `format_section(...)` |
| PE64 executable or DLL | `format_pe64(options, sections)` | `format_section(...)` |
| COFF32 object | `format_coff32(sections)` | `format_section(...)` |
| COFF64 object | `format_coff64(sections)` | `format_section(...)` |
| ELF32 executable | `format_elf32(options, segments)` | `format_segment(...)` |
| ELF64 executable or PIE | `format_elf64(options, segments)` | `format_segment(...)` |
| ELF32 object | `format_elfobj32(sections)` | `format_section(...)` |
| ELF64 object | `format_elfobj64(sections)` | `format_section(...)` |
| ELF64 shared object | `format_elf64_so(soname, segments)` | `format_segment(...)` |

PE, COFF, and ELF object files use sections. ELF executable images and shared
objects use load segments.

## Section Descriptors

`format_section(name, attributes)` takes two parameters:

| Parameter | What to pass |
| --- | --- |
| `name` | a section name such as `".text"`, `".data"`, `".bss"`, or `".idata"` |
| `attributes` | one purpose flag plus the required permission flags |

Each section needs exactly one purpose:

| Purpose | Use for |
| --- | --- |
| `format_code` | instructions |
| `format_data` | initialized or read-only data |
| `format_uninitialized_data` | zero-filled memory |
| `format_imports` | PE import tables |
| `format_exports` | PE export tables |
| `format_resources` | PE resources |
| `format_fixups` | PE base relocation tables |

Then add permissions:

| Permission | Meaning |
| --- | --- |
| `format_readable` | mapped readable |
| `format_writeable` | mapped writable |
| `format_executable` | mapped executable |
| `format_discardable` | loader metadata that may be discarded |

Common combinations:

| Purpose | Recommended attributes |
| --- | --- |
| code | `format_code \| format_readable \| format_executable` |
| read-only data | `format_data \| format_readable` |
| writable data | `format_data \| format_readable \| format_writeable` |
| BSS | `format_uninitialized_data \| format_readable \| format_writeable` |
| PE imports | `format_imports \| format_readable \| format_writeable` |
| PE exports | `format_exports \| format_readable` |
| PE resources | `format_resources \| format_readable` |
| PE relocations | `format_fixups \| format_readable \| format_discardable` |

## Segment Descriptors

`format_segment(name, attributes)` is used by ELF images:

| Parameter | What to pass |
| --- | --- |
| `name` | a segment name such as `".text"`, `".rodata"`, `".data"`, or `".bss"` |
| `attributes` | `format_load` plus permission flags |

Common ELF segment combinations:

| Purpose | Recommended attributes |
| --- | --- |
| code | `format_load \| format_readable \| format_executable` |
| read-only data | `format_load \| format_readable` |
| writable data | `format_load \| format_readable \| format_writeable` |
| BSS | `format_load \| format_readable \| format_writeable` |

## Lifecycle

```asm
import("format/format.inc");

// Choose a PE64 console executable and declare two sections.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        // .text contains instructions and is readable/executable.
        format_section(".text", format_code | format_readable | format_executable),
        // .bss is readable/writable memory without initialized file bytes.
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)

// Start the file. format.inc emits the headers and section rows.
format_begin(image);

format_section_begin(image, ".text");
start:
    xor eax, eax
    ret
format_section_end(image, ".text");

format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

`format.inc` derives headers, table rows, file offsets, RVAs, file alignment,
and BSS sizes from the named blocks.
