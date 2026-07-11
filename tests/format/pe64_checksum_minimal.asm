import("../../include/format/pe64.inc");

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
    xor eax, eax
    ret
text_end:
pe64_end_section(0);
pe64_finish_text(0, start, text_start, text_end, pe_rx);

pe64_section(".rdata", 1);
rdata_start:
    emit.u8(1);
    emit.u8(2);
    emit.u8(3);
    emit.u8(4);
rdata_end:
pe64_end_section(1);
pe64_finish_section(1, pe_name_rdata, rdata_start, rdata_end, pe_ro);
pe_finalize_image_size(rdata_start - pe_default_image_base64, rdata_start, rdata_end);
pe_finalize_init_data_size(rdata_start, rdata_end);

pe_checksum_begin();
pe_checksum_add_region(text_start);
pe_checksum_add_region(rdata_start);
pe_checksum_finish(rdata_start);

defer {
    assert(load.u32(region_base() + pe_opt_checksum_foa) != 0);
}
