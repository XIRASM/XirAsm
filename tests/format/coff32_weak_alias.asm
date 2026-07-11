import("../../include/format/coff.inc");

x86.use32();

const section_count: u16 = 1
const symbol_count: u64 = 5
const reloc_count: u64 = 1
const text_raw: u64 = coff_first_raw_foa(section_count)
const text_raw_size: u64 = 16
const reloc_table_foa: u64 = coff_next_foa(text_raw, text_raw_size, 4)
const symbol_table_foa: u64 = coff_next_foa(reloc_table_foa, reloc_count * coff_reloc_size, 4)
const string_table_foa: u64 = coff_string_table_foa(symbol_table_foa, symbol_count)
const coff_name_fallback: u64 = 0x006b626c6c61665f
const coff_name_weakfn: u64 = 0x006e666b6165775f

coff_begin32(section_count, symbol_table_foa, symbol_count);

coff_begin_section(".text", text_raw);
text_start:
main:
    db(0xe8);
call_disp:
    dd(0);
    ret
fallback:
    mov eax, 42
    ret
    db(0x90, 0x90, 0x90, 0x90);
text_end:
coff_end_section(text_raw_size);

region.begin(".reloc.text", 0, reloc_table_foa);
coff_reloc_i386_rel32_at(text_start, call_disp, 3);

region.begin(".symtab", 0, symbol_table_foa);
coff_static(coff_name_text, 0, 1, coff_sym_type_null);
coff_public(coff_name__main, main - text_start, 1, coff_sym_type_function);
coff_public(coff_name_fallback, fallback - text_start, 1, coff_sym_type_function);
coff_weak_external_alias(coff_name_weakfn, 2, coff_sym_type_function);
coff_end_symbols(symbol_count);

coff_finalize_section_reloc(0, coff_name_text, text_raw_size, text_raw, reloc_table_foa, reloc_count, coff_text_chars);

defer {
    assert(load.u32(region_base() + 12) == symbol_count);
    assert(load.u32(region_base() + coff_section_row_foa(0) + coff_sec_reloc_ptr_foa) == reloc_table_foa);
    assert(load.u16(region_base() + coff_section_row_foa(0) + coff_sec_reloc_count_foa) == reloc_count);
    assert(string_table_foa == 178);
}
