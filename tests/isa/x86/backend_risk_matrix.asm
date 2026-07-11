origin(0x1000)

state:
emit.u64(0)
emit.u32(0)

src:
emit.bytes(b"ABCD")

dst:
emit.u8(0)
emit.u8(0)
emit.u8(0)
emit.u8(0)

entry:
    mov eax, [rel state + 8]
    cmp qword [rel state], 0x11223344
    cmp rax, 0x7fffffff
    cmp rax, -2147483648
    lea rsi, [rel src]
    lea rdi, [rel dst]
    mov ecx, 4
    rep movsb
    ret
