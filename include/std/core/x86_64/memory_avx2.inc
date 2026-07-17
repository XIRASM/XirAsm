// x86-64 memory 原语的 AVX2 correctness 内核生成器。
//
// YMM 主循环和 XMM 尾部全部使用 VEX 编码；不足 8 字节的最终尾部只使用整数
// 指令。内核不发出 RET，调用方必须在每条返回路径执行 VZEROUPPER；该 ABI
// 边界会清空全部 YMM 寄存器的高 128 位。

// 紧凑前向 AVX2 copy/move 内核。
// 输入：R10=目标，R11=源，R8=长度，范围适合前向复制。
// 返回：不设置 RAX；调用方保存原目标并负责 VZEROUPPER。
// 破坏：RDX、R8-R11、YMM0、flags；按 32/16/8/4/2/1 精确访问，不越界。
fn std_core_memory_emit_forward_avx2_compact() {
    const tail: string = sym.unique("__std_mem_fwd_avx2_tail_")
    const loop: string = sym.unique("__std_mem_fwd_avx2_loop_")
    const small: string = sym.unique("__std_mem_fwd_avx2_small_")
    const scalar: string = sym.unique("__std_mem_fwd_avx2_scalar_")

    cmp r8, 32
    isa(sym.join("jb ", tail));
    label.define(loop);
    vmovdqu ymm0, [r11]
    vmovdqu [r10], ymm0
    add r11, 32
    add r10, 32
    sub r8, 32
    cmp r8, 32
    isa(sym.join("jae ", loop));

    label.define(tail);
    cmp r8, 16
    isa(sym.join("jb ", small));
    vmovdqu xmm0, [r11]
    vmovdqu [r10], xmm0
    add r11, 16
    add r10, 16
    sub r8, 16
    label.define(small);
    cmp r8, 8
    isa(sym.join("jb ", scalar));
    mov rdx, qword [r11]
    mov qword [r10], rdx
    add r11, 8
    add r10, 8
    sub r8, 8
    label.define(scalar);
    std_core_memory_emit_forward_tail();
}

// 大块 AVX2 copy 内核。
// 输入：R10=目标，R11=源，R8=长度；copy 契约保证两个范围不重叠。
// 返回：不设置 RAX；调用方保存原目标并负责 VZEROUPPER。
// 破坏：RCX、RDX、R8-R11、YMM0-YMM3、flags；不使用栈或 DF。
// 编译期参数：non_temporal_threshold=0 禁用 streaming store，否则为最小长度。
// 策略：达到显式阈值时优先选择 non-temporal 路径，把目标推进到 32 字节
// 边界，使用 4x streaming store 并在退出前执行 SFENCE。其余 4096 字节以上
// temporal copy 才检查源未对齐且低 12 位接近下一页的风险，命中时后向复制以
// 规避 4 KiB alias 假依赖。反向选择只用于明确不重叠的 copy，不用于 move。
fn std_core_memory_emit_copy_avx2(non_temporal_threshold: u64) {
    const compact: string = sym.unique("__std_mem_copy_avx2_compact_")
    const backward: string = sym.unique("__std_mem_copy_avx2_backward_")
    const done: string = sym.unique("__std_mem_copy_avx2_done_")
    const non_temporal: string = sym.unique("__std_mem_copy_avx2_nt_")
    const non_temporal_loop: string = sym.unique("__std_mem_copy_avx2_nt_loop_")

    cmp r8, 4096
    isa(sym.join("jb ", compact));

    // Streaming store 不需要 temporal store/load 消歧，达到阈值后优先进入 NT。
    if non_temporal_threshold != std_memory_non_temporal_disabled {
        cmp r8, non_temporal_threshold
        isa(sym.join("jae ", non_temporal));
    }

    // 只在源未按 YMM 对齐时检查 near-4K 地址关系，减少普通路径分支。
    test r11, 31
    isa(sym.join("jz ", compact));
    mov rdx, r11
    sub rdx, r10
    and edx, 4095
    cmp edx, 4096 - 128
    isa(sym.join("jae ", backward));
    isa(sym.join("jmp ", compact));

    label.define(backward);
    std_core_memory_emit_backward_avx2();
    isa(sym.join("jmp ", done));

    if non_temporal_threshold != std_memory_non_temporal_disabled {
        label.define(non_temporal);
        mov edx, r10d
        neg edx
        and edx, 31
        test edx, edx
        isa(sym.join("jz ", non_temporal_loop));
        mov r9, rdx
        mov rcx, r8
        mov r8, r9
        std_core_memory_emit_forward_avx2_compact();
        mov r8, rcx
        sub r8, r9

        label.define(non_temporal_loop);
        vmovdqu ymm0, [r11]
        vmovdqu ymm1, [r11 + 32]
        vmovdqu ymm2, [r11 + 64]
        vmovdqu ymm3, [r11 + 96]
        vmovntdq [r10], ymm0
        vmovntdq [r10 + 32], ymm1
        vmovntdq [r10 + 64], ymm2
        vmovntdq [r10 + 96], ymm3
        add r11, 128
        add r10, 128
        sub r8, 128
        cmp r8, 128
        isa(sym.join("jae ", non_temporal_loop));

        sfence
        std_core_memory_emit_forward_avx2_compact();
        isa(sym.join("jmp ", done));
    }

    label.define(compact);
    std_core_memory_emit_forward_avx2_compact();
    label.define(done);
}

