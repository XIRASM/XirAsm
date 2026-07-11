import("../../include/format/pe32.inc");

x86.use32();

pe32_exe(1);

pe32_section(".text", 0);
text_start:
start:
for i in range(0, 128) {
    vmovdqu ymm0, yword [eax + ebx*4 + 64]
    vpxor ymm1, ymm0, yword [eax + ebx*4 + 96]
    vpaddd ymm2, ymm1, yword [eax + ebx*4 + 128]
    vpshufb ymm3, ymm2, yword [eax + ebx*4 + 160]
    vperm2i128 ymm4, ymm2, ymm3, 031h
    vpalignr ymm5, ymm4, ymm1, 8
    vpblendd ymm6, ymm5, yword [eax + ebx*4 + 192], 0AAh
    vmovdqu yword [eax + ebx*4 + 224], ymm6
}
    ret
text_end:
pe32_end_section(0);

pe32_finish_text(0, start, text_start, text_end, pe32_rx);

defer {
    assert(load.u16(region_base()) == pe_magic_mz);
    assert(load.u32(region_base() + pe_nt_headers_foa) == pe_signature);
    assert(load.u16(region_base() + pe_file_header_foa) == pe_machine_i386);
    assert(load.u16(region_base() + pe_optional_header_foa) == pe_opt32_magic);
    assert(load.u32(region_base() + pe_opt_entry_rva_foa) == pe32_rva(0) + (start - text_start));
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_ptr_foa) == pe32_foa(0));
    assert(load.u32(region_base() + pe_row32_foa(0) + pe_sec_raw_size_foa) == align_up(text_end - text_start, pe_default_file_align));
}
