// api-matrix-fixture: pe_finalize_u32(
// api-matrix-fixture: pe_finalize_section64(
// api-matrix-fixture: pe_finalize_entry(
// api-matrix-fixture: pe_finalize_image_size(
// api-matrix-fixture: pe_finalize_code_size(
// api-matrix-fixture: pe_finalize_init_data_size(
// api-matrix-fixture: pe_finalize_base_of_code(
// api-matrix-fixture: pe_finalize_import_dir64(
// api-matrix-fixture: pe64_finish_import_section(
// api-matrix-fixture: pe_import_new(
// api-matrix-fixture: pe_import_use32(
// api-matrix-fixture: pe_import_use64(
// api-matrix-fixture: pe_import_use32_as(
// api-matrix-fixture: pe_import_use64_as(
// api-matrix-fixture: pe_import_use32_many(
// api-matrix-fixture: pe_import_use64_many(
// api-matrix-fixture: pe_import_use32_pairs(
// api-matrix-fixture: pe_import_use64_pairs(
// api-matrix-fixture: pe_import_use32_ordinal_as(
// api-matrix-fixture: pe_import_use64_ordinal_as(
// api-matrix-fixture: pe_import_descriptor(
// api-matrix-fixture: pe_import_descriptor_null(
// api-matrix-fixture: pe_import_thunk32_name(
// api-matrix-fixture: pe_import_emit64(
// api-matrix-fixture: pe_import_descriptors
// api-matrix-fixture: pe_import_thunk64_name(
// api-matrix-fixture: pe_import_thunk32_ordinal(
// api-matrix-fixture: pe_import_thunk64_ordinal(
// api-matrix-fixture: pe_import_thunk32_null(
// api-matrix-fixture: pe_import_thunk64_null(
// api-matrix-fixture: pe_import_hint_name(

import("../../include/format/pe64.inc");
import("../../include/format/pe_import.inc");

let imports: map = pe_import_new()
imports = pe_import_use64_pairs(
    imports,
    "KERNEL32.DLL",
    list.of("exit_process_iat", "ExitProcess", "get_process_id_iat", "GetCurrentProcessId")
)

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const idata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const idata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
    sub rsp, 40
    xor ecx, ecx
call_exitprocess:
db(0xff, 0x15);
dd(0);
text_end:
pe64_end_section(0);

pe64_section(".idata", 1);
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
pe64_end_section(1);

pe64_finish_text(0, start, text_start, text_end, pe_text_chars);
pe64_finish_import_section(1, idata_start, idata_end);
pe_finalize_u32(call_exitprocess + 2, exit_process_iat - (call_exitprocess + 6));

defer {

    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_import)) == idata_rva + (pe_import_descriptors - idata_start));
    assert(load.u32(region_base() + pe_dir_size_foa(pe_dir_import)) == pe_import_descriptor_size * 2);
    assert(load.u32(pe_import_descriptors) == idata_rva + (pe_import_kernel32_dll_lookup - idata_start));
    assert(load.u32(pe_import_descriptors + 12) == idata_rva + (pe_import_kernel32_dll_name - idata_start));
    assert(load.u32(pe_import_descriptors + 16) == idata_rva + (pe_import_kernel32_dll_iat - idata_start));
    assert(load.u32(exit_process_iat) != 0);
    assert(load.u32(get_process_id_iat) != 0);
}
