# 5. Common Rules and Mistakes

When a format source fails, the problem is rarely in the PE or ELF field details; it is in the declarations: a section name misspelled, one section given several purposes, permissions that do not match how the range is used, or calls in the wrong order. The headers and tables are generated from the declarations, so when a declaration disagrees with the intent, the file is still structurally valid — it is simply not the file that was wanted.

The rules below run from "what the error looks like" to "how to avoid it". Each one comes with a real diagnostic or a checkable result, ready to compare against your own source.

## Do Not Mix Two Sets of Calls

A normal program imports one file:

```asm id=only-one-layer
import("format/format.inc")
```

Do not use `format.inc`'s lifecycle functions and hand-written PE/ELF headers or tables in the same file. When two sets of calls own the same table, the final file ends up with two values both trying to fill one field: the earlier write is overwritten and there is no way to tell which one took effect. When the fields must be fully controlled, organize the whole file as [advanced construction](../advanced-formats.md) instead.

Mixing sections and segments is caught as well, because the two kinds of plan carry different keys: an ELF image given `format_section` reports `an ELF image plan declares segments, not sections`, and a PE image given `format_segment` reports `only an ELF image plan declares segments`.

## A Mutable Configuration Must Be a `let`

A function whose name ends in `_mut` rewrites the binding passed to it, so that argument has to be a `let` that can be rewritten:

```asm id=mut-requires-let
import("format/format.inc")

// The configuration is rewritten by _mut functions, so it is a let, not a const.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    )
)
format_begin(image)
format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")
format_entry_mut(image, start)
format_finish(image)
```

These three forms are all invalid, and each reports differently:

| Form | Diagnostic |
| --- | --- |
| `const image: map = format_pe64(...)` followed by a `_mut` call | `mutable function argument must resolve to a let binding` |
| passing a constructor's result straight to a `_mut` function | `mutable function argument must be a direct let binding` |
| passing something like `map.get(holder, "image")` | the same, because no binding can be resolved |

The distinction is this: **read-only descriptor values can live in a `const`**, such as the results of `format_section(...)`, `format_segment(...)`, or `format_coff_public(...)`; **a configuration or collection that a `_mut` function rewrites must be a `let`**.

## Declare Before Writing Content

The name passed to `format_section_begin`, `format_section_end`, `format_segment_begin`, or `format_segment_end` must already appear in the configuration's section or segment list:

```text
// Whatever the configuration declares is what can be written.
format_section(".text", format_code | format_readable | format_executable)
```

Writing a section that was never declared reports `format section is not declared`. The diagnostic points at the `format_section_begin` line, but the fix belongs in the declaration list above it.

## One Purpose Per Descriptor

A section is exactly one of code, data, BSS, imports, exports, resources, or base relocations. Giving it two purposes reports `format section has multiple purposes`:

```text
// Invalid: one section claiming to be both code and data.
format_section(".mixed", format_code | format_data | format_readable)
```

Permissions may be combined; purposes may not. An ELF load segment currently has only `format_load` as its purpose, with no second option.

## Permissions Follow Run-Time Need

| Content | Common permissions |
| --- | --- |
| instructions | readable, executable |
| constants and strings | readable |
| mutable data | readable, writable |
| BSS | readable, writable |
| PE import tables | readable, writable |
| PE base relocation tables | readable, discardable |

Apart from self-modifying code or a specialized loader scenario, do not mark a code section writable or a data section executable. Excess permissions raise no error, but they let the loader permit writes or execution it would otherwise refuse.

## BSS Is a Memory Size, Not File Content

`format_uninitialized_data` declares "this program needs a range of zero-filled memory at run time". Register the size inside it with a reserve form such as `rb(...)` or `reserve(...)`:

```asm id=bss-reserved-only target=x86-64
import("format/format.inc")

// The correct BSS form: rb() registers the size and writes no initialized bytes.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")

// rb(8) registers memory size and takes no file bytes.
format_section_begin(image, ".bss")
scratch:
    rb(8)
format_section_end(image, ".bss")

format_entry_mut(image, start)
format_finish(image)
```