// 后向 AVX2 move 内核。
// 输入：R10=目标起点，R11=源起点，R8=长度，目标位于重叠源之后。
// 返回：不设置 RAX；调用方负责 VZEROUPPER。
// 破坏：RDX、R8-R11、YMM0、flags；先移动到末尾，再精确向低地址复制。
fn std_core_memory_emit_backward_avx2() {
    const tail: string = sym.unique("__std_mem_back_avx2_tail_")
    const loop: string = sym.unique("__std_mem_back_avx2_loop_")
    const small: string = sym.unique("__std_mem_back_avx2_small_")
    const scalar: string = sym.unique("__std_mem_back_avx2_scalar_")

    add r10, r8
    add r11, r8
    cmp r8, 32
    isa(sym.join("jb ", tail));
    label.define(loop);
    sub r11, 32
    sub r10, 32
    vmovdqu ymm0, [r11]
    vmovdqu [r10], ymm0
    sub r8, 32
    cmp r8, 32
    isa(sym.join("jae ", loop));

    label.define(tail);
    cmp r8, 16
    isa(sym.join("jb ", small));
    sub r11, 16
    sub r10, 16
    vmovdqu xmm0, [r11]
    vmovdqu [r10], xmm0
    sub r8, 16
    label.define(small);
    cmp r8, 8
    isa(sym.join("jb ", scalar));
    sub r11, 8
    sub r10, 8
    mov rdx, qword [r11]
    mov qword [r10], rdx
    sub r8, 8
    label.define(scalar);
    std_core_memory_emit_backward_tail();
}

// AVX2 fill 内核。
// 输入：R10=目标，R11 低字节=填充值，R8=长度。
// 返回：不设置 RAX；调用方保存原目标并负责 VZEROUPPER。
// 破坏：RDX、R8-R11、YMM0、flags；32 字节主循环和精确尾部均允许未对齐。
fn std_core_memory_emit_fill_avx2() {
    const tail: string = sym.unique("__std_mem_fill_avx2_tail_")
    const loop: string = sym.unique("__std_mem_fill_avx2_loop_")
    const skip16: string = sym.unique("__std_mem_fill_avx2_skip16_")
    const skip8: string = sym.unique("__std_mem_fill_avx2_skip8_")
    const skip4: string = sym.unique("__std_mem_fill_avx2_skip4_")
    const skip2: string = sym.unique("__std_mem_fill_avx2_skip2_")
    const skip1: string = sym.unique("__std_mem_fill_avx2_skip1_")

    std_core_memory_prepare_fill_scalar();
    vmovd xmm0, edx
    vpbroadcastd ymm0, xmm0
    cmp r8, 32
    isa(sym.join("jb ", tail));
    label.define(loop);
    vmovdqu [r10], ymm0
    add r10, 32
    sub r8, 32
    cmp r8, 32
    isa(sym.join("jae ", loop));

    label.define(tail);
    test r8, 16
    isa(sym.join("jz ", skip16));
    vmovdqu [r10], xmm0
    add r10, 16
    label.define(skip16);
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

// AVX2 compare 内核。
// 输入：R10=left，R11=right，R8=长度；三个结果标签由调用方定义。
// 输出：按首个不同的 unsigned byte 跳转到 equal/less/greater。
// 破坏：RAX、RCX、RDX、R8、R10、R11、YMM0-YMM1、flags。
// 安全：只在剩余长度足够时加载 32/16 字节；最终尾部逐字节处理。
fn std_core_memory_emit_compare_avx2(equal_label: string, less_label: string, greater_label: string) {
    const tail: string = sym.unique("__std_mem_cmp_avx2_tail_")
    const loop: string = sym.unique("__std_mem_cmp_avx2_loop_")
    const difference32: string = sym.unique("__std_mem_cmp_avx2_diff32_")
    const scalar: string = sym.unique("__std_mem_cmp_avx2_scalar_")
    const difference16: string = sym.unique("__std_mem_cmp_avx2_diff16_")
    const compare_byte: string = sym.unique("__std_mem_cmp_avx2_byte_")

    cmp r8, 32
    isa(sym.join("jb ", tail));
    label.define(loop);
    vmovdqu ymm0, [r10]
    vmovdqu ymm1, [r11]
    vpcmpeqb ymm0, ymm0, ymm1
    vpmovmskb edx, ymm0
    cmp edx, -1
    isa(sym.join("jne ", difference32));
    add r10, 32
    add r11, 32
    sub r8, 32
    cmp r8, 32
    isa(sym.join("jae ", loop));
    isa(sym.join("jmp ", tail));

    label.define(difference32);
    not edx
    bsf ecx, edx
    isa(sym.join("jmp ", compare_byte));

    label.define(tail);
    cmp r8, 16
    isa(sym.join("jb ", scalar));
    vmovdqu xmm0, [r10]
    vmovdqu xmm1, [r11]
    vpcmpeqb xmm0, xmm0, xmm1
    vpmovmskb edx, xmm0
    cmp edx, 0xffff
    isa(sym.join("jne ", difference16));
    add r10, 16
    add r11, 16
    sub r8, 16
    isa(sym.join("jmp ", scalar));

    label.define(difference16);
    not edx
    and edx, 0xffff
    bsf ecx, edx

    label.define(compare_byte);
    movzx eax, byte [r10 + rcx]
    movzx edx, byte [r11 + rcx]
    cmp eax, edx
    isa(sym.join("jb ", less_label));
    isa(sym.join("jmp ", greater_label));

    label.define(scalar);
    std_core_memory_emit_compare_scalar(equal_label, less_label, greater_label);
}
