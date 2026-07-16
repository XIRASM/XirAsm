import("format/format.inc");

let object: map = format_elfobj64(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable),
        format_section(".rodata.long", format_data | format_readable)
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

format_section_begin(object, ".rodata.long");
data_start:
answer:
    dd(42);
format_section_end(object, ".rodata.long");

const symbols: list = list.of(
    format_elfobj_public("_start", ".text", text_start, _start, 8, elfobj_stt_func),
    format_elfobj_public("scratch", ".bss", bss_start, scratch, 64, elfobj_stt_object),
    format_elfobj_public("answer", ".rodata.long", data_start, answer, 4, elfobj_stt_object),
    format_elfobj_extern("puts", elfobj_stt_func)
)
const relocs: list = list.of(
    format_elfobj_reloc(".text", text_start, call_disp, "puts", elf_r_x86_64_plt32, 0xfffffffffffffffc)
)
format_elfobj_tables_mut(object, symbols, relocs)
format_finish(object);
