origin(0x1000)
x86.use64()

entry:
    call [rel thunk]
    jmp [rel table]
    mov rax, [rel value]
    lea rbx, [rel value + 8]
    cmp dword [rel value], 0x11223344
    cmp qword [rel value + 8], -1
    nop

thunk:
    emit.u64(0)
table:
    emit.u64(0)
value:
    emit.u64(0)
    emit.u64(0)
