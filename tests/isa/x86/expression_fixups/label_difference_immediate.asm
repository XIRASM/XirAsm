origin(0)
x86.use64()

start:
    nop
    mov eax, finish - start
finish:
    ret
