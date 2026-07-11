import("../../include/format/pe64.inc");

pe64_exe(2);

pe64_section(".text", 0);
text_start:
start:
for i in range(0, 128) {
    vmovdqu ymm0, yword [rax + rbx*4 + 64]
    vpxor ymm1, ymm0, yword [rax + rbx*4 + 96]
    vpaddd ymm2, ymm1, yword [rax + rbx*4 + 128]
    vpshufb ymm3, ymm2, yword [rax + rbx*4 + 160]
    vperm2i128 ymm4, ymm2, ymm3, 031h
    vpalignr ymm5, ymm4, ymm1, 8
    vpblendd ymm6, ymm5, yword [rax + rbx*4 + 192], 0AAh
    vmovdqu yword [rax + rbx*4 + 224], ymm6
}
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

defer {
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_size_foa) == align_up(text_end - text_start, pe_default_file_align));
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) == pe_default_file_align);
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_raw_ptr_foa) == pe_default_file_align + align_up(text_end - text_start, pe_default_file_align));
    assert(load.u32(region_base() + pe_row_foa(1) + pe_sec_rva_foa) == align_up(text_end - pe_default_image_base64, pe_default_section_align));
    assert(load.u32(region_base() + pe_opt_size_of_image_foa) == align_up(align_up(text_end - pe_default_image_base64, pe_default_section_align) + (rdata_end - rdata_start), pe_default_section_align));
}
