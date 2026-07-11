import("../../include/format/coff.inc");

x86.use32();

const section_count: u16 = 1
const symbol_count: u64 = 2
const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 8
const symbol_table_foa: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const main_symbol_foa: u64 = coff_symbol_foa(symbol_table_foa, 1)
const string_table_foa: u64 = coff_string_table_foa(symbol_table_foa, symbol_count)

coff_begin32(section_count, symbol_table_foa, symbol_count);

coff_begin_section(".text", text_raw);
text_start:
main:
    mov eax, 42
    ret
text_end:
coff_end_section(text_raw_size);

region.begin(".symtab", 0, symbol_table_foa);
coff_symbol(coff_name_text, 0, 1, coff_sym_class_static, coff_sym_type_null);
coff_symbol(coff_name__main, main - text_start, 1, coff_sym_class_external, coff_sym_type_function);
coff_end_symbols(symbol_count);

coff_finalize_section(0, coff_name_text, text_raw_size, text_raw, coff_text_chars);

defer {

    assert(load.u16(region_base()) == coff_machine_i386);
    assert(load.u16(region_base() + 2) == section_count);
    assert(load.u32(region_base() + 8) == symbol_table_foa);
    assert(load.u32(region_base() + 12) == symbol_count);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_raw_ptr_foa) == text_raw);
    assert(main_symbol_foa < string_table_foa);
}
