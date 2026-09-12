# 2. Windows PE and DLLs

Windows executables and DLLs both use the PE format. Generating one with `format.inc` means specifying three things in `options`: whether the file role is an exe or a DLL, which subsystem it uses, and which ASLR policy applies; `format_pe_nx` is a separate optional flag. The remaining header fields, the section table, the import and export directories, and the base relocation table all follow from those.

## PE Options

The `options` argument of `format_pe32(options, sections)` and `format_pe64(options, sections)` must specify one role, one subsystem, and one ASLR policy, with `format_pe_nx` optional. Leaving a group out is an error: no role reports `PE format requires EXE or DLL`, no subsystem reports `PE format requires console or GUI subsystem`, and no ASLR reports `PE format requires an ASLR policy`. Two values from the same group is also an error — console and gui together report `PE format has multiple subsystems`.

| Group | Value | Meaning |
| --- | --- | --- |
| role | `format_pe_exe` | executable |
| role | `format_pe_dll` | DLL |
| subsystem | `format_pe_console` | console program |
| subsystem | `format_pe_gui` | GUI program |
| safety | `format_pe_nx` | mark the image NX-compatible |
| ASLR | `format_pe_aslr_auto` | enable ASLR only when a relocation section exists |
| ASLR | `format_pe_aslr_required` | require ASLR, and require a relocation section |
| ASLR | `format_pe_aslr_disabled` | disable ASLR |

`format_pe_nx` sets the `NX_COMPAT` bit in `DllCharacteristics`. The three ASLR policies write the `DYNAMIC_BASE` bit of the same field:

| Policy | `DllCharacteristics` |
| --- | --- |
| `format_pe_aslr_auto`, no relocation section declared | `0x100`: `DYNAMIC_BASE` clear, relocation directory `(0, 0)` |
| `format_pe_aslr_required`, relocation section declared | `0x160`: `DYNAMIC_BASE` set, relocation directory pointing at `.reloc` |

Requiring ASLR without declaring a relocation section reports `PE ASLR required needs a fixups section`.

`format_pe64` builds an x86-64 image and `format_pe64_arm64(options, sections)` builds an AArch64 one. The two machines share the container layout, the import and export directories, and the DIR64 base relocations; only the file header machine field and the instruction encoding differ.

Common PE sections:

| Section | Recommended attributes |
| --- | --- |
| `".text"` | `format_code \| format_readable \| format_executable` |
| `".data"` | `format_data \| format_readable \| format_writeable` |
| `".bss"` | `format_uninitialized_data \| format_readable \| format_writeable` |
| `".idata"` | `format_imports \| format_readable \| format_writeable` |
| `".edata"` | `format_exports \| format_readable` |
| `".rsrc"` | `format_resources \| format_readable` |
| `".reloc"` | `format_fixups \| format_readable \| format_discardable` |

A PE section name is at most eight bytes. The four special purposes — imports, exports, resources, and fixups — may each appear only once in one configuration.

## Minimal PE64 Executable

```asm id=pe64-executable target=x86-64
import("format/format.inc")

// Executable, console subsystem, DEP on, ASLR off.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        // Code section: readable and executable.
        format_section(".text", format_code | format_readable | format_executable),
        // BSS: 64 bytes of memory only, never file bytes.
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

format_section_begin(image, ".bss")
    rb(64)
format_section_end(image, ".bss")

// The entry address must be nonzero: a PE plan without one makes format_finish
// report "PE executable or DLL requires an entry address".
format_entry_mut(image, start)
format_finish(image)
```

`format_begin` writes and reserves the PE headers and the section table; `format_finish` backfills the entry, section sizes, RVAs, and file offsets once the layout is stable. The result is a 1024-byte PE image: `Format: COFF-x86-64`, `Subsystem: IMAGE_SUBSYSTEM_WINDOWS_CUI`, `AddressOfEntryPoint: 0x1000`, `SizeOfHeaders: 512`, `SectionAlignment: 4096`, `FileAlignment: 512`.

