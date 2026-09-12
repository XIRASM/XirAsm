# 1. Choose a Template

Writing a format file starts with choosing which file to produce. That decision fixes everything after it: a PE image carries a section table, an ELF executable carries program headers, and an object file has neither an entry address nor a load segment. Choose the wrong kind and the content you write has nowhere to go.

`format.inc` groups the common outputs into one set of entry points. It is a wrapper layer: you declare which file you want, which sections or load segments it has, and where execution starts; it generates the headers, the section table or program headers, the file offsets, the RVAs, the alignment, and the final backfills.

## One Include

```asm
// Declare the sections or segments; format.inc generates the rest.
import("format/format.inc")
```

Importing `pe.inc`, `elfexe.inc`, `elfobj.inc`, or their relatives directly means filling in headers, directories, and table rows yourself. Reach for the [Advanced Format Construction Guide](../advanced-formats.md) only when `format.inc` cannot express the layout you need.

## Configuration Functions

| Output | Configuration function | Content descriptor | Options |
| --- | --- | --- | --- |
| PE32 executable or DLL | `format_pe32(options, sections)` | `format_section(...)` | required |
| PE64 executable or DLL | `format_pe64(options, sections)` | `format_section(...)` | required |
| PE64 AArch64 executable or DLL | `format_pe64_arm64(options, sections)` | `format_section(...)` | required |
| COFF32 object | `format_coff32(sections)` | `format_section(...)` | none |
| COFF64 object | `format_coff64(sections)` | `format_section(...)` | none |
| COFF64 AArch64 object | `format_coff64_arm64(sections)` | `format_section(...)` | none |
| ELF32 executable | `format_elf32(options, segments)` | `format_segment(...)` | required, only `format_elf_exec` |
| ELF64 executable | `format_elf64(options, segments)` | `format_segment(...)` | required |
| ELF64 AArch64 executable | `format_elf64_aarch64(options, segments)` | `format_segment(...)` | required |
| ELF32 object | `format_elfobj32(sections)` | `format_section(...)` | none |
| ELF64 object | `format_elfobj64(sections)` | `format_section(...)` | none |
| ELF64 AArch64 object | `format_elfobj64_aarch64(sections)` | `format_section(...)` | none |
| ELF64 shared object | `format_elf64_so(soname, segments)` | `format_segment(...)` | none; pass the library name |
| ELF64 AArch64 shared object | `format_elf64_so_aarch64(soname, segments)` | `format_segment(...)` | none; pass the library name |

An ELF executable covers both `format_elf_exec` and `format_elf_pie`. A shared object needs no option, because the function fixes its type. The ELF32 layer supports executable mode only; passing `format_elf_pie` reports `format.inc ELF32 layer currently supports executable mode`.

## Section Descriptors

PE, COFF, and ELF object files organize content as sections. `format_section(name, attributes)` declares one and takes two parameters:

| Parameter | What to pass |
| --- | --- |
| `name` | a section name such as `".text"`, `".data"`, `".bss"`, or `".idata"` |
| `attributes` | one purpose flag plus the permission flags you need |

The purpose says what the section holds, and each section takes **exactly one**:

| Purpose | Holds |
| --- | --- |
| `format_code` | instructions |
| `format_data` | initialized or read-only data |
| `format_uninitialized_data` | zero-filled memory, that is, BSS |
| `format_imports` | PE import tables |
| `format_exports` | PE export tables |
| `format_resources` | PE resources |
| `format_fixups` | PE base relocation tables |

The permissions say how the section is accessed at run time and can be combined:

| Permission | Meaning |
| --- | --- |
| `format_readable` | mapped readable |
| `format_writeable` | mapped writable |
| `format_executable` | mapped executable |
| `format_discardable` | loader metadata that may be discarded |

Common combinations:

| Content | Recommended attributes |
| --- | --- |
| code | `format_code \| format_readable \| format_executable` |
| read-only data | `format_data \| format_readable` |
| writable data | `format_data \| format_readable \| format_writeable` |
| BSS | `format_uninitialized_data \| format_readable \| format_writeable` |
| PE imports | `format_imports \| format_readable \| format_writeable` |
| PE exports | `format_exports \| format_readable` |
| PE resources | `format_resources \| format_readable` |
| PE relocations | `format_fixups \| format_readable \| format_discardable` |

