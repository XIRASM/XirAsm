nop
mov rax, fs:[rbx]
vaddps xmm1, xmm2, xmm3
vaddps xmm8, xmm9, xmm10
vaddps zmm8{k4}{z}, zmm9, zmm10, {rn-sae}
vaddps zmm2{k1}{z}, zmm3, dword [rax + 64]{1to16}
vgatherdps xmm1, dword [rax + xmm2*4], xmm3
vpgatherdd xmm4, dword [r8 + xmm5*4], xmm6
push r24
ccmpl 9, rdx, r30
