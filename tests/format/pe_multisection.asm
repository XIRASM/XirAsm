import("../../include/format/pe.inc");

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const rdata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const rdata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)
const bss_rva: u64 = pe_section_rva(2, pe_default_section_align)

pe_begin64();
pe_headers64(3);

pe_begin_section(".text", 0, text_rva);
text_start:
start:
    mov eax, [rel rdata_start]
    ret
text_end:
pe_end_section(0, pe_default_file_align);

pe_begin_section(".rdata", 1, rdata_rva);
rdata_start:
dd(42);
rdata_end:
pe_end_section(1, pe_default_file_align);

pe_begin_section(".bss", 2, bss_rva);
bss_start:
reserve(64);
bss_end:
pe_align_section_file(2);

pe_finalize_section64(0, pe_name_text, text_rva, text_raw, text_start, text_end, pe_text_chars);
pe_finalize_section64(1, pe_name_rdata, rdata_rva, rdata_raw, rdata_start, rdata_end, pe_rdata_chars);
pe_finalize_section64_auto(2, pe_name_bss, bss_start, pe_bss_chars);
pe_finalize_entry(start, text_start, text_rva);
pe_finalize_image_size(bss_rva, bss_start, bss_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_init_data_size(rdata_start, rdata_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_u32(
    pe_default_image_base64 + pe_opt_size_of_uninit_data_foa,
    bss_end - bss_start
);

defer {

    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa + 2) == 3);
    assert(load.u32(region_base() + pe_opt_size_of_image_foa) == 0x4000);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_rva_foa) == rdata_rva);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_raw_ptr_foa) == rdata_raw);
    assert(load.u32(region_base() + pe_row_foa(2) + pe_sec_virtual_size_foa) == 64);
    assert(load.u32(region_base() + pe_row_foa(2) + pe_sec_raw_size_foa) == 0);
    assert(load.u32(region_base() + pe_row_foa(2) + pe_sec_raw_ptr_foa) == 0);
    assert(load.u32(region_base() + pe_opt_size_of_uninit_data_foa) == 64);
}
