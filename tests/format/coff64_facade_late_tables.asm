// api-matrix-fixture: coff64_finish_section_reloc(
// api-matrix-fixture: late_layout {

import("../../include/format/coff64.inc");

const section_count: u16 = 1
const symbol_count: u64 = 3
const reloc_count: u64 = 1
const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 8
const reloc_table_foa: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const string_size: u64 = coff_string_table_min_size

coff64_obj(section_count, symbol_count);

coff64_section(".text");
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    ret
    reserve(16);
text_end:
coff64_end_section();

virtual.begin(0);
reloc_scratch:
coff_reloc_amd64_rel32_at(text_start, call_disp, 2);
reloc_scratch_end:
virtual.end();

virtual.begin(0);
symbol_scratch:
coff_static(coff_name_text, 0, 1, coff_sym_type_null);
coff_public(coff_name_main, main - text_start, 1, coff_sym_type_function);
coff_extrn(coff_name_puts, coff_sym_type_function);
virtual.end();

virtual.begin(0);
string_scratch:
emit.u32(string_size);
virtual.end();

coff64_finish_section_reloc(0, coff_name_text, text_start, reloc_table_foa, reloc_count, coff_rx);

late_layout {
    region.begin(".coff.tables", 0, reloc_table_foa);
    emit.bytes(load.bytes(reloc_scratch, reloc_count * coff_reloc_size));
    align(4);
    store.u32(coff_file + 8, file_cursor_real());
    store.u32(coff_file + 12, symbol_count);
    emit.bytes(load.bytes(symbol_scratch, symbol_count * coff_symbol_size));
    emit.bytes(load.bytes(string_scratch, string_size));
}

defer {
    assert(load.u16(coff_file) == coff_machine_amd64);
    assert(load.u16(coff_file + 2) == section_count);
    assert(load.u32(coff_file + 8) == coff_align_up(reloc_table_foa + reloc_count * coff_reloc_size, 4));
    assert(load.u32(coff_file + 12) == symbol_count);
    assert(load.u32(coff_sections + coff_sec_raw_size_foa) == text_raw_size);
    assert(load.u32(coff_sections + coff_sec_raw_ptr_foa) == text_raw);
    assert(load.u32(coff_sections + coff_sec_reloc_ptr_foa) == reloc_table_foa);
    assert(load.u16(coff_sections + coff_sec_reloc_count_foa) == reloc_count);
    assert(coff_reloc_count(reloc_scratch, reloc_scratch_end) == reloc_count);
    assert(region_file_size(text_start) == text_raw_size);
    assert(region_logical_size(text_start) == text_end - text_start);
}
