// User-facing PE32 format facade.
//
// This facade remains as a source-level compatibility layer over pe.inc for
// examples that spell out PE rows and finalizers in DSL.

import("pe.inc");

const pe32_r: u32 = pe_scn_mem_read
const pe32_w: u32 = pe_scn_mem_write
const pe32_x: u32 = pe_scn_mem_execute
const pe32_rx: u32 = pe_scn_cnt_code | pe32_r | pe32_x
const pe32_rw: u32 = pe_scn_cnt_init_data | pe32_r | pe32_w
const pe32_rwx: u32 = pe_scn_cnt_code | pe_scn_cnt_init_data | pe32_r | pe32_w | pe32_x
const pe32_ro: u32 = pe_scn_cnt_init_data | pe32_r

const pe32_console: u16 = pe_subsystem_console
const pe32_gui: u16 = pe_subsystem_gui

fn pe32_exe(section_count: u16) {
    pe_begin32();
    pe_headers32(section_count);
}

fn pe32_dll(section_count: u16) {
    pe_begin_dll32();
    pe_headers_dll32(section_count);
}

fn pe32_rva(row: u64) -> u64 {
    return pe_section_rva(row, pe_default_section_align);
}

fn pe32_foa(row: u64) -> u64 {
    return pe_section_raw_ptr(row, pe_default_file_align);
}

fn pe32_current_rva() -> u64 {
    const current: u64 = here()
    if current < pe_default_image_base32 {
        return pe_default_section_align;
    }
    return align_up(current - pe_default_image_base32, pe_default_section_align);
}

fn pe32_section(name: string, row: u64) {
    pe_begin_section32_at(name, row, pe32_current_rva(), file_offset());
}

fn pe32_end_section(row: u64) {
    pe_align_section_file(row);
}

fn pe32_finish_text(row: u64, entry_label: u64, start: u64, end: u64, chars: u64) {
    assert(start >= pe_default_image_base32, "PE32 section start is outside image space");
    assert(end >= start, "PE32 section end is before section start");
    const section_rva: u64 = start - pe_default_image_base32
    pe_finalize_section32_auto(row, pe_name_text, start, chars);
    pe_finalize_entry(entry_label, start, section_rva);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_code_size(start, end);
    pe_finalize_base_of_code(section_rva);
}

fn pe32_finish_section(row: u64, name0: u64, start: u64, end: u64, chars: u64) {
    assert(start >= pe_default_image_base32, "PE32 section start is outside image space");
    assert(end >= start, "PE32 section end is before section start");
    pe_finalize_section32_auto(row, name0, start, chars);
}

fn pe32_finish_import_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base32, "PE32 import section start is outside image space");
    assert(end >= start, "PE32 import section end is before section start");
    const section_rva: u64 = start - pe_default_image_base32
    pe_finalize_section32_auto(row, pe_name_idata, start, pe_idata_chars);
    pe_finalize_import_dir32(section_rva, start, pe_import_descriptors, pe_import_descriptors_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}

fn pe32_finish_export_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base32, "PE32 export section start is outside image space");
    assert(end >= start, "PE32 export section end is before section start");
    const section_rva: u64 = start - pe_default_image_base32
    pe_finalize_section32_auto(row, pe_name_edata, start, pe_edata_chars);
    pe_finalize_export_dir32(section_rva, start, pe_export_directory, pe_export_directory_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}

fn pe32_finish_reloc_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base32, "PE32 relocation section start is outside image space");
    assert(end >= start, "PE32 relocation section end is before section start");
    const section_rva: u64 = start - pe_default_image_base32
    pe_finalize_section32_auto(row, pe_name_reloc, start, pe_reloc_chars);
    pe_finalize_reloc_dir32(section_rva, start, pe_reloc_block, pe_reloc_block_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
    defer {
        store.u16(region_base() + pe_opt_dll_chars_foa, pe_dll_dynamic_base | pe_dll_nx_compat);
    }
}

fn pe32_finish_resource_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base32, "PE32 resource section start is outside image space");
    assert(end >= start, "PE32 resource section end is before section start");
    const section_rva: u64 = start - pe_default_image_base32
    pe_finalize_section32_auto(row, pe_name_rsrc, start, pe_rsrc_chars);
    pe_finalize_resource_dir32(section_rva, start, pe_resource_root, end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}
