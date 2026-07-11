// api-matrix-fixture: pe_finalize_data_dir32(
import("../../include/format/pe.inc");

x86.use32();

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)

pe_begin32();
pe_headers32(1);

pe_begin_section32(".text", 0, text_rva);
text_start:
start:
    xor eax, eax
    ret
text_end:
pe_end_section(0, pe_default_file_align);

pe_finalize_section32(0, pe_name_text, text_rva, text_raw, text_start, text_end, pe_text_chars);
pe_finalize_entry(start, text_start, text_rva);
pe_finalize_image_size(text_rva, text_start, text_end);
pe_finalize_code_size(text_start, text_end);
pe_finalize_base_of_code(text_rva);
pe_finalize_data_dir32(pe_dir_resource, 0, 0);

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_i386);
    assert(load.u16(region_base() + pe_optional_header_foa) == pe_opt32_magic);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == text_rva + (start - text_start));
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_ptr_foa) == text_raw);
    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_resource)) == 0);
    assert(load.u32(region_base() + pe_dir32_size_foa(pe_dir_resource)) == 0);
}