## Importing Windows APIs

The import table describes the external function addresses the loader fills at startup. The order is: declare the `.idata` section, build the import collection, then let `format_pe_import_section` generate the table content. **Do not open `.idata` yourself and fill in import entries by hand** — the RVA relationships between the descriptors, the lookup table, the address table, the hint names, and the DLL name strings are derived by `format.inc`.

```asm id=pe64-imports target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        // The import section is declared first, then filled by the generator.
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)

// A slot defaults to the API name, so instructions can reference it directly.
let imports: map = format_pe_import_new()
format_pe_import_many_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "GetCurrentProcessId")
)
// The same binding takes further DLLs; pairs gives an API a local alias.
format_pe_import_pairs_mut(
    image,
    imports,
    "ADVAPI32.DLL",
    list.of("close_registry_key", "RegCloseKey")
)

format_begin(image)

format_section_begin(image, ".text")
start:
    // A Windows x64 call needs 32 bytes of shadow space, plus 8 to keep the stack 16-byte aligned.
    sub rsp, 40
    // PE64 calls through the RIP-relative import slot.
    call [rel GetCurrentProcessId]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text")

// Generate .idata here: do not open the same section around this call.
format_pe_import_section(image, ".idata", imports)

format_entry_mut(image, start)
format_finish(image)
```

This image is 1536 bytes, and the import directory holds two tables: `KERNEL32.DLL` with `ExitProcess` and `GetCurrentProcessId`, and `ADVAPI32.DLL` with `RegCloseKey`. The second table has no `close_registry_key` — the `pairs` form is "local slot name, real API name", and the local name only exists in the source.

Import helpers:

| Function | Parameters | Purpose |
| --- | --- | --- |
| `format_pe_import_new()` | none | create an empty import collection |
| `format_pe_import_many_mut(plan, imports, dll, names)` | configuration, collection, DLL name, name list | add a batch whose slot names match the API names |
| `format_pe_import_pairs_mut(plan, imports, dll, pairs)` | configuration, collection, DLL name, slot/name pairs | add a batch, giving each API a local slot name |
| `format_pe_import_section(plan, name, imports)` | configuration, declared import section, collection | write the import section and register its directory |

The `pairs` list must hold an even number of entries; more than 128 reports `PE64 import pairs exceed the batch limit`, and an odd count reports `PE64 import pairs require slot/name entries`. One slot name cannot point at two different functions; a conflict reports `PE import slot already maps to a different name`.

A PE64 call through an import slot is written `call [rel slot_name]`, and a PE32 call is written `call [slot_name]` — in 64-bit code the slot address is RIP-relative, in 32-bit code it is absolute.

## Exporting DLL Functions

A DLL export exposes an internal label as an external symbol. `many` exports a label under its own name and `pairs` assigns an explicit public name.

```asm id=pe64-dll-exports target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    // The DLL role sets IMAGE_FILE_DLL in the file header.
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".edata", format_exports | format_readable)
    )
)

let exports: list = format_pe_export_new()
// Two labels exported under their own names.
format_pe_export_many_mut(image, exports, list.of("x_add7", "x_sub3"))
// answer_impl exported as x_answer.
format_pe_export_pairs_mut(image, exports, list.of("answer_impl", "x_answer"))

format_begin(image)

format_section_begin(image, ".text")
dll_main:
    // A DLL entry returns nonzero to report a successful load.
    mov eax, 1
    ret
x_add7:
    lea eax, [ecx + 7]
    ret
x_sub3:
    lea eax, [ecx - 3]
    ret
answer_impl:
    mov eax, 42
    ret
format_section_end(image, ".text")

// The last argument is the DLL's own name, written into the export directory.
format_pe_export_section(image, ".edata", exports, "xirasm_demo.dll")

format_entry_mut(image, dll_main)
format_finish(image)
```

