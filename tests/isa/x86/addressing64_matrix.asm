origin(0x2000)
x86.use64()

before:
    nop
after:
    mov eax, [rax + 127]
    mov eax, [rax + 128]
    mov eax, [rax - 128]
    mov eax, [rax - 129]
    mov eax, [rbp]
    mov eax, [r13]
    mov eax, [rsp]
    mov eax, [r12]
    mov eax, [rcx*4 + 0x12345678]
    mov eax, [rax + rcx + 16]
    mov eax, [rax + rcx*1 + 16]
    mov eax, [rax + rcx*8 - 128]
    mov eax, [r13 + r11*2 - 129]
    mov eax, [rel after - 1]
    cmp byte [rax], 0x7f
    cmp byte [rax], -1
    cmp word [rax], 0x1234
    cmp dword [rax], 0x12345678
    cmp qword [rax], -1
    cmp qword [rax], 0x11223344
    repne scasb
    repe cmpsb