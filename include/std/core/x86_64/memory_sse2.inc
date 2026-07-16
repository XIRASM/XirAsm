// x86-64 memory 原语的 SSE2 baseline 内核生成器。
//
// 所有向量访问都使用 movdqu，只在剩余长度至少 16 时执行。代码不使用
// AVX，因此不需要 vzeroupper，也不会产生 legacy SSE/AVX 转换问题。

// 前向 SSE2 copy 内核。
// 输入：R10=目标，R11=源，R8=长度，范围适合前向复制。
// 返回：不设置 RAX。
// 破坏：RDX、R8-R11、XMM0、flags；尾部转交精确 scalar 生成器。
fn std_core_memory_emit_forward_sse2() {
    const tail: string = sym.unique("__std_mem_fwd_sse2_tail_")
    const loop: string = sym.unique("__std_mem_fwd_sse2_loop_")

    cmp r8, 16
    isa(sym.join("jb ", tail));
    label.define(loop);
    movdqu xmm0, [r11]
    movdqu [r10], xmm0
    add r11, 16
    add r10, 16
    sub r8, 16
    cmp r8, 16
    isa(sym.join("jae ", loop));

    label.define(tail);
    cmp r8, 8
    const small_tail: string = sym.unique("__std_mem_fwd_sse2_small_")
    isa(sym.join("jb ", small_tail));
    mov rdx, qword [r11]
    mov qword [r10], rdx
    add r11, 8
    add r10, 8
    sub r8, 8
    label.define(small_tail);
    std_core_memory_emit_forward_tail();
}

// 后向 SSE2 move 内核。
// 输入：R10=目标起点，R11=源起点，R8=长度，目标位于重叠源之后。
// 返回：不设置 RAX。
// 破坏：RDX、R8-R11、XMM0、flags；每个向量先完整读取再写入。
fn std_core_memory_emit_backward_sse2() {
    const tail: string = sym.unique("__std_mem_back_sse2_tail_")
    const loop: string = sym.unique("__std_mem_back_sse2_loop_")
    const small_tail: string = sym.unique("__std_mem_back_sse2_small_")

    add r10, r8
    add r11, r8
    cmp r8, 16
    isa(sym.join("jb ", tail));
    label.define(loop);
    sub r11, 16
    sub r10, 16
    movdqu xmm0, [r11]
    movdqu [r10], xmm0
    sub r8, 16
    cmp r8, 16
    isa(sym.join("jae ", loop));

    label.define(tail);
    cmp r8, 8
    isa(sym.join("jb ", small_tail));
    sub r11, 8
    sub r10, 8
    mov rdx, qword [r11]
    mov qword [r10], rdx
    sub r8, 8
    label.define(small_tail);
    std_core_memory_emit_backward_tail();
}

// SSE2 fill 内核。
// 输入：R10=目标，R11 低字节=填充值，R8=长度。
// 返回：不设置 RAX。
// 破坏：RDX、R8-R11、XMM0、flags；不对齐写安全且不越过尾部。
fn std_core_memory_emit_fill_sse2() {
    const tail: string = sym.unique("__std_mem_fill_sse2_tail_")
    const loop: string = sym.unique("__std_mem_fill_sse2_loop_")
    const skip8: string = sym.unique("__std_mem_fill_sse2_skip8_")
    const skip4: string = sym.unique("__std_mem_fill_sse2_skip4_")
    const skip2: string = sym.unique("__std_mem_fill_sse2_skip2_")
    const skip1: string = sym.unique("__std_mem_fill_sse2_skip1_")

    std_core_memory_prepare_fill_scalar();
    movd xmm0, edx
    pshufd xmm0, xmm0, 0
    cmp r8, 16
    isa(sym.join("jb ", tail));
    label.define(loop);
    movdqu [r10], xmm0
    add r10, 16
    sub r8, 16
    cmp r8, 16
    isa(sym.join("jae ", loop));

    label.define(tail);
    test r8, 8
    isa(sym.join("jz ", skip8));
    mov qword [r10], rdx
    add r10, 8
    label.define(skip8);
    test r8, 4
    isa(sym.join("jz ", skip4));
    mov dword [r10], edx
    add r10, 4
    label.define(skip4);
    test r8, 2
    isa(sym.join("jz ", skip2));
    mov word [r10], dx
    add r10, 2
    label.define(skip2);
    test r8, 1
    isa(sym.join("jz ", skip1));
    mov byte [r10], dl
    label.define(skip1);
}

// SSE2 compare 内核。
// 输入：R10=left，R11=right，R8=长度；三个结果标签由调用方定义。
// 输出：跳转到 equal/less/greater。
// 破坏：RAX、RCX、RDX、R8、R10、R11、XMM0-XMM1、flags。
// 安全：向量加载只发生在剩余长度至少 16 时；尾部逐字节处理。
fn std_core_memory_emit_compare_sse2(equal_label: string, less_label: string, greater_label: string) {
    const tail: string = sym.unique("__std_mem_cmp_sse2_tail_")
    const loop: string = sym.unique("__std_mem_cmp_sse2_loop_")
    const difference: string = sym.unique("__std_mem_cmp_sse2_difference_")

    cmp r8, 16
    isa(sym.join("jb ", tail));
    label.define(loop);
    movdqu xmm0, [r10]
    movdqu xmm1, [r11]
    pcmpeqb xmm0, xmm1
    pmovmskb edx, xmm0
    cmp edx, 0xffff
    isa(sym.join("jne ", difference));
    add r10, 16
    add r11, 16
    sub r8, 16
    cmp r8, 16
    isa(sym.join("jae ", loop));
    isa(sym.join("jmp ", tail));

    label.define(difference);
    not edx
    and edx, 0xffff
    bsf ecx, edx
    movzx eax, byte [r10 + rcx]
    movzx edx, byte [r11 + rcx]
    cmp eax, edx
    isa(sym.join("jb ", less_label));
    isa(sym.join("jmp ", greater_label));

    label.define(tail);
    std_core_memory_emit_compare_scalar(equal_label, less_label, greater_label);
}
