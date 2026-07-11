x86.use16();
nop
mov ax, [bx + si + 16]
mov [bp + di + 32], ax
add ax, 1234h

x86.use32();
nop
mov eax, [ebx + ecx*4 + 16]
mov [esp + 8], eax
add eax, 12345678h

x86.use64();
nop
mov rax, [rbx + rcx*4 + 16]
mov [rsp + 8], rax
add rax, 12345678h
