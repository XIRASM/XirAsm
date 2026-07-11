mov al, [0x12345678]
mov [0x12345678], eax
mov rax, [0x123456789abcdef0]
mov [0x123456789abcdef0], rax
adc eax, -1
sbb qword [rbp - 0x80], -1
cmp byte [rax + 0x20], 0
rol byte [rcx], 1
rcr byte [rbp - 0x2b], 1
pand mm1, [rax]
paddb mm1, mm2
emms
movdqa xmm2, [rax + 0x10]
pshufb xmm2, xmm3
vpermilps xmm1, xmm2, 1
vaddps ymm1, ymm2, ymm3
vfmadd132ps ymm1, ymm2, yword [rax + 0x20]
vpbroadcastd ymm1, dword [rax + 0x30]
vperm2f128 ymm0, ymm1, ymm2, 0x62
