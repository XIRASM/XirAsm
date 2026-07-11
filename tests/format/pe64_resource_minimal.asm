// api-matrix-fixture: pe_finalize_resource_dir64(
// api-matrix-fixture: pe64_finish_resource_section(
// api-matrix-fixture: pe_resource_directory(
// api-matrix-fixture: pe_resource_directory_entry(
// api-matrix-fixture: pe_resource_data_entry(
// api-matrix-fixture: pe_resource_emit_single_numeric(
// api-matrix-fixture: pe_resource_finish_single_numeric(

import("../../include/format/pe64.inc");
import("../../include/format/pe_resource.inc");

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const rsrc_rva: u64 = pe_section_rva(1, pe_default_section_align)

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
    mov eax, 1
    ret
text_end:
pe64_end_section(0);

pe64_section(".rsrc", 1);
rsrc_start:
pe_resource_emit_single_numeric(pe_resource_type_version, 1, pe_resource_lang_en_us);
db(0x34, 0x12, 0x00, 0x00, 0x56);
resource_payload_end:
pe_resource_finish_single_numeric(rsrc_rva, rsrc_start, resource_payload_end, 0);
rsrc_end:
pe64_end_section(1);

pe64_finish_text(0, start, text_start, text_end, pe_text_chars);
pe64_finish_resource_section(1, rsrc_start, pe_resource_end);

defer {

    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_resource)) == rsrc_rva);
    assert(load.u32(region_base() + pe_dir_size_foa(pe_dir_resource)) == pe_resource_end - pe_resource_root);
    assert(load.u16(pe_resource_root + 12) == 0);
    assert(load.u16(pe_resource_root + 14) == 1);
    assert(load.u32(pe_resource_root + 16) == pe_resource_type_version);
    assert(load.u32(pe_resource_root + 20) == pe_resource_subdirectory_flag | pe_resource_single_type_dir_offset);
    assert(load.u32(pe_resource_type_directory + 16) == 1);
    assert(load.u32(pe_resource_type_directory + 20) == pe_resource_subdirectory_flag | pe_resource_single_id_dir_offset);
    assert(load.u32(pe_resource_id_directory + 16) == pe_resource_lang_en_us);
    assert(load.u32(pe_resource_id_directory + 20) == pe_resource_single_data_entry_offset);
    assert(load.u32(pe_resource_data_entry) == rsrc_rva + (pe_resource_data - rsrc_start));
    assert(load.u32(pe_resource_data_entry + 4) == resource_payload_end - pe_resource_data);
    assert(load.u32(pe_resource_data_entry + 8) == 0);
    assert(load.u8(pe_resource_data) == 0x34);
    assert(load.u8(pe_resource_data + 4) == 0x56);
}
