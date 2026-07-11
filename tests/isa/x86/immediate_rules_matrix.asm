origin(0)
x86.use64()

entry:
    add al, 0x7f
    add ax, 0x1234
    add eax, 0x12345678
    add rax, 0x12345678
    add rax, -1
    sub al, 0x7f
    sub ax, 0x1234
    sub eax, 0x12345678
    sub rax, 0x12345678
    cmp al, 0x7f
    cmp ax, 0x1234
    cmp eax, 0x12345678
    cmp rax, 0x12345678
    test al, 0x7f
    test ax, 0x1234
    test eax, 0x12345678
    test rax, 0x12345678
    mov ax, 0x1234
    mov eax, 0x12345678
    mov rax, 0x123456789abcdef0
    push 0x7f
    push 0x1234
    push 0x12345678
