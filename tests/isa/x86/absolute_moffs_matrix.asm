origin(0)
x86.use64()

entry:
    mov rax, [abs 0x12345678]
    mov [abs 0x12345678], rax
    mov al, [abs 0x12345678]
    mov [abs 0x12345678], al
    mov rax, [qword 0x123456789abcdef0]
    mov [qword 0x123456789abcdef0], rax
    mov al, [byte 0x12345678]
    mov [byte 0x12345678], al
