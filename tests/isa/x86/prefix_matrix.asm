origin(0)
x86.use64()

entry:
    lock add dword [rbx], 1
    rep movsb
    repe cmpsb
    repne scasb
    mov rax, fs:[rbx]
    mov rax, [gs:rbx + 4]
