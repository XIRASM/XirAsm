// XIRASM std/core x86-64 memory 公共门面。
//
// 导入本文件只声明生成函数。调用方必须在已经打开的可执行文本区域中
// 调用 std_memory_emit(abi) 一次；该调用生成四个固定运行时标签：
// std_memory_copy、std_memory_move、std_memory_fill、std_memory_compare。
// 重复调用 emitter 会产生重复标签诊断。

import("contract.inc");
import("abi/sysv64.inc");
import("abi/windows64.inc");
import("x86_64/memory_scalar.inc");
import("x86_64/memory_sse2.inc");

// 将选定 ABI 的三个参数映射到共享内核寄存器。
// 编译期参数：abi=std_core_abi_sysv64 或 std_core_abi_windows64。
// 运行时输出：R10=参数1，R11=参数2，R8=参数3。
// 返回值和内存所有权：无；只生成寄存器移动。
// 保留/破坏、栈与 DF：由对应 abi/*.inc 契约定义。
fn std_core_memory_map_args(abi: string) {
    if abi == std_core_abi_sysv64 {
        std_core_memory_map_sysv64_args();
    } else {
        std_core_memory_map_windows64_args();
    }
}

// 生成 copy 运行时入口。
// 参数：由 abi 决定；dst/src/count 范围必须有效且不得重叠。
// 返回：RAX=原 dst；count=0 时不访问指针。
// 所有权：不取得任何内存所有权。
// 保留：两端 ABI 的全部非易失寄存器、RSP、DF。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 tier 额外破坏 XMM0。
fn std_core_memory_emit_copy(abi: string, tier: string) {
    label.define(std_memory_copy_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_forward_scalar();
    } else {
        std_core_memory_emit_forward_sse2();
    }
    ret
}

// 生成 overlap-safe move 运行时入口。
// 参数和返回：与 copy 相同，但允许任意重叠和 dst==src。
// 行为：dst 位于重叠 src 之后时后向复制，否则前向复制。
// 所有权：不取得任何内存所有权。
// 保留：全部 ABI 非易失寄存器、RSP、DF；不使用 std/rep。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 tier 额外破坏 XMM0。
fn std_core_memory_emit_move(abi: string, tier: string) {
    const forward: string = sym.unique("__std_mem_move_forward_")
    const done: string = sym.unique("__std_mem_move_done_")

    label.define(std_memory_move_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    test r8, r8
    isa(sym.join("jz ", done));
    cmp r10, r11
    isa(sym.join("je ", done));
    isa(sym.join("jb ", forward));
    mov rcx, r10
    sub rcx, r11
    cmp rcx, r8
    isa(sym.join("jae ", forward));

    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_backward_scalar();
    } else {
        std_core_memory_emit_backward_sse2();
    }
    isa(sym.join("jmp ", done));

    label.define(forward);
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_forward_scalar();
    } else {
        std_core_memory_emit_forward_sse2();
    }

    label.define(done);
    ret
}

// 生成 fill 运行时入口。
// 参数：dst、value、count 由 abi 映射；只使用 value 的低 8 位。
// 返回：RAX=原 dst；count=0 时不写内存。
// 所有权：不取得目标内存所有权。
// 保留：全部 ABI 非易失寄存器、RSP、DF。
// 破坏：RAX、RDX、R8-R11、flags；SSE2 tier 额外破坏 XMM0。
fn std_core_memory_emit_fill(abi: string, tier: string) {
    label.define(std_memory_fill_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_fill_scalar();
    } else {
        std_core_memory_emit_fill_sse2();
    }
    ret
}

// 生成 compare 运行时入口。
// 参数：left、right、count 由 abi 映射；按第一个不同的无符号字节比较。
// 返回：left<right 为 RAX=-1，相等为 0，left>right 为 1。
// count=0 时不读内存。返回值只承诺符号关系，不承诺字节差值。
// 所有权：只读两个输入范围。
// 保留：全部 ABI 非易失寄存器、RSP、DF。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 tier 额外破坏 XMM0-XMM1。
fn std_core_memory_emit_compare(abi: string, tier: string) {
    const equal: string = sym.unique("__std_mem_cmp_equal_")
    const less: string = sym.unique("__std_mem_cmp_less_")
    const greater: string = sym.unique("__std_mem_cmp_greater_")

    label.define(std_memory_compare_symbol);
    std_core_memory_map_args(abi);
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_compare_scalar(equal, less, greater);
    } else {
        std_core_memory_emit_compare_sse2(equal, less, greater);
    }

    label.define(equal);
    xor eax, eax
    ret
    label.define(less);
    mov rax, -1
    ret
    label.define(greater);
    mov eax, 1
    ret
}

// 生成指定实现层级的四个运行时入口。
// 编译期参数：abi 选择 Win64/SysV；tier 选择 scalar/SSE2。
// 运行时输入、返回、错误、所有权和寄存器契约：见四个入口注释。
// 布局：调用位置必须位于可执行输出区域；本函数会改变布局。
fn std_memory_emit_tier(abi: string, tier: string) {
    std_core_assert_x86_64();
    std_core_assert_memory_abi(abi);
    std_core_assert_memory_tier(tier);
    std_core_memory_emit_copy(abi, tier);
    std_core_memory_emit_move(abi, tier);
    std_core_memory_emit_fill(abi, tier);
    std_core_memory_emit_compare(abi, tier);
}

// 生成默认 SSE2 baseline 的四个运行时入口。
// 编译期参数：abi=std_core_abi_sysv64 或 std_core_abi_windows64。
// 运行时契约：与 std_memory_emit_tier(..., std_core_memory_tier_sse2) 相同。
// ISA：只要求 x86-64 baseline SSE2，不生成 AVX/AVX2/AVX-512 指令。
fn std_memory_emit(abi: string) {
    std_memory_emit_tier(abi, std_core_memory_tier_sse2);
}
