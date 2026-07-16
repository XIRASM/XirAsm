# 4. COFF and ELF Object Files

Object files are not loaded directly by the operating system. They are
intermediate files for a linker. They describe sections, linker-visible symbols,
and fields that the linker must patch.

## COFF Object Template

```asm
import("format/format.inc");

// 64-bit COFF object for Windows/MSVC-style linkers.
let object: map = format_coff64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(object);

// .text contains a placeholder call displacement.
format_section_begin(object, ".text");
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    xor eax, eax
    ret
format_section_end(object, ".text");

format_section_begin(object, ".data");
data_start:
answer:
    dd(42);
format_section_end(object, ".data");

format_section_begin(object, ".bss");
bss_start:
scratch:
    rb(64);
format_section_end(object, ".bss");

// Declare public and external linker symbols.
const symbols: list = list.of(
    format_coff_public("main", ".text", text_start, main, coff_sym_type_function),
    format_coff_public("answer", ".data", data_start, answer, coff_sym_type_null),
    format_coff_public("scratch", ".bss", bss_start, scratch, coff_sym_type_null),
    format_coff_extern("puts", coff_sym_type_function)
)

// The linker will patch call_disp with a 32-bit relative call displacement.
const relocs: list = list.of(
    format_coff_reloc(".text", text_start, call_disp, "puts", coff_rel_amd64_rel32)
)
format_coff_tables_mut(object, symbols, relocs)
format_finish(object);
```

Common COFF relative call relocations:

| Width | Relocation |
| --- | --- |
| 32-bit | `coff_rel_i386_rel32` |
| 64-bit | `coff_rel_amd64_rel32` |

## ELF Object Template

```asm
import("format/format.inc");

let object: map = format_elfobj64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".rodata", format_data | format_readable)
    )
)
format_begin(object);

format_section_begin(object, ".text");
text_start:
_start:
    db(0xe8);
call_disp:
    dd(0);
    xor eax, eax
    ret
format_section_end(object, ".text");

format_section_begin(object, ".bss");
bss_start:
scratch:
    reserve(64);
format_section_end(object, ".bss");

format_section_begin(object, ".rodata");
data_start:
answer:
    dd(42);
format_section_end(object, ".rodata");

// ELF public symbols need name, section, section start, address, size, and type.
const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 8, elfobj_stt_func),
    format_elfobj_public("scratch", ".bss", bss_start, scratch, 64, elfobj_stt_object),
    format_elfobj_public("answer", ".rodata", data_start, answer, 4, elfobj_stt_object),
    format_elfobj_extern("puts", elfobj_stt_func)
)

// x86-64 PLT calls commonly use R_X86_64_PLT32 with addend -4.
const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_disp, "puts", elf_r_x86_64_plt32, 0xfffffffffffffffc)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

For ELF32, use `format_elfobj32`. A common 32-bit relative call relocation is
`elf_r_386_pc32`.

## Object Call Summary

| Family | Function | Use |
| --- | --- | --- |
| COFF | `format_coff32(sections)` / `format_coff64(sections)` | create an object plan |
| COFF | `format_coff_public(name, section_name, section_start, address, sym_type)` | define a public symbol |
| COFF | `format_coff_extern(name, sym_type)` | declare an external symbol |
| COFF | `format_coff_reloc(section_name, section_start, address, symbol_name, reloc_type)` | declare a relocation field |
| COFF | `format_coff_tables_mut(plan, symbols, relocs)` | attach symbol and relocation tables |
| ELF | `format_elfobj32(sections)` / `format_elfobj64(sections)` | create an object plan |
| ELF | `format_elfobj_public(name, section_name, section_start, address, symbol_size, symbol_type)` | define a public symbol |
| ELF | `format_elfobj_extern(name, symbol_type)` | declare an external symbol |
| ELF | `format_elfobj_reloc(section_name, section_start, address, symbol_name, reloc_type, addend)` | declare a relocation field |
| ELF | `format_elfobj_tables_mut(plan, symbols, relocs)` | attach symbol and relocation tables |

The relocation field is the bytes the linker will patch. Emit a placeholder
first, then describe that placeholder with `format_*_reloc`.
