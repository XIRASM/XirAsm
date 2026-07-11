origin(0x2000)
x86.use32()

before:
    nop
after:
    mov eax, [eax + 127]
    mov eax, [eax + 128]
    mov eax, [eax - 128]
    mov eax, [eax - 129]
    mov eax, [ebp]
    mov eax, [esp]
    mov eax, [ecx*4 + 0x12345678]
    mov eax, [eax + ecx + 16]
    mov eax, [eax + ecx*1 + 16]
    mov eax, [eax + ecx*8 - 128]
    cmp byte [eax], 0x7f
    cmp byte [eax], -1
    cmp word [eax], 0x1234
    cmp dword [eax], 0x12345678
    repne scasb
    repe cmpsb