// x86-64 memory 原语的 scalar 内核生成器。
//
// 内部统一寄存器：R10=目标/左缓冲区，R11=源/右缓冲区或填充值，
// R8=剩余长度。所有生成器只使用 Win64 与 SysV 都允许破坏的寄存器。

// 精确复制不足 8 字节的前向尾部。
// 输入：R10=目标，R11=源，R8=0..7。
// 输出：复制恰好 R8 字节；R10/R11 前移已复制长度。
// 破坏：RDX、R8-R11、flags；不越界读取，不使用栈或 DF。
fn std_core_memory_emit_forward_tail() {
    const skip4: string = sym.unique("__std_mem_fwd_skip4_")
    const skip2: string = sym.unique("__std_mem_fwd_skip2_")
    const skip1: string = sym.unique("__std_mem_fwd_skip1_")

    test r8, 4
    isa(sym.join("jz ", skip4));
    mov edx, dword [r11]
    mov dword [r10], edx
    add r11, 4
    add r10, 4

    label.define(skip4);
    test r8, 2
    isa(sym.join("jz ", skip2));
    movzx edx, word [r11]
    mov word [r10], dx
    add r11, 2
    add r10, 2

    label.define(skip2);
    test r8, 1
    isa(sym.join("jz ", skip1));
    movzx edx, byte [r11]
    mov byte [r10], dl

    label.define(skip1);
}

// 精确复制不足 8 字节的后向尾部。
// 输入：R10/R11 指向尚未复制范围末尾，R8=0..7。
// 输出：先递减指针，再复制恰好 R8 字节。
// 破坏：RDX、R8-R11、flags；不越界读取，不使用栈或 DF。
fn std_core_memory_emit_backward_tail() {
    const skip4: string = sym.unique("__std_mem_back_skip4_")
    const skip2: string = sym.unique("__std_mem_back_skip2_")
    const skip1: string = sym.unique("__std_mem_back_skip1_")

    test r8, 4
    isa(sym.join("jz ", skip4));
    sub r11, 4
    sub r10, 4
    mov edx, dword [r11]
    mov dword [r10], edx

    label.define(skip4);
    test r8, 2
    isa(sym.join("jz ", skip2));
    sub r11, 2
    sub r10, 2
    movzx edx, word [r11]
    mov word [r10], dx

    label.define(skip2);
    test r8, 1
    isa(sym.join("jz ", skip1));
    sub r11, 1
    sub r10, 1
    movzx edx, byte [r11]
    mov byte [r10], dl

    label.define(skip1);
}

// 前向 scalar copy 内核。
// 输入：R10=目标，R11=源，R8=长度，范围必须有效且可按前向顺序复制。
// 返回：不设置 RAX；调用方保存并返回原目标。
// 破坏：RDX、R8-R11、flags；每次只访问范围内 8/4/2/1 字节。
fn std_core_memory_emit_forward_scalar() {
    const tail: string = sym.unique("__std_mem_fwd_scalar_tail_")
    const loop: string = sym.unique("__std_mem_fwd_scalar_loop_")

    cmp r8, 8
    isa(sym.join("jb ", tail));
    label.define(loop);
    mov rdx, qword [r11]
    mov qword [r10], rdx
    add r11, 8
    add r10, 8
    sub r8, 8
    cmp r8, 8
    isa(sym.join("jae ", loop));

    label.define(tail);
    std_core_memory_emit_forward_tail();
}

// 后向 scalar move 内核。
// 输入：R10=目标起点，R11=源起点，R8=长度，目标位于重叠源之后。
// 返回：不设置 RAX。
// 破坏：RDX、R8-R11、flags；先移动到范围末尾，再精确向低地址复制。
fn std_core_memory_emit_backward_scalar() {
    const tail: string = sym.unique("__std_mem_back_scalar_tail_")
    const loop: string = sym.unique("__std_mem_back_scalar_loop_")

    add r10, r8
    add r11, r8
    cmp r8, 8
    isa(sym.join("jb ", tail));
    label.define(loop);
    sub r11, 8
    sub r10, 8
    mov rdx, qword [r11]
    mov qword [r10], rdx
    sub r8, 8
    cmp r8, 8
    isa(sym.join("jae ", loop));

    label.define(tail);
    std_core_memory_emit_backward_tail();
}

// 把填充值低字节扩展为 RDX 中的 8 个相同字节。
// 输入：R11 的低 8 位为填充值。
// 输出：RDX=重复 8 次的字节，R9D=重复 4 次的字节。
// 破坏：RDX、R9、flags；完整写入 32 位寄存器以避免部分寄存器伪依赖。
fn std_core_memory_prepare_fill_scalar() {
    movzx edx, r11b
    imul edx, edx, 0x01010101
    mov r9d, edx
    shl rdx, 32
    or rdx, r9
}

// scalar fill 内核。
// 输入：R10=目标，R11 低字节=填充值，R8=长度。
// 返回：不设置 RAX；调用方保存并返回原目标。
// 破坏：RDX、R8-R11、flags；零长度不写内存。
fn std_core_memory_emit_fill_scalar() {
    const tail: string = sym.unique("__std_mem_fill_scalar_tail_")
    const loop: string = sym.unique("__std_mem_fill_scalar_loop_")
    const skip4: string = sym.unique("__std_mem_fill_skip4_")
    const skip2: string = sym.unique("__std_mem_fill_skip2_")
    const skip1: string = sym.unique("__std_mem_fill_skip1_")

    std_core_memory_prepare_fill_scalar();
    cmp r8, 8
    isa(sym.join("jb ", tail));
    label.define(loop);
    mov qword [r10], rdx
    add r10, 8
    sub r8, 8
    cmp r8, 8
    isa(sym.join("jae ", loop));

    label.define(tail);
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

// scalar compare 内核。
// 输入：R10=left，R11=right，R8=长度；三个标签由调用方定义。
// 输出：跳转到 equal/less/greater，不直接设置最终 RAX。
// 破坏：RAX、RDX、R8、R10、R11、flags；按无符号字节找第一个差异。
fn std_core_memory_emit_compare_scalar(equal_label: string, less_label: string, greater_label: string) {
    const loop: string = sym.unique("__std_mem_cmp_scalar_loop_")

    test r8, r8
    isa(sym.join("jz ", equal_label));
    label.define(loop);
    movzx eax, byte [r10]
    movzx edx, byte [r11]
    cmp eax, edx
    isa(sym.join("jb ", less_label));
    isa(sym.join("ja ", greater_label));
    add r10, 1
    add r11, 1
    sub r8, 1
    isa(sym.join("jnz ", loop));
    isa(sym.join("jmp ", equal_label));
}
