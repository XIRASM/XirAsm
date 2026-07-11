// api-matrix-fixture: pe_opt_checksum_foa
// api-matrix-fixture: pe_checksum_begin(
// api-matrix-fixture: pe_checksum_add_region(
// api-matrix-fixture: pe_checksum_finish(

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

pe_checksum_begin();
pe_checksum_add_region(text_start);
pe_checksum_finish(text_start);

defer {
    assert(load.u32(region_base() + pe_opt_checksum_foa) != 0);
}
