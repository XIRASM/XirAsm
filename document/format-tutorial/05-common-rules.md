# 5. Common Rules and Mistakes

When a format source fails, check the plan, names, permissions, and lifecycle
order before digging into file-format internals.

## Use One Layer

For normal programs, use:

```asm
import("format/format.inc");
```

Do not mix high-level facade calls with manual header or table emission unless
you are intentionally writing an advanced construction.

## Mutate One Configuration

Create plans and declaration collections as `let` bindings. Mutating facade
calls update those bindings directly:

```text
let image: map = format_elf64(format_elf_exec, segments)
let imports: list = format_elfexe_import_new()
format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid"))
format_elfexe_tables_mut(image, imports)
format_entry_mut(image, start)
```

The first argument of a `_mut` function must name a compatible `let` binding.

## Declare Before Emitting

The name passed to `format_section_begin`, `format_section_end`,
`format_segment_begin`, or `format_segment_end` must exist in the plan:

```text
format_section(".text", format_code | format_readable | format_executable)
```

Section and segment names must be unique.

## Pick Exactly One Purpose

This is valid:

```text
format_section(".text", format_code | format_readable | format_executable)
```

This is not:

```text
format_section(".mixed", format_code | format_data | format_readable)
```

Use one purpose plus any needed permissions.

## Choose Permissions by Runtime Need

| Content | Common permissions |
| --- | --- |
| instructions | readable, executable |
| constants and strings | readable |
| mutable data | readable, writable |
| BSS | readable, writable |
| import tables | readable, often writable for PE |
| relocation tables | readable, often discardable for PE |

Do not make code writable unless you truly need self-modifying code. Do not make
data executable.

## BSS Is Memory, Not File Payload

For `format_uninitialized_data`, emit `rb(...)` or `reserve(...)`. The facade
records logical size while keeping initialized file bytes empty when required.

## Relocations Are Not Pointers

Writing a pointer value and declaring a relocation are separate steps:

```text
// Actual address storage in the file.
absolute_slot:
    dq(0);

// Tell the PE loader this slot needs base relocation.
let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, absolute_slot)
format_pe_reloc_section(image, ".reloc", relocs);

// Write the final value after layout is stable.
defer {
    store.u64(absolute_slot, start);
}
```

The stored value is the bytes in the image. The relocation record tells the
loader or linker that those bytes may need adjustment.

## Entry Points Belong to Executables

Use `format_entry_mut(plan, label)` for PE and ELF executables. Object files and
ELF shared objects do not use the same entry workflow.

## Finalizers May Backfill, Not Re-layout

Use `defer` for final checks, pointer backfills, and checksums. Do not emit new
layout-changing content in `defer`. Bytes that participate in layout must be
emitted before `format_finish`.

## Build Up from a Minimal Template

A practical order is:

1. Start with a `.text`-only executable.
2. Add `.data` or `.bss`.
3. Add imports when you need system functions.
4. Add exports when building a DLL or shared object.
5. Add base relocations when the file stores absolute addresses.
6. Use COFF or ELF object templates when another linker will finish the file.
