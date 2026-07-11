// api-matrix-fixture: pe32_exe(
// api-matrix-fixture: pe32_section(
// api-matrix-fixture: pe32_end_section(
// api-matrix-fixture: pe32_finish_text(
// api-matrix-fixture: pe32_rx

import("../../include/format/pe32.inc");

x86.use32();

pe32_exe(1);

pe32_section(".text", 0);
text_start:
start:
    xor eax, eax
    ret
text_end:
pe32_end_section(0);

pe32_finish_text(0, start, text_start, text_end, pe32_rx);

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_i386);
    assert(load.u16(region_base() + pe_optional_header_foa) == pe_opt32_magic);
    assert(load.u16(region_base() + pe_opt_dll_chars_foa) == pe_dll_nx_compat);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == pe32_rva(0) + (start - text_start));
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_ptr_foa) == pe32_foa(0));
}
