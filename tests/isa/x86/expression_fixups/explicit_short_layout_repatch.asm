origin(0)
x86.use64()

entry:
    jmp short target
    mov eax, target
    nop
target:
    ret
