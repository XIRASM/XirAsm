// api-matrix-fixture: pe_finalize_resource_dir32(
// api-matrix-fixture: pe32_finish_resource_section(

import("../../include/format/pe32.inc");
import("../../include/format/pe_resource.inc");

x86.use32();

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const rsrc_rva: u64 = pe_section_rva(1, pe_default_section_align)

pe32_exe(2);

pe32_section(".text", 0);
text_start:
start:
    mov eax, 1
    ret
text_end:
pe32_end_section(0);

pe32_section(".rsrc", 1);
rsrc_start:
pe_resource_emit_single_numeric(pe_resource_type_version, 1, pe_resource_lang_en_us);
db(0x78, 0x56, 0x34, 0x12);
resource_payload_end:
pe_resource_finish_single_numeric(rsrc_rva, rsrc_start, resource_payload_end, 0);
rsrc_end:
pe32_end_section(1);

pe32_finish_text(0, start, text_start, text_end, pe_text_chars);
pe32_finish_resource_section(1, rsrc_start, pe_resource_end);

defer {

    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_resource)) == rsrc_rva);
    assert(load.u32(region_base() + pe_dir32_size_foa(pe_dir_resource)) == pe_resource_end - pe_resource_root);
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
    assert(load.u8(pe_resource_data) == 0x78);
    assert(load.u8(pe_resource_data + 3) == 0x12);
}
