import("../../include/format/pe32.inc");

x86.use32();

pe32_exe(2);

pe32_section(".text", 0);
text_start:
start:
    ret
reserve(0x20000);
text_end:
pe32_end_section(0);
pe32_finish_text(0, start, text_start, text_end, pe32_rx);

pe32_section(".rdata", 1);
rdata_start:
    emit.u8(0x42);
rdata_end:
pe32_end_section(1);
pe32_finish_section(1, pe_name_rdata, rdata_start, rdata_end, pe32_ro);
pe_finalize_image_size(rdata_start - pe_default_image_base32, rdata_start, rdata_end);
pe_finalize_init_data_size(rdata_start, rdata_end);

defer {
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_virtual_size_foa) == text_end - text_start);
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_size_foa) == pe_default_file_align);
    assert(load.u32(region_base() + pe_row32_foa(1) + pe_sec_raw_ptr_foa) == pe_default_file_align * 2);
    assert(load.u32(region_base() + pe_row32_foa(1) + pe_sec_rva_foa) == align_up(text_end - pe_default_image_base32, pe_default_section_align));
    assert(load.u32(region_base() + pe_opt_size_of_code_foa) == region_file_size(text_start));
    assert(load.u32(region_base() + pe_opt_size_of_init_data_foa) == region_file_size(rdata_start));
    assert(load.u32(region_base() + pe_opt_size_of_image_foa) == align_up((rdata_start - pe_default_image_base32) + (rdata_end - rdata_start), pe_default_section_align));
    assert(region_file_offset(text_start) == pe_default_file_align);
    assert(region_file_size(text_start) == pe_default_file_align);
    assert(region_logical_size(text_start) == text_end - text_start);
}
