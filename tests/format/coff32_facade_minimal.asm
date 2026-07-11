// api-matrix-fixture: coff32_obj(
// api-matrix-fixture: coff32_section(
// api-matrix-fixture: coff32_end_section(
// api-matrix-fixture: coff32_symbols(
// api-matrix-fixture: coff32_finish_section(
// api-matrix-fixture: coff32_rx

import("../../include/format/coff32.inc");

x86.use32();

const section_count: u16 = 1
const symbol_count: u64 = 2
const text_raw: u64 = coff_first_raw_foa(section_count)

coff32_obj(section_count, symbol_count);

coff32_section(".text");
text_start:
main:
    mov eax, 42
    ret
text_end:
coff32_end_section();

coff32_symbols();
symbol_table_start:
coff_symbol(coff_name_text, 0, 1, coff_sym_class_static, coff_sym_type_null);
coff_symbol(coff_name__main, main - text_start, 1, coff_sym_class_external, coff_sym_type_function);
coff_end_symbols(symbol_count);

coff32_finish_section(0, coff_name_text, text_start, coff32_rx);

defer {
    assert(load.u16(region_base()) == coff_machine_i386);
    assert(load.u16(region_base() + 2) == section_count);
    assert(load.u32(region_base() + 8) == region_file_offset(symbol_table_start));
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_raw_ptr_foa) == text_raw);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_raw_size_foa) == region_file_size(text_start));
}
