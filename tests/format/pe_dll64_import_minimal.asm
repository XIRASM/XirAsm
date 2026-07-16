import("../../include/format/pe64.inc");
import("../../include/format/pe_import.inc");

let imports: map = pe_import_new()
imports = pe_import_use64(imports, "KERNEL32.DLL", "ExitProcess")

const text_rva: u64 = pe_section_rva(0, pe_default_section_align)
const text_raw: u64 = pe_section_raw_ptr(0, pe_default_file_align)
const idata_rva: u64 = pe_section_rva(1, pe_default_section_align)
const idata_raw: u64 = pe_section_raw_ptr(1, pe_default_file_align)

pe64_dll(2);

pe64_section(".text", 0);
text_start:
dll_main:
    sub rsp, 40
    xor ecx, ecx
call_exitprocess:
db(0xff, 0x15);
dd(0);
    mov eax, 1
    add rsp, 40
    ret
text_end:
pe64_end_section(0);

pe64_section(".idata", 1);
idata_start:
pe_import_emit64(imports, idata_rva, idata_start);
idata_end:
pe64_end_section(1);

pe64_finish_text(0, dll_main, text_start, text_end, pe_text_chars);
pe64_finish_import_section(1, idata_start, idata_end);
pe_finalize_u32(call_exitprocess + 2, ExitProcess - (call_exitprocess + 6));

defer {

    assert((load.u16(region_base() + pe_file_header_foa + 18) & pe_file_dll) == pe_file_dll);
    assert(load.u32(region_base() + pe_dir_rva_foa(pe_dir_import)) == idata_rva + (pe_import_descriptors - idata_start));
    assert(load.u32(region_base() + pe_dir_size_foa(pe_dir_import)) == pe_import_descriptor_size * 2);
    assert(load.u32(pe_import_descriptors) == idata_rva + (pe_import_kernel32_dll_lookup - idata_start));
    assert(load.u32(pe_import_descriptors + 12) == idata_rva + (pe_import_kernel32_dll_name - idata_start));
    assert(load.u32(pe_import_descriptors + 16) == idata_rva + (pe_import_kernel32_dll_iat - idata_start));
    assert(load.u64(ExitProcess) != 0);
}
