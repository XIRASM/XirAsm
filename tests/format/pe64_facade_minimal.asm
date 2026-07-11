// api-matrix-fixture: pe64_exe(
// api-matrix-fixture: pe64_section(
// api-matrix-fixture: pe64_end_section(
// api-matrix-fixture: pe64_finish_text(
// api-matrix-fixture: pe_rx

import("../../include/format/pe64.inc");

pe64_exe(1);

pe64_section(".text", 0);
text_start:
start:
    xor eax, eax
    ret
text_end:
pe64_end_section(0);

pe64_finish_text(0, start, text_start, text_end, pe_rx);

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_amd64);
    assert(load.u16(region_base() + pe_opt_dll_chars_foa) == pe_dll_nx_compat);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == pe64_rva(0) + (start - text_start));
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) == pe64_foa(0));
}