This image is 1536 bytes. The export table holds three exports, with ordinals starting at 1 and names in dictionary order (`x_add7`, `x_answer`, `x_sub3`) — the PE name pointer table has to be sorted, and `format.inc` sorts it. An empty export table reports `PE export table requires at least one export`, and an empty DLL name reports `PE export DLL name is empty`. The `pairs` list likewise needs an even number of entries, at most 128.

## Resources

A resource section holds a compiled `.res` tree — the output of `rc.exe` or `windres`, not a hand-written text file. Declare `.rsrc` as `format_resources`, then hand the file path to the generator:

```asm id=pe64-resources target=x86-64
import("format/format.inc")

// A PE with a resource section: .res is a compiled resource tree.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        // .rsrc must be declared with format_resources.
        format_section(".rsrc", format_resources | format_readable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    ret
format_section_end(image, ".text")

// Copy the tree and register the directory; do not open .rsrc around this call.
format_pe_resource_section(image, ".rsrc", "app.res")

format_entry_mut(image, start)
format_finish(image)
```

This image is 1536 bytes: `.rsrc` occupies 364 bytes, and the optional header's resource directory slot (data directory entry 3) is filled with `RVA = 0x2000`, `size = 364`.

`format_pe_resource_section(plan, name, path)` reorders the tree by **type / name / language**; the directories at each level, the name strings, and the offsets all come from `format.inc`, so the record order inside the `.res` file does not affect the result. A `.res` with no non-empty records reports `compiled PE resource file contains no non-empty records`.

The `path` is resolved relative to the directory of the code that reads it, and the code that reads the `.res` lives in `include/format/pe_resource.inc`. A relative path therefore resolves against `include/format/`, not against the source file and not against the working directory. To reach a `.res` beside your source, write the absolute path; otherwise the read reports `the file this statement reads cannot be opened (FileNotAvailable)`.

## Base Relocations

A base relocation describes "this slot in the file holds an absolute address, so the loader must adjust it when the image moves". It is not the same thing as a `rel` instruction reference: a `rel` reference encodes a displacement and needs no attention from the loader, while only an absolute address written into memory needs a relocation record.

```asm id=pe64-relocations target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    // ASLR is required, so a fixups section must be declared.
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".idata", format_imports | format_readable | format_writeable),
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)

let imports: map = format_pe_import_new()
format_pe_import_many_mut(image, imports, "KERNEL32.DLL", list.of("ExitProcess"))

format_begin(image)

format_section_begin(image, ".text")
start:
    // Reserve the Windows x64 shadow space before the calls.
    sub rsp, 40
    // Read the function address out of .data, then call it.
    mov rax, [rel worker_pointer]
    call rax
    mov ecx, eax
    call [rel ExitProcess]
worker:
    mov eax, 42
    ret
format_section_end(image, ".text")

format_section_begin(image, ".data")
// This slot holds an absolute address, so a moved image must correct it.
worker_pointer:
    dq(0)
format_section_end(image, ".data")

format_pe_import_section(image, ".idata", imports)

// The record names the slot itself, not the worker it points at.
let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, start)
format_finish(image)

// The absolute value is written only once every label address is stable.
defer {
    store.u64(worker_pointer, worker)
}
```

This image is 3072 bytes. The relocation directory points at `.reloc`, which holds one base relocation block: page RVA `0x2000`, block size 12 (an 8-byte block header, one 2-byte record, and a 2-byte terminator), record type 10, that is `IMAGE_REL_BASED_DIR64`, offset 0, together naming `worker_pointer`. `DYNAMIC_BASE` is set at the same time, which is what `format_pe_aslr_required` requires.

`format_pe_reloc_add_mut` picks the 32-bit or 64-bit relocation type from the configuration's width, so the type code is never written by hand. Records must reach `format_pe_reloc_section` in ascending RVA order. A PE32 slot is stored with `dd(0)` and backfilled with `store.u32`, and the same function selects the 32-bit type.

