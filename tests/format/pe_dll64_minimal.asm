import("../../include/format/pe.inc");

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)

pe_begin_dll64();
pe_headers_dll64(1);

pe_begin_section(".text", 0, text_rva);
text_start:
dll_main:
    mov eax, 1
    ret
text_end:
pe_end_section(0, pe_default_file_align);

pe_finalize_section64(0, pe_name_text, text_rva, text_raw, text_start, text_end, pe_text_chars);
pe_finalize_entry(dll_main, text_start, text_rva);
pe_finalize_image_size(text_rva, text_start, text_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_base_of_code(text_rva);

defer {

    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_amd64);
    assert((load.u16(region_base() + pe_file_header_foa + 18) & pe_file_dll) == pe_file_dll);
    assert(load.u16(region_base() + pe_optional_header_foa) == pe_opt64_magic);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == text_rva + (dll_main - text_start));
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) == text_raw);
}
