# 2. Windows PE and DLLs

Windows programs use PE files. A PE configuration says whether the file is an executable
or DLL, which subsystem it uses, which safety flags are enabled, whether ASLR is
allowed or required, and which sections must be loaded.

## PE Options

`format_pe32(options, sections)` and `format_pe64(options, sections)` require
one role, one subsystem, and one ASLR policy. Add `format_pe_nx` when desired.

| Group | Value | Meaning |
| --- | --- | --- |
| role | `format_pe_exe` | executable |
| role | `format_pe_dll` | dynamic library |
| subsystem | `format_pe_console` | console program |
| subsystem | `format_pe_gui` | GUI program |
| safety | `format_pe_nx` | NX-compatible image |
| ASLR | `format_pe_aslr_auto` | enable ASLR when relocation data exists |
| ASLR | `format_pe_aslr_required` | require ASLR and relocation data |
| ASLR | `format_pe_aslr_disabled` | disable ASLR |

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

## Minimal PE64 Executable

```asm
import("format/format.inc");

// PE64 console executable with NX and automatic ASLR policy.
let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(image);

// Entry code.
format_section_begin(image, ".text");
start:
    xor eax, eax
    ret
format_section_end(image, ".text");

// BSS has memory size but no initialized file payload.
format_section_begin(image, ".bss");
    rb(64);
format_section_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

## Imports

Imports describe external function addresses that the Windows loader fills at
startup. Declare imports first, then call `format_pe_import_section` to generate
`.idata`.

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".idata", format_imports | format_readable | format_writeable)
    )
)
// One call can add several APIs whose local IAT labels match their API names.
let imports: map = format_pe_import_new()
format_pe_import_many_mut(
    image,
    imports,
    "KERNEL32.DLL",
    list.of("ExitProcess", "GetCurrentProcessId")
)
// Call the mutator again for another DLL. pairs also gives an API a local alias.
format_pe_import_pairs_mut(
    image,
    imports,
    "ADVAPI32.DLL",
    list.of("close_registry_key", "RegCloseKey")
)
format_begin(image);

format_section_begin(image, ".text");
start:
    // Windows x64 calls need 32 bytes of shadow space.
    sub rsp, 40
    // PE64 calls through the RIP-relative import slot.
    call [rel GetCurrentProcessId]
    xor ecx, ecx
    call [rel ExitProcess]
format_section_end(image, ".text");

// Generate .idata. Do not open .idata manually around this call.
format_pe_import_section(image, ".idata", imports);

format_entry_mut(image, start)
format_finish(image);
```

Import helpers:

| Function | Parameters | Use |
| --- | --- | --- |
| `format_pe_import_new()` | none | create an empty import map |
| `format_pe_import_many_mut(image, imports, dll, names)` | image config, map, DLL, list | add matching-name PE32/PE64 imports |
| `format_pe_import_pairs_mut(image, imports, dll, pairs)` | image config, map, DLL, slot/name list | add PE32/PE64 imports with local labels |
| `format_pe_import_section(image, name, imports)` | image config, import section name, map | generate the import section |

Call a grouped mutator once per DLL. Reusing the same `imports` binding builds
one `.idata` section containing all DLLs and APIs. For PE64 calls, use
`call [rel slot_name]`. For PE32 calls, use `call [slot_name]`.

## Exports

DLL exports map internal labels to public symbol names. `many` exports labels
under their existing names; `pairs` assigns explicit public names.

```asm
import("format/format.inc");

let image: map = format_pe64(
    format_pe_dll | format_pe_console | format_pe_nx | format_pe_aslr_auto,
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".edata", format_exports | format_readable)
    )
)
let exports: list = format_pe_export_new()
// Export two labels without renaming them.
format_pe_export_many_mut(image, exports, list.of("x_add7", "x_sub3"))
// Export answer_impl under the public name x_answer.
format_pe_export_pairs_mut(image, exports, list.of("answer_impl", "x_answer"))
format_begin(image);

format_section_begin(image, ".text");
dll_main:
    // A minimal DLL entry returns TRUE.
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
format_section_end(image, ".text");

format_pe_export_section(image, ".edata", exports, "xirasm_demo.dll");

format_entry_mut(image, dll_main)
format_finish(image);
```

## Resources

Pass a prepared `.res` file to the resource section generator:

```text
// .rsrc must be declared with format_resources.
format_pe_resource_section(image, ".rsrc", "data/app.res");
```

| Function | Parameters | Use |
| --- | --- | --- |
| `format_pe_resource_section(image, name, path)` | image config, declared resource section, `.res` path | copy a compiled resource tree and register the PE resource directory |

## Base Relocations

Base relocations mark stored absolute addresses that the loader must adjust
when ASLR moves the image. This complete PE64 example stores a function pointer
in `.data` and requires a matching relocation in `.reloc`:

```asm
import("format/format.inc");

let image: map = format_pe64(
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
format_begin(image);

format_section_begin(image, ".text");
start:
    // Reserve Windows x64 shadow space and align the stack for both calls.
    sub rsp, 40
    // Loading the slot uses a relative instruction reference.
    mov rax, [rel worker_pointer]
    call rax
    // ExitProcess makes the example's runtime result explicit.
    mov ecx, eax
    call [rel ExitProcess]
worker:
    mov eax, 42
    ret
format_section_end(image, ".text");

format_section_begin(image, ".data");
worker_pointer:
    // The stored pointer is absolute, so the loader must relocate this slot.
    dq(0);
format_section_end(image, ".data");

format_pe_import_section(image, ".idata", imports);

let relocs: list = pe_reloc_new()
format_pe_reloc_add_mut(image, relocs, worker_pointer)
format_pe_reloc_section(image, ".reloc", relocs);

format_entry_mut(image, start)
format_finish(image);

// Backfill the absolute value only after all label addresses are stable.
defer {
    store.u64(worker_pointer, worker);
}
```

`format_pe_reloc_add_mut` chooses the PE32 or PE64 relocation kind from the image
configuration.
Its address argument is the storage location that contains the pointer, not the
pointer target. Pass records to `format_pe_reloc_section` in ascending RVA
order. A `rel` instruction reference is already position-relative and does not
need a base relocation. For PE32, use `dd(0)` and `store.u32`; the same mutator
selects the 32-bit relocation kind.

| Function | Parameters | Use |
| --- | --- | --- |
| `pe_reloc_new()` | none | create an empty relocation list |
| `format_pe_reloc_add_mut(image, relocs, storage)` | image config, list, pointer storage address | append the width-appropriate base relocation |
| `format_pe_reloc_section(image, name, relocs)` | image config, declared relocation section, sorted list | generate `.reloc` and register its data directory |

## Checksum

Call `format_pe_checksum(image)` after `format_finish(image)` when you need the
PE checksum field:

```text
// The checksum depends on final file bytes, so write it last.
format_pe_checksum(image);
```

`format_pe_checksum(image)` takes the finished PE configuration and backfills
the checksum field from the final file bytes.
