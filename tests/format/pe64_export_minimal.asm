// api-matrix-fixture: pe_finalize_export_dir64(
// api-matrix-fixture: pe64_finish_export_section(
// api-matrix-fixture: pe_export_new(
// api-matrix-fixture: pe_export_use64(
// api-matrix-fixture: pe_export_emit64(
// api-matrix-fixture: pe_export_directory(
// api-matrix-fixture: pe_export_label_rva(
// api-matrix-fixture: pe_export_name_label(

import("../../include/format/pe64.inc");
import("../../include/format/pe_export.inc");

const exports0: list = pe_export_new()
const exports1: list = pe_export_use64(exports0, "dll_main", "xir_add7")
const exports2: list = pe_export_use64(exports1, "dll_sub3", "xir_sub3")

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const edata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const edata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)

pe64_dll(2);

pe64_section(".text", 0);
text_start:
dll_main:
    mov eax, 7
    ret
dll_sub3:
    mov eax, 3
    ret
text_end:
pe64_end_section(0);

pe64_section(".edata", 1);
edata_start:
pe_export_emit64(exports2, "xirasm_export64.dll", edata_rva, edata_start);
edata_end:
pe64_end_section(1);

pe64_finish_text(0, dll_main, text_start, text_end, pe_text_chars);
pe64_finish_export_section(1, edata_start, edata_end);

defer {

    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_export)) == edata_rva + (pe_export_directory - edata_start));
    assert(load.u32(pe_export_directory + 12) == edata_rva + (pe_export_dll_name - edata_start));
    assert(load.u32(pe_export_directory + 16) == pe_export_ordinal_base);
    assert(load.u32(pe_export_directory + 20) == 2);
    assert(load.u32(pe_export_directory + 24) == 2);
    assert(load.u32(pe_export_address_table) == text_rva + (dll_main - text_start));
    assert(load.u32(pe_export_address_table + 4) == text_rva + (dll_sub3 - text_start));
    assert(load.u32(pe_export_name_pointer_table) == edata_rva + (pe_export_name_0 - edata_start));
    assert(load.u32(pe_export_name_pointer_table + 4) == edata_rva + (pe_export_name_1 - edata_start));
    assert(load.u16(pe_export_ordinal_table) == 0);
    assert(load.u16(pe_export_ordinal_table + 2) == 1);
}
