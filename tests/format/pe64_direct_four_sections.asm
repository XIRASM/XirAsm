import("../../include/format/pe.inc");

const section_count: u16 = 4
const headers_size: u64 = align_up(
    pe_section_table_foa + section_count * pe_section_header_size,
    pe_default_file_align
)

pe_begin64();
pe_headers64(section_count);

pe_begin_section_at(".text", 0, 0x1000, headers_size);
text_start:
emit.u8(1);
pe_align_section_file(0);

pe_begin_section_at(".rdata", 1, 0x2000, headers_size + 0x200);
rdata_start:
emit.u8(2);
pe_align_section_file(1);

pe_begin_section_at(".data", 2, 0x3000, headers_size + 0x400);
data_start:
emit.u8(3);
pe_align_section_file(2);

pe_begin_section_at(".reloc", 3, 0x4000, headers_size + 0x600);
reloc_start:
emit.u8(4);
pe_align_section_file(3);

pe_finalize_section64_auto(0, pe_name_text, text_start, pe_text_chars);
pe_finalize_section64_auto(1, pe_name_rdata, rdata_start, pe_rdata_chars);
pe_finalize_section64_auto(2, pe_name_data, data_start, pe_data_chars);
pe_finalize_section64_auto(3, pe_name_reloc, reloc_start, pe_reloc_chars);

defer {
    assert(load.u32(region_base() + pe_opt_size_of_headers_foa) == 0x400);
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) == 0x400);
    assert(load.u32(region_base() + pe_row_foa(3) + pe_sec_raw_ptr_foa) == 0xa00);
}
