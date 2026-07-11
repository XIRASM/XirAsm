// api-matrix-fixture: coff_finalize_section_reloc(
// api-matrix-fixture: coff_reloc_amd64_addr64_at(
// api-matrix-fixture: coff_reloc_amd64_addr32_at(
// api-matrix-fixture: coff_reloc_amd64_addr32nb_at(
// api-matrix-fixture: coff_reloc_amd64_rel32_at(
import("../../include/format/coff.inc");

const section_count: u16 = 1
const symbol_count: u64 = 3
const reloc_count: u64 = 1
const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 8
const reloc_table_foa: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const symbol_table_foa: u64 = coff_next_foa(reloc_table_foa, reloc_count * coff_reloc_size, 4)
const string_table_foa: u64 = coff_string_table_foa(symbol_table_foa, symbol_count)

coff_begin64(section_count, symbol_table_foa, symbol_count);

coff_begin_section(".text", text_raw);
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    ret
    db(0x90, 0x90);
text_end:
coff_end_section(text_raw_size);

region.begin(".reloc.text", 0, reloc_table_foa);
reloc_start:
coff_reloc_amd64_rel32_at(text_start, call_disp, 2);
reloc_end:

region.begin(".symtab", 0, symbol_table_foa);
coff_static(coff_name_text, 0, 1, coff_sym_type_null);
coff_public(coff_name_main, main - text_start, 1, coff_sym_type_function);
coff_extrn(coff_name_puts, coff_sym_type_function);
coff_end_symbols(symbol_count);

coff_finalize_section_reloc(0, coff_name_text, text_raw_size, text_raw, reloc_table_foa, reloc_count, coff_text_chars);

defer {

    assert(load.u16(region_base()) == coff_machine_amd64);
    assert(load.u16(region_base() + 2) == section_count);
    assert(load.u32(region_base() + 8) == symbol_table_foa);
    assert(load.u32(region_base() + 12) == symbol_count);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_reloc_ptr_foa) == reloc_table_foa);
    assert(load.u16(region_base() + coff_section_row_foa(0) + coff_sec_reloc_count_foa) == reloc_count);
    assert(coff_reloc_count(reloc_start, reloc_end) == reloc_count);
    assert(coff_reloc_offset(text_start, call_disp) == 1);
    assert(coff_reloc_foa(reloc_table_foa, 0) < symbol_table_foa);
    assert(coff_reloc_table_end_foa(reloc_table_foa, reloc_count) < symbol_table_foa);
    assert(string_table_foa == 134);
}
