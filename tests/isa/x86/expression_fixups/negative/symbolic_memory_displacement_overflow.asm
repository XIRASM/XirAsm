origin(0x80000000)
x86.use64()

entry:
    mov eax, [rax + target]
target:
    ret
