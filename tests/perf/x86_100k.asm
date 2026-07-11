for i in range(0, 12500) {
    vmovdqu ymm0, yword [rax + rbx*4 + 64]
    vpxor ymm1, ymm0, yword [rax + rbx*4 + 96]
    vpaddd ymm2, ymm1, yword [rax + rbx*4 + 128]
    vpshufb ymm3, ymm2, yword [rax + rbx*4 + 160]
    vperm2i128 ymm4, ymm2, ymm3, 031h
    vpalignr ymm5, ymm4, ymm1, 8
    vpblendd ymm6, ymm5, yword [rax + rbx*4 + 192], 0AAh
    vmovdqu yword [rax + rbx*4 + 224], ymm6
}

emit.u8(0xc3);
