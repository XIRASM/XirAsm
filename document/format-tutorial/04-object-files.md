# 4. COFF and ELF Object Files

Object files are not loaded by the operating system. They are the intermediate
form a linker consumes: sections, linker-visible symbols, and placeholder
fields that the linker patches later. `format.inc` emits COFF32, COFF64,
ELF32, ELF64 for x86-64 and AArch64, and Mach-O 64 relocatable objects through
one shared workflow.

Object files have no entry point, so never call `format_entry_mut`. The
workflow is always the same:

1. Declare the sections.
2. Emit placeholder bytes and real data into each section.
3. Describe the linker-visible labels in a symbol list.
4. Describe the placeholders in a relocation list.
5. Attach both lists with a `format_*_tables_mut` call, then finish.

## COFF Object Template

COFF objects support `format_code`, `format_data`, and
`format_uninitialized_data` sections. Section names must fit in eight bytes.

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

`format_coff_public` takes the symbol label and the start label of the section
that contains it; the emitted symbol value is their difference. A relocation
address is the placeholder the linker patches — `call_disp` above is the
4-byte displacement of `call rel32`.

Common COFF relative call relocations:

| Width | Relocation |
| --- | --- |
| 32-bit | `coff_rel_i386_rel32` |
| 64-bit | `coff_rel_amd64_rel32` |

## ELF Object Template

ELF objects support code, data, and BSS sections. ELF section names may be
longer than eight bytes.

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

ELF64 relocations are RELA records with an explicit addend. The `call rel32`
addend of `-4` (`0xfffffffffffffffc`) is the size of the displacement field
itself, following the x86-64 psABI.

### Choosing the ELF Machine

| Constructor | `e_machine` | Notes |
| --- | --- | --- |
| `format_elfobj32(sections)` | `EM_386` | switches the assembler to 32-bit x86 text mode |
| `format_elfobj64(sections)` | `EM_X86_64` | switches the assembler to 64-bit x86 text mode |
| `format_elfobj64_aarch64(sections)` | `EM_AARCH64` | arm64 Linux and BSD targets |
| `format_elfobj64_machine(sections, machine)` | explicit | accepts `elf_machine_x86_64` or `elf_machine_aarch64` |

The AArch64 form does not select any x86 text mode. Emit A64 instruction words
as data — with `emit.u32` or the AArch64 DSL layer — and attach AArch64
relocation types from `elf_const.inc`:

```asm
const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 16, elfobj_stt_func),
    format_elfobj_public("answer", ".data", data_start, answer, 8, elfobj_stt_object),
    format_elfobj_extern("printf", elfobj_stt_func)
)

// Each reloc describes the placeholder word or pointer field that the
// linker patches; the addend is explicit because AArch64 uses RELA.
const relocs: list = list.of(
    // bl printf: R_AARCH64_CALL26.
    format_elfobj_reloc(".text", text_start, call_site, "printf", elf_r_aarch64_call26, 0),
    // adrp x0, answer: page-base part.
    format_elfobj_reloc(".text", text_start, page_site, "answer", elf_r_aarch64_adr_prel_pg_hi21, 0),
    // add x0, x0, :lo12:answer: low-12-bit part.
    format_elfobj_reloc(".text", text_start, lo12_site, "answer", elf_r_aarch64_add_abs_lo12_nc, 0),
    // .xword printf: R_AARCH64_ABS64.
    format_elfobj_reloc(".data", data_start, ptr_slot, "printf", elf_r_aarch64_abs64, 0)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
```

`elf_const.inc` provides the common AArch64 types: `elf_r_aarch64_abs64`,
`elf_r_aarch64_abs32`, `elf_r_aarch64_adr_prel_lo21`,
`elf_r_aarch64_adr_prel_pg_hi21`, `elf_r_aarch64_add_abs_lo12_nc`,
the `elf_r_aarch64_ldst{8,16,32,64}_abs_lo12_nc` set,
`elf_r_aarch64_condbr19`, `elf_r_aarch64_jump26`, `elf_r_aarch64_call26`, and
the GOT forms `elf_r_aarch64_adr_got_page` plus
`elf_r_aarch64_ld64_got_lo12_nc`. An `adrp`/`add` pair targeting the same
symbol uses the page relocation and the low-12-bit relocation together.

For ELF32, use `format_elfobj32`. A common 32-bit relative call relocation is
`elf_r_386_pc32`.

## Mach-O Objects

`format_macho64_object(target, sections)` builds an `MH_OBJECT` relocatable
file for the selected CPU target (see [macOS Mach-O](06-macos-macho.md)). It
shares the section lifecycle with the templates above and manages the symbol
table, relocations, and `LC_SYMTAB` automatically once you attach tables with
`format_macho64_tables_mut`. Object symbols and relocations use
`format_macho64_public`, `format_macho64_extern`, `format_macho64_reloc`, and
the ISA convenience `format_macho64_arm64_reloc`; the summary table below
lists their signatures, and the Mach-O chapter shows a complete object.

## Object Call Summary

| Family | Function | Use |
| --- | --- | --- |
| COFF | `format_coff32(sections)` / `format_coff64(sections)` | create an object configuration |
| COFF | `format_coff_public(name, section_name, section_start, address, sym_type)` | define a public symbol |
| COFF | `format_coff_extern(name, sym_type)` | declare an external symbol |
| COFF | `format_coff_reloc(section_name, section_start, address, symbol_name, reloc_type)` | declare a relocation field |
| COFF | `format_coff_tables_mut(object, symbols, relocs)` | attach symbol and relocation tables |
| ELF | `format_elfobj32(sections)` / `format_elfobj64(sections)` | create an x86 object configuration |
| ELF | `format_elfobj64_aarch64(sections)` | create an AArch64 object configuration |
| ELF | `format_elfobj64_machine(sections, machine)` | create an object configuration with an explicit machine |
| ELF | `format_elfobj_public(name, section_name, section_start, address, symbol_size, symbol_type)` | define a public symbol |
| ELF | `format_elfobj_extern(name, symbol_type)` | declare an external symbol |
| ELF | `format_elfobj_reloc(section_name, section_start, address, symbol_name, reloc_type, addend)` | declare a relocation field |
| ELF | `format_elfobj_tables_mut(object, symbols, relocs)` | attach symbol and relocation tables |
| Mach-O | `format_macho64_object(target, sections)` | create a Mach-O object configuration |
| Mach-O | `format_macho64_target_arm64(minos, sdk)` / `format_macho64_target_x86_64(minos, sdk)` | select the CPU target and macOS version |
| Mach-O | `format_macho64_public(name, section_name, section_start, address, symbol_type)` | define a public symbol |
| Mach-O | `format_macho64_extern(name)` | declare an external symbol |
| Mach-O | `format_macho64_reloc(section_name, section_start, address, symbol_name, pcrel, length, reloc_type)` | declare a relocation field |
| Mach-O | `format_macho64_arm64_reloc(section_name, section_start, address, symbol_name, reloc_type)` | declare an AArch64 relocation field with derived `pcrel`/`length` |
| Mach-O | `format_macho64_tables_mut(object, symbols, relocs)` | attach symbol and relocation tables |

The relocation field is the bytes the linker will patch. Emit a placeholder
first, then describe that placeholder with `format_*_reloc`.
