// api-matrix-fixture: coff_finalize_section(
import("../../include/format/coff.inc");

const section_count: u16 = 2
const symbol_count: u64 = 3
const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 16
const rdata_raw: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const rdata_raw_size: u64 = 4
const symbol_table_foa: u64 = coff_next_foa(rdata_raw, rdata_raw_size, 4)
const main_symbol_foa: u64 = coff_symbol_foa(symbol_table_foa, 1)
const string_table_foa: u64 = coff_string_table_foa(symbol_table_foa, symbol_count)

coff_begin64(section_count, symbol_table_foa, symbol_count);

coff_begin_section(".text", text_raw);
text_start:
main:
    mov eax, 42
    ret
text_end:
coff_end_section(text_raw_size);

coff_begin_section(".rdata", rdata_raw);
rdata_start:
dd(7);
rdata_end:
coff_end_section(rdata_raw_size);

region.begin(".symtab", 0, symbol_table_foa);
coff_symbol(coff_name_text, 0, 1, coff_sym_class_static, coff_sym_type_null);
coff_symbol(coff_name_main, main - text_start, 1, coff_sym_class_external, coff_sym_type_function);
coff_symbol(coff_name_rdata, 0, 2, coff_sym_class_static, coff_sym_type_null);
coff_end_symbols(symbol_count);

coff_finalize_section(0, coff_name_text, text_raw_size, text_raw, coff_text_chars);
coff_finalize_section(1, coff_name_rdata, rdata_raw_size, rdata_raw, coff_rdata_chars);

defer {

    assert(load.u16(region_base()) == coff_machine_amd64);
    assert(load.u16(region_base() + 2) == section_count);
    assert(load.u32(region_base() + 8) == symbol_table_foa);
    assert(load.u32(region_base() + 12) == symbol_count);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_raw_ptr_foa) == text_raw);
    assert(load.u32(region_base() + coff_section_row_foa(1) + coff_sec_raw_ptr_foa) == rdata_raw);
    assert(main_symbol_foa < string_table_foa);
}
