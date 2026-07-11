mov rax, [rbx + rcx*4 + 8]
mov rax, [r12 + r13*8 + 128]
mov r8, [r9 + r10*2 + 12345678h]
mov [rsp + 8], rax
lea r11, [r12 + r13*4 + 40h]
vmovdqu ymm1, yword [rax + rbx*4 + 64]
vmovups ymm3, yword [r8 + r9*8 + 128]
vmovntdq yword [r14 + rdi*4 + 224], ymm11
