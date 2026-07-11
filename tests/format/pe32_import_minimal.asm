// api-matrix-fixture: pe_finalize_section32(
// api-matrix-fixture: pe_finalize_import_dir32(
// api-matrix-fixture: pe32_finish_import_section(
// api-matrix-fixture: pe_import_new(
// api-matrix-fixture: pe_import_use32(
// api-matrix-fixture: pe_import_use64(
// api-matrix-fixture: pe_import_use32_as(
// api-matrix-fixture: pe_import_use64_as(
// api-matrix-fixture: pe_import_use32_ordinal_as(
// api-matrix-fixture: pe_import_use64_ordinal_as(
// api-matrix-fixture: pe_import_descriptor(
// api-matrix-fixture: pe_import_descriptor_null(
// api-matrix-fixture: pe_import_emit32(
// api-matrix-fixture: pe_import_thunk32_name(
// api-matrix-fixture: pe_import_thunk64_name(
// api-matrix-fixture: pe_import_thunk32_ordinal(
// api-matrix-fixture: pe_import_thunk64_ordinal(
// api-matrix-fixture: pe_import_thunk32_null(
// api-matrix-fixture: pe_import_thunk64_null(
// api-matrix-fixture: pe_import_hint_name(
// api-matrix-fixture: pe_import_descriptors

import("../../include/format/pe32.inc");
import("../../include/format/pe_import.inc");

x86.use32();

const imports0: map = pe_import_new()
const imports1: map = pe_import_use32_as(imports0, "KERNEL32.DLL", "ExitProcess", "exit_process_iat")

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const idata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const idata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)

pe32_exe(2);

pe32_section(".text", 0);
text_start:
start:
db(0x6a, 0x00);
call_exitprocess:
db(0xff, 0x15);
dd(0);
text_end:
pe32_end_section(0);

pe32_section(".idata", 1);
idata_start:
pe_import_emit32(imports1, idata_rva, idata_start);
idata_payload_end:
idata_end:
pe32_end_section(1);

pe32_finish_text(0, start, text_start, text_end, pe_text_chars);
pe32_finish_import_section(1, idata_start, idata_end);
pe_finalize_u32(call_exitprocess + 2, exit_process_iat);

defer {

    assert(load.u32(region_base() + pe_dir32_rva_foa(pe_dir_import)) == idata_rva + (pe_import_descriptors - idata_start));
    assert(load.u32(region_base() + pe_dir32_size_foa(pe_dir_import)) == pe_import_descriptor_size * 2);
    assert(load.u32(pe_import_descriptors) == idata_rva + (pe_import_kernel32_dll_lookup - idata_start));
    assert(load.u32(pe_import_descriptors + 12) == idata_rva + (pe_import_kernel32_dll_name - idata_start));
    assert(load.u32(pe_import_descriptors + 16) == idata_rva + (pe_import_kernel32_dll_iat - idata_start));
    assert(load.u32(exit_process_iat) == idata_rva + (pe_import_kernel32_dll_exit_process_iat_hint - idata_start));
}
