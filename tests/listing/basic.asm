origin(0x7c00);

start:
    mov rax, 1
    add rax, 2
    ret

emit.u8(0xaa);
reserve(2);
emit.u16(0x55cc);