| Function | Parameters | Purpose |
| --- | --- | --- |
| `pe_reloc_new()` | none | create an empty relocation list |
| `format_pe_reloc_add_mut(plan, relocs, storage)` | configuration, list, address of the slot holding the absolute value | append one width-appropriate relocation record |
| `format_pe_reloc_section(plan, name, relocs)` | configuration, declared fixups section, sorted list | write the relocation section and register its directory |

### Watching the Loader Apply a Relocation

An executable rarely shows whether its relocations work: the loader maps it at the `ImageBase` written at link time and never reaches the adjustment. To observe the adjustment, build the same structure as a DLL and have a host read an absolute pointer back out of it:

```asm id=pe64-reloc-probe target=x86-64
import("format/format.inc")

// Store a function address in .data and read it back through an export, so a
// host can tell whether the loader adjusted it.
let image: map = format_pe64(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_required,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".edata", format_exports | format_readable),
        // format_pe_aslr_required requires a fixups section.
        format_section(".reloc", format_fixups | format_readable | format_discardable)
    )
)

format_begin(image)

format_section_begin(image, ".text")
dll_main:
    // A DLL entry returns nonzero to report a successful load.
    mov eax, 1
    ret
worker:
    // Returns a fixed value, proving what the pointer points at.
    mov eax, 42
    ret
read_pointer:
    // Hand the stored worker address back to the host.
    mov rax, [rel worker_pointer]
    ret
format_section_end(image, ".text")

// The slot holds worker's absolute address, which a moved image must correct.
format_section_begin(image, ".data")
worker_pointer:
    dq(0)
format_section_end(image, ".data")

let exports: list = format_pe_export_new()
format_pe_export_many_mut(image, exports, list.of("read_pointer"))
format_pe_export_section(image, ".edata", exports, "reloc_probe.dll")

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs)

format_entry_mut(image, dll_main)
format_finish(image)

// The absolute value is written only once every label address is stable.
defer {
    store.u64(worker_pointer, worker)
}
```

The host loads it, reads the stored address, and calls it:

```c
#include <windows.h>
#include <stdio.h>

int main(void) {
    HMODULE dll = LoadLibraryA("reloc_probe.dll");
    if (!dll) { printf("load failed: %lu\n", GetLastError()); return 2; }

    /* Read the stored address back and call it: this only succeeds when the
       loader rewrote the slot. */
    int (*read_pointer)(void) = (int (*)(void))GetProcAddress(dll, "read_pointer");
    long long stored = (long long)read_pointer();
    printf("DLL loaded at : %p\n", (void *)dll);
    printf("stored pointer: 0x%llX\n", stored);
    printf("worker() = %d\n", ((int (*)(void))stored)());
    return 0;
}
```

Place the DLL beside the host and run it; the output has this shape:

```text
DLL loaded at : 00007FFB4E3E0000
stored pointer: 0x7FFB4E3E1006
worker() = 42
```

The load address is not the `0x140000000` written at link time, so the image was moved. The address read back out of the slot lies inside the load address range, and calling it returns 42, so **the loader adjusted that absolute address according to `.reloc`**. Had the record named the wrong location, the read would have returned the stale link-time address and the call would have crashed.

## Checksum

A PE `CheckSum` covers the whole file, so it can only be computed once the file bytes are final:

```asm id=pe64-checksum target=x86-64
import("format/format.inc")

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_disabled,
    list.of(
        format_section(".text", format_code | format_readable | format_executable)
    )
)
format_begin(image)

format_section_begin(image, ".text")
start:
    xor eax, eax
    ret
format_section_end(image, ".text")

format_entry_mut(image, start)
format_finish(image)

// The checksum covers the final file bytes, so it is written last.
format_pe_checksum(image)
```

`format_pe_checksum` measures from the start of the first section to the end of the last, so at least one section must exist or it reports `PE checksum requires at least one section`. This image is 1024 bytes and its `CheckSum` field is `0x4A36`.
