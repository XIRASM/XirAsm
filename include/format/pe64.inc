// Width-specific PE64 format compatibility include.
//
// This include remains as a source-level compatibility layer over pe.inc for
// examples that spell out PE rows and finalizers in DSL.

import("pe.inc");

const pe_r: u32 = pe_scn_mem_read
const pe_w: u32 = pe_scn_mem_write
const pe_x: u32 = pe_scn_mem_execute
const pe_rx: u32 = pe_scn_cnt_code | pe_r | pe_x
const pe_rw: u32 = pe_scn_cnt_init_data | pe_r | pe_w
const pe_rwx: u32 = pe_scn_cnt_code | pe_scn_cnt_init_data | pe_r | pe_w | pe_x
const pe_ro: u32 = pe_scn_cnt_init_data | pe_r

const pe_console: u16 = pe_subsystem_console
const pe_gui: u16 = pe_subsystem_gui

fn pe64_exe(section_count: u16) {
    pe_begin64();
    pe_headers64(section_count);
}

fn pe64_dll(section_count: u16) {
    pe_begin_dll64();
    pe_headers_dll64(section_count);
}

fn pe64_rva(row: u64) -> u64 {
    return pe_section_rva(row, pe_default_section_align);
}

fn pe64_foa(row: u64) -> u64 {
    return pe_section_raw_ptr(row, pe_default_file_align);
}

fn pe64_current_rva() -> u64 {
    const current: u64 = here()
    if current < pe_default_image_base64 {
        return pe_default_section_align;
    }
    return align_up(current - pe_default_image_base64, pe_default_section_align);
}

fn pe64_section(name: string, row: u64) {
    pe_begin_section_at(name, row, pe64_current_rva(), file_offset());
}

fn pe64_end_section(row: u64) {
    pe_align_section_file(row);
}

fn pe64_finish_text(row: u64, entry_label: u64, start: u64, end: u64, chars: u64) {
    assert(start >= pe_default_image_base64, "PE64 section start is outside image space");
    assert(end >= start, "PE64 section end is before section start");
    const section_rva: u64 = start - pe_default_image_base64
    pe_finalize_section64_auto(row, pe_name_text, start, chars);
    pe_finalize_entry(entry_label, start, section_rva);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_code_size(start, end);
    pe_finalize_base_of_code(section_rva);
}

fn pe64_finish_section(row: u64, name0: u64, start: u64, end: u64, chars: u64) {
    assert(start >= pe_default_image_base64, "PE64 section start is outside image space");
    assert(end >= start, "PE64 section end is before section start");
    pe_finalize_section64_auto(row, name0, start, chars);
}

fn pe64_finish_import_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base64, "PE64 import section start is outside image space");
    assert(end >= start, "PE64 import section end is before section start");
    const section_rva: u64 = start - pe_default_image_base64
    pe_finalize_section64_auto(row, pe_name_idata, start, pe_idata_chars);
    pe_finalize_import_dir64(section_rva, start, pe_import_descriptors, pe_import_descriptors_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}

fn pe64_finish_export_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base64, "PE64 export section start is outside image space");
    assert(end >= start, "PE64 export section end is before section start");
    const section_rva: u64 = start - pe_default_image_base64
    pe_finalize_section64_auto(row, pe_name_edata, start, pe_edata_chars);
    pe_finalize_export_dir64(section_rva, start, pe_export_directory, pe_export_directory_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}

fn pe64_finish_reloc_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base64, "PE64 relocation section start is outside image space");
    assert(end >= start, "PE64 relocation section end is before section start");
    const section_rva: u64 = start - pe_default_image_base64
    pe_finalize_section64_auto(row, pe_name_reloc, start, pe_reloc_chars);
    pe_finalize_reloc_dir64(section_rva, start, pe_reloc_block, pe_reloc_block_end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
    defer {
        store.u16(region_base() + pe_opt_dll_chars_foa, pe_dll_high_entropy_va | pe_dll_dynamic_base | pe_dll_nx_compat);
    }
}

fn pe64_finish_resource_section(row: u64, start: u64, end: u64) {
    assert(start >= pe_default_image_base64, "PE64 resource section start is outside image space");
    assert(end >= start, "PE64 resource section end is before section start");
    const section_rva: u64 = start - pe_default_image_base64
    pe_finalize_section64_auto(row, pe_name_rsrc, start, pe_rsrc_chars);
    pe_finalize_resource_dir64(section_rva, start, pe_resource_root, end);
    pe_finalize_image_size(section_rva, start, end);
    pe_finalize_init_data_size(start, end);
}
