import("../../include/format/pe64.inc");

pe64_exe(1);

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

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_amd64);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == pe64_rva(0) + (start - text_start));
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_ptr_foa) == pe64_foa(0));
    assert(load.u32(region_base() + pe_row_foa(0) + pe_sec_raw_size_foa) == align_up(text_end - text_start, pe_default_file_align));
}