Section names must be unique. PE and COFF names cannot exceed eight bytes; a longer name reports `PE/COFF section names must fit in eight bytes`. The four purposes `format_imports`, `format_exports`, `format_resources`, and `format_fixups` may each appear only once in a configuration; a second one reports `format special-purpose section is duplicated`.

## Segment Descriptors

An ELF executable or shared object is not organized as sections but as load segments: the program headers describe those segments, and the loader maps the file into memory from them. `format_segment(name, attributes)` declares one:

| Parameter | What to pass |
| --- | --- |
| `name` | a segment name such as `".text"`, `".rodata"`, `".data"`, or `".bss"` |
| `attributes` | `format_load` plus permission flags |

`format_load` is the only segment purpose this layer supports. The permissions are the same three: `format_readable`, `format_writeable`, and `format_executable`. A load segment has no discardable notion, so `format_discardable` reports `unknown format segment attribute`.

| Content | Recommended attributes |
| --- | --- |
| code | `format_load \| format_readable \| format_executable` |
| read-only data | `format_load \| format_readable` |
| writable data | `format_load \| format_readable \| format_writeable` |
| BSS | `format_load \| format_readable \| format_writeable` |

Segment names must also be unique; a repeat reports `format segment name is duplicated`.

## Lifecycle

The example below is a minimal PE64 console program. It declares `.text` and `.bss`; `format.inc` generates the PE headers, the section table, and the entry field, and handles the difference between a BSS section's file size and its memory size:

```asm id=pe64-minimal target=x86-64
import("format/format.inc")

// Four options: executable, console subsystem, NX on, ASLR off.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        // Code section: readable and executable.
        format_section(".text", format_code | format_readable | format_executable),
        // BSS section: readable and writable, but only memory.
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)

// Open the output first: the headers and the section rows are reserved here.
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

// BSS occupies memory addresses, never file bytes.
format_section_begin(image, ".bss")
scratch:
    rb(64)
format_section_end(image, ".bss")

// Set the entry address, then backfill every field.
format_entry_mut(image, start)
format_finish(image)
```

The result is a 1024-byte PE: an `MZ` header, a `PE\0\0` signature, machine `0x8664` (x86-64), entry RVA `0x1000`, two rows in the section table, and a `.bss` whose file size is 0 while its memory size is 64. `llvm-readobj` reads it back as `Format: COFF-x86-64`, `SizeOfHeaders: 512`, `Subsystem: IMAGE_SUBSYSTEM_WINDOWS_CUI`, and `IMAGE_DLL_CHARACTERISTICS_NX_COMPAT` with `DYNAMIC_BASE` clear.

Five steps put that together, and skipping one breaks the file:

1. create the configuration with `let image: map = ...`;
2. call `format_begin(image)` to reserve the headers and table rows;
3. write content inside an already declared section;
4. set the entry with `format_entry_mut(image, start)` for an executable;
5. call `format_finish(image)` to perform every backfill.

Step 3 cannot drop `format_section_end`. Leaving it out raises no error and the assembly still succeeds, but the section row never settles: the file shrinks from 1024 bytes to 515, and `.text` keeps a file size of 3, its logical length, instead of the 512 the file alignment requires. A loader rejects that file outright.

## ELF Executables

An ELF executable replaces `format_section` with `format_segment` and `format_section_begin`/`format_section_end` with `format_segment_begin`/`format_segment_end`. Everything else keeps the same order:

```asm id=elf64-minimal target=x86-64
import("format/format.inc")

// The format_elf_exec option selects a plain executable; format_elf_pie makes it a PIE.
let image: map = format_elf64(
    format_elf_exec,
    list.of(
        // Load segment: readable and executable, mapped by the loader.
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

format_begin(image)

format_segment_begin(image, ".text")
start:
    // Syscall 60: exit(0).
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text")

format_entry_mut(image, start)
format_finish(image)
```

The output is 137 bytes: a `\x7fELF` magic, 64-bit little-endian, type `ET_EXEC` (2), machine `EM_X86_64` (62), entry `0x400080`, one `PT_LOAD` program header with `R|X` permissions, file size 9, memory size 9, and `0x1000` page alignment. `llvm-readobj` reports the same values, and the segment offset and address agree modulo the page as `PT_LOAD` requires.

The two kinds do not mix: an ELF image with `format_section` reports `an ELF image plan declares segments, not sections`, and PE with `format_segment` reports `only an ELF image plan declares segments`. An object file and an ELF shared object have no ordinary executable entry, so calling `format_entry_mut` on them reports `format plan does not use an executable entry`.
