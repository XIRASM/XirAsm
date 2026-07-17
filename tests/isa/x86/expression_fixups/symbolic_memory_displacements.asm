origin(0)
x86.use64()

entry:
    mov eax, [rax + target]
    mov eax, [rax + rcx*4 + target]
    mov eax, [r13 + target]
    vmovdqu32 zmm0, [rax + target]
target:
    ret
