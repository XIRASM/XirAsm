# 3. Linux ELF Executables and Shared Objects

ELF images describe loadable segments. A loadable segment has file offsets,
virtual addresses, file size, memory size, and permissions. `format.inc`
derives those fields from named segments.

## ELF Executable

Use `format_elf_exec` for a normal fixed-address executable:

```asm
import("format/format.inc");

// Three load segments: code, initialized data, and BSS.
let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable),
        format_segment(".bss", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
answer:
    dd(42);
format_segment_end(image, ".data");

format_segment_begin(image, ".bss");
scratch:
    rb(128);
format_segment_end(image, ".bss");

format_entry_mut(image, start)
format_finish(image);
```

For ELF32, use `format_elf32(format_elf_exec, segments)`. `format.inc` does not
provide an ELF32 PIE entry point.

## ELF64 PIE

Use `format_elf_pie` for a position-independent executable:

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_pie,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".bss", format_load | format_readable | format_writeable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    // Both label references remain valid when the loader moves the PIE.
    lea rbx, [rel scratch]
    lea rsi, [rel message]
    mov dword [rbx], 0x5a
    mov eax, 60
    xor edi, edi
    syscall
format_segment_end(image, ".text");

format_segment_begin(image, ".bss");
scratch:
    rb(64);
format_segment_end(image, ".bss");

format_segment_begin(image, ".rodata");
message:
    db("XIRASM PIE", 0);
format_segment_end(image, ".rodata");

format_entry_mut(image, start)
format_finish(image);
```

The instructions must also be position-independent where the ISA requires it.
For x86-64, use `rel` references for labels in the same image. They encode a
relative displacement, so they do not need an absolute dynamic relocation. An
absolute pointer stored in a PIE or shared object does require a dynamic
relocation; arbitrary user pointer relocations require direct ELF construction.

## ELF64 Executable Imports

ELF64 fixed-address executables can call external functions through PLT-style
entries:

```asm
import("format/format.inc");

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

// Add several APIs from libc. format.inc derives <name>_gotplt and <name>_plt.
let imports: list = format_elfexe_import_new()
format_elfexe_import_many_mut(imports, "libc.so.6", list.of("getpid", "getppid"))
// Add another library and give cos a different local prefix.
format_elfexe_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfexe_tables_mut(image, imports)
format_begin(image);

format_segment_begin(image, ".text");
start:
    call getpid_plt
    call getppid_plt
    xor edi, edi
    mov eax, 60
    syscall
format_segment_end(image, ".text");

format_entry_mut(image, start)
format_finish(image);
```

Call a grouped mutator once per library and keep using the same `imports` list.
`format.inc` creates the dynamic segment, PLT, GOT, and related relocations. In
the example, the aliased import is available as `cos_fn_plt` and
`cos_fn_gotplt`.

## ELF64 Shared Object

Shared objects do not use the normal executable entry workflow. They expose
dynamic symbols and may also import symbols.

```asm
import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_demo.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable)
    )
)

let exports: list = format_elfso_export_new()
// Export two four-byte functions under their label names.
format_elfso_export_many_mut(exports, list.of("x_add7", "x_sub3"), ".text", 4)
// Export answer_impl under a different public name.
format_elfso_export_pairs_mut(exports, list.of("answer_impl", "x_answer"), ".text", 6)
format_elfso_tables_mut(image, exports, list.new())
format_begin(image);

format_segment_begin(image, ".text");
x_add7:
    lea eax, [rdi + 7]
    ret
x_sub3:
    lea eax, [rdi - 3]
    ret
answer_impl:
    mov eax, 42
    ret
format_segment_end(image, ".text");

format_finish(image);
```

## ELF64 Shared Object Imports

A shared object can collect imports from several libraries in the same way:

```asm
import("format/format.inc");

let image: map = format_elf64_so(
    "libxirasm_report.so",
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)

let exports: list = format_elfso_export_new()
format_elfso_export_pairs_mut(exports, list.of("report_impl", "x_report"), ".text", 18)

let imports: list = format_elfso_import_new()
// Two APIs from libc use matching local names.
format_elfso_import_many_mut(imports, "libc.so.6", list.of("puts", "getpid"))
// A second library maps cos to the local prefix cos_fn.
format_elfso_import_pairs_mut(imports, "libm.so.6", list.of("cos_fn", "cos"))
format_elfso_tables_mut(image, exports, imports)
format_begin(image);

format_segment_begin(image, ".text");
report_impl:
    lea rdi, [rel message]
    call puts_plt
    call getpid_plt
    ret
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
message:
    db("XIRASM shared object", 0);
format_segment_end(image, ".data");

format_finish(image);
```

The generated `cos_fn_plt` and `cos_fn_gotplt` labels are available even when
the example does not call them. Internal data references use `rel`; imported
calls use the generated PLT labels.

## ELF Call Summary

| Function | Use |
| --- | --- |
| `format_elf32(format_elf_exec, segments)` | ELF32 executable |
| `format_elf64(format_elf_exec, segments)` | ELF64 fixed executable |
| `format_elf64(format_elf_pie, segments)` | ELF64 PIE |
| `format_elf64_so(soname, segments)` | ELF64 shared object |
| `format_elfexe_import_new()` | empty ELF64 executable import list |
| `format_elfexe_import_many_mut(imports, library, names)` | grouped ELF64 executable PLT/GOT imports |
| `format_elfexe_import_pairs_mut(imports, library, pairs)` | ELF64 executable local-name/import-name pairs |
| `format_elfexe_tables_mut(image, imports)` | attach executable import metadata |
| `format_elfso_export_new()` | empty shared-object export list |
| `format_elfso_export_many_mut(exports, names, segment, size)` | grouped shared-object exports |
| `format_elfso_export_pairs_mut(exports, pairs, segment, size)` | shared-object target/name export pairs |
| `format_elfso_import_new()` | empty shared-object import list |
| `format_elfso_import_many_mut(imports, library, names)` | grouped shared-object PLT/GOT imports |
| `format_elfso_import_pairs_mut(imports, library, pairs)` | shared-object local-name/import-name pairs |
| `format_elfso_tables_mut(image, exports, imports)` | attach shared-object dynamic metadata |
