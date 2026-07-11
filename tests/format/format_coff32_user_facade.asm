import("format/format.inc");

const object0: map = format_coff32(
    list.of(
        format_section(".text", format_code | format_readable | format_executable),
        format_section(".data", format_data | format_readable | format_writeable),
        format_section(".bss", format_uninitialized_data | format_readable | format_writeable)
    )
)
format_begin(object0);

format_section_begin(object0, ".text");
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    xor eax, eax
    ret
format_section_end(object0, ".text");

format_section_begin(object0, ".data");
data_start:
answer:
    dd(42);
format_section_end(object0, ".data");

format_section_begin(object0, ".bss");
bss_start:
scratch:
    rb(64);
format_section_end(object0, ".bss");

const symbols: list = list.of(
    format_coff_public("_main", ".text", text_start, main, coff_sym_type_function),
    format_coff_public("answer", ".data", data_start, answer, coff_sym_type_null),
    format_coff_public("scratch", ".bss", bss_start, scratch, coff_sym_type_null),
    format_coff_extern("_puts", coff_sym_type_function)
)
const relocs: list = list.of(
    format_coff_reloc(".text", text_start, call_disp, "_puts", coff_rel_i386_rel32)
)
const object: map = format_coff_tables(object0, symbols, relocs)
format_finish(object);

defer {
    assert(load.u16(region_base()) == coff_machine_i386);
    assert(load.u16(region_base() + 2) == 3);
    assert(load.u32(region_base() + 12) == 4);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_reloc_ptr_foa) != 0);
    assert(load.u16(region_base() + coff_section_row_foa(0) + coff_sec_reloc_count_foa) == 1);
    assert(load.u32(region_base() + coff_section_row_foa(2) + coff_sec_raw_size_foa) == 64);
    assert(load.u32(region_base() + coff_section_row_foa(2) + coff_sec_raw_ptr_foa) == 0);
}