The `.bss` written this way has file size 0 and memory size 8.

Writing real bytes into `.bss` instead **raises no error**, but the result contradicts itself: the section still carries `IMAGE_SCN_CNT_UNINITIALIZED_DATA` (claiming no initialized data) while its file size stops being 0. Replace the line above with `dd(0x11223344)` and `dd(0x55667788)` and `.bss` reports a file size of 512 — one whole block after file alignment, while the loader still reads the attribute as "this range needs nothing from the file". The file assembles, and its meaning is wrong, so bytes like these belong in a `format_data` section.

## Relocations Are Not Pointers

Writing a pointer value and declaring a relocation are two separate acts, and both are needed:

```asm id=reloc-not-pointer
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
worker:
    mov eax, 42
    ret
format_section_end(image, ".text")

// The slot is written at its final width first; only its value changes later.
format_section_begin(image, ".data")
worker_pointer:
    dq(0)
format_section_end(image, ".data")

let relocs: list = pe_reloc_new()
// The argument is the slot holding the address, not the worker it points at.
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, start)
format_finish(image)

// The value is written once every address is stable.
defer {
    store.u64(worker_pointer, worker)
}
```

`format_pe_reloc_add_mut` takes the **address of the slot**. Passing the target label `worker` instead raises no error, but the generated record points into the middle of an instruction in `.text`, and a moved image adjusts a location that is not a slot; in the example above, passing `worker` puts the record at `0x1001`, inside `.text`. The way to check is to compare the record's RVA with the section table: it has to land on the slot in `.data`.

Writing a value inside `defer` is allowed, because a value does not change the file size; the `store.u64` above sits in a `defer` for exactly that reason.

## Entry Points Belong to Executables

A PE executable, a PE DLL, and an ELF executable all need an entry:

```text
format_entry_mut(image, start)
```

COFF objects, ELF objects, and ELF shared objects take no entry. Setting one reports `format plan does not use an executable entry`; the other direction, a PE or ELF executable with no entry, makes `format_finish` report `PE executable or DLL requires an entry address` or `ELF executable requires an entry address`.

## When to Attach Tables

Exactly one group of functions has to be called **before** `format_begin`: the `format_*_tables_mut` functions that attach symbol tables, relocation tables, or import and export metadata to a configuration — `format_coff_tables_mut`, `format_elfobj_tables_mut`, `format_elfexe_tables_mut`, `format_elfso_tables_mut`. They decide how much room the headers and dynamic tables need, so the data has to be in hand before output starts.

The PE section generators are not bound by that rule. `format_pe_import_section`, `format_pe_export_section`, `format_pe_resource_section`, and `format_pe_reloc_section` write section content, so they belong after `format_begin` and before `format_finish`; called after `format_begin`, the import directory is registered just the same (`RVA = 0x2040`, `size = 40`). Their only requirement is not to open the same section again with a `format_section_begin` of your own.

## `defer` Only Backfills

`defer` suits work that leaves the layout alone: filling in addresses, writing pointer slots, computing a checksum. Writing content into it reports an error:

```text
// Invalid: section content written inside defer.
defer {
    format_section_begin(image, ".text")
    dd(0x11223344)
    format_section_end(image, ".text")
}
```

The diagnostic is `FinalizerCannotChangeLayout`. Bytes that take part in the layout must be written before `format_finish`; `defer` changes values only, once the final bytes are settled.

## Some Mistakes Are Up to the Source

Each rule above comes with a diagnostic or a checkable result, but a few mistakes `format.inc` will not catch, and only the way the source is written can avoid them:

| Situation | Consequence |
| --- | --- |
| real bytes written into `.bss` | assembles; the section attribute contradicts its content, and it takes an extra file block |
| a relocation naming the target label | assembles; the record points at an unrelated location |
| `format_section_end` left out | assembles; the section row never settles and the file is truncated |
| argument registers placed against the ABI in a cross-language call | assembles and links; the run produces a wrong answer |

None of these four gives any warning, so after touching them the **output has to be checked**: read the section table and directories with `llvm-readobj`, or run the file and look at the exit status. Chapters 3 and 4 give the exact commands.
