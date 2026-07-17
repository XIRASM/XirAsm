// XIRASM std/core x86-64 memory 公共门面。
//
// 导入本文件只声明生成函数。调用方在可执行文本区域中选择默认、固定 tier
// 或 runtime emitter 之一；它们生成四个固定运行时标签：
// std_memory_copy、std_memory_move、std_memory_fill、std_memory_compare。
// 默认保持 SSE2；固定 AVX2 由调用者保证能力，runtime 依赖 CPU emitter。
// 在同一输出中重复生成这些入口会产生重复标签诊断。

import("contract.inc");
import("abi/sysv64.inc");
import("abi/windows64.inc");
import("x86_64/memory_scalar.inc");
import("x86_64/memory_sse2.inc");
import("x86_64/memory_avx2.inc");
import("dispatch.inc");

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
// 编译期参数：abi 选择参数映射；tier 选择内核；entry_symbol 指定入口标签。
// 参数：由 abi 决定；dst/src/count 范围必须有效且不得重叠。
// 返回：RAX=原 dst；count=0 时不访问指针。
// 所有权：不取得任何内存所有权。
// 保留：两端 ABI 的全部非易失寄存器、RSP、DF。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 额外破坏 XMM0，AVX2 破坏 YMM0-YMM3。
fn std_core_memory_emit_copy(abi: string, tier: string, entry_symbol: string, non_temporal_threshold: u64) {
    label.define(entry_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_forward_scalar();
    } else if tier == std_core_memory_tier_sse2 {
        std_core_memory_emit_forward_sse2();
    } else {
        std_core_memory_emit_copy_avx2(non_temporal_threshold);
        vzeroupper
    }
    ret
}

// 生成 overlap-safe move 运行时入口。
// 编译期参数：abi 选择参数映射；tier 选择内核；entry_symbol 指定入口标签。
// 参数和返回：与 copy 相同，但允许任意重叠和 dst==src。
// 行为：dst 位于重叠 src 之后时后向复制，否则前向复制。
// 所有权：不取得任何内存所有权。
// 保留：全部 ABI 非易失寄存器、RSP、DF；不使用 std/rep。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 额外破坏 XMM0，AVX2 破坏 YMM0。
fn std_core_memory_emit_move(abi: string, tier: string, entry_symbol: string) {
    const forward: string = sym.unique("__std_mem_move_forward_")
    const done: string = sym.unique("__std_mem_move_done_")

    label.define(entry_symbol);
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
    } else if tier == std_core_memory_tier_sse2 {
        std_core_memory_emit_backward_sse2();
    } else {
        std_core_memory_emit_backward_avx2();
    }
    isa(sym.join("jmp ", done));

    label.define(forward);
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_forward_scalar();
    } else if tier == std_core_memory_tier_sse2 {
        std_core_memory_emit_forward_sse2();
    } else {
        std_core_memory_emit_forward_avx2_compact();
    }

    label.define(done);
    if tier == std_core_memory_tier_avx2 {
        vzeroupper
    }
    ret
}

// 生成 fill 运行时入口。
// 编译期参数：abi 选择参数映射；tier 选择内核；entry_symbol 指定入口标签。
// 参数：dst、value、count 由 abi 映射；只使用 value 的低 8 位。
// 返回：RAX=原 dst；count=0 时不写内存。
// 所有权：不取得目标内存所有权。
// 保留：全部 ABI 非易失寄存器、RSP、DF。
// 破坏：RAX、RDX、R8-R11、flags；SSE2 额外破坏 XMM0，AVX2 破坏 YMM0。
fn std_core_memory_emit_fill(abi: string, tier: string, entry_symbol: string) {
    label.define(entry_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_fill_scalar();
    } else if tier == std_core_memory_tier_sse2 {
        std_core_memory_emit_fill_sse2();
    } else {
        std_core_memory_emit_fill_avx2();
        vzeroupper
    }
    ret
}

// 生成 compare 运行时入口。
// 编译期参数：abi 选择参数映射；tier 选择内核；entry_symbol 指定入口标签。
// 参数：left、right、count 由 abi 映射；按第一个不同的无符号字节比较。
// 返回：left<right 为 RAX=-1，相等为 0，left>right 为 1。
// count=0 时不读内存。返回值只承诺符号关系，不承诺字节差值。
// 所有权：只读两个输入范围。
// 保留：全部 ABI 非易失寄存器、RSP、DF。
// 破坏：RAX、RCX、RDX、R8-R11、flags；SSE2 破坏 XMM0-XMM1，AVX2 破坏 YMM0-YMM1。
fn std_core_memory_emit_compare(abi: string, tier: string, entry_symbol: string) {
    const equal: string = sym.unique("__std_mem_cmp_equal_")
    const less: string = sym.unique("__std_mem_cmp_less_")
    const greater: string = sym.unique("__std_mem_cmp_greater_")

    label.define(entry_symbol);
    std_core_memory_map_args(abi);
    if tier == std_core_memory_tier_scalar {
        std_core_memory_emit_compare_scalar(equal, less, greater);
    } else if tier == std_core_memory_tier_sse2 {
        std_core_memory_emit_compare_sse2(equal, less, greater);
    } else {
        std_core_memory_emit_compare_avx2(equal, less, greater);
    }

    label.define(equal);
    if tier == std_core_memory_tier_avx2 {
        vzeroupper
    }
    xor eax, eax
    ret
    label.define(less);
    if tier == std_core_memory_tier_avx2 {
        vzeroupper
    }
    mov rax, -1
    ret
    label.define(greater);
    if tier == std_core_memory_tier_avx2 {
        vzeroupper
    }
    mov eax, 1
    ret
}

// 生成可调大块策略的指定实现层级入口。
// 编译期参数：abi 选择 Win64/SysV；tier 选择 scalar/SSE2/固定 AVX2；
// non_temporal_threshold=0 禁用 streaming store，其他值只允许用于 AVX2。
// 运行时输入、返回、错误、所有权和寄存器契约：见四个入口注释。
// NT 边界：只影响不重叠 copy；目标按 32 字节对齐，返回前执行 SFENCE/VZEROUPPER。
// 布局：调用位置必须位于可执行输出区域；本函数会改变布局。
fn std_memory_emit_tier_tuned(abi: string, tier: string, non_temporal_threshold: u64) {
    std_core_assert_x86_64();
    std_core_assert_abi(abi);
    std_core_assert_memory_tier(tier);
    std_core_assert_non_temporal_threshold(non_temporal_threshold);
    assert(
        tier == std_core_memory_tier_avx2 || non_temporal_threshold == std_memory_non_temporal_disabled,
        "std/core non-temporal copy requires the avx2 tier"
    );
    std_core_memory_emit_copy(abi, tier, std_memory_copy_symbol, non_temporal_threshold);
    std_core_memory_emit_move(abi, tier, std_memory_move_symbol);
    std_core_memory_emit_fill(abi, tier, std_memory_fill_symbol);
    std_core_memory_emit_compare(abi, tier, std_memory_compare_symbol);
}

// 生成指定实现层级的四个运行时入口。
// 默认 non-temporal 阈值为 0；调用方需要 streaming store 时使用 tuned emitter。
fn std_memory_emit_tier(abi: string, tier: string) {
    if tier == std_core_memory_tier_avx2 {
        std_memory_emit_tier_tuned(abi, tier, std_memory_avx2_non_temporal_threshold_default);
    } else {
        std_memory_emit_tier_tuned(abi, tier, std_memory_non_temporal_disabled);
    }
}

// 生成按 CPU/OS feature 首次选择 SSE2 或 AVX2 的可调公共入口。
// 编译期参数：abi 选择 Win64/SysV；state_symbol 指向 64 字节 runtime state；
// non_temporal_threshold=0 禁用 AVX2 copy 的 streaming store。
// 前置：同一输出必须另行调用 std_cpu_emit(abi) 一次，生成 feature cache 入口。
// 运行时契约：与默认 memory 四入口相同；首次解析后每个函数独立缓存目标指针。
// 所有权/错误：state 由调用方持有，至少 8 字节对齐、全零、可写且长期有效。
// NT 边界：只影响 AVX2 copy；阈值 0 禁用，其他值必须至少为 4096。
// 布局：本函数只生成代码；state 存储必须由调用方在可写数据区定义。
fn std_memory_emit_runtime_tuned(abi: string, state_symbol: string, non_temporal_threshold: u64) {
    const copy_sse2: string = sym.unique("__std_mem_copy_sse2_")
    const copy_avx2: string = sym.unique("__std_mem_copy_avx2_")
    const move_sse2: string = sym.unique("__std_mem_move_sse2_")
    const move_avx2: string = sym.unique("__std_mem_move_avx2_")
    const fill_sse2: string = sym.unique("__std_mem_fill_sse2_")
    const fill_avx2: string = sym.unique("__std_mem_fill_avx2_")
    const compare_sse2: string = sym.unique("__std_mem_compare_sse2_")
    const compare_avx2: string = sym.unique("__std_mem_compare_avx2_")
    const move_state: string = sym.join(state_symbol, " + ", std_memory_runtime_move_state_offset)
    const fill_state: string = sym.join(state_symbol, " + ", std_memory_runtime_fill_state_offset)
    const compare_state: string = sym.join(state_symbol, " + ", std_memory_runtime_compare_state_offset)

    std_core_assert_x86_64();
    std_core_assert_abi(abi);
    std_core_assert_non_temporal_threshold(non_temporal_threshold);

    std_dispatch_emit_avx2(abi, std_core_dispatch_runtime, std_memory_copy_symbol, state_symbol, copy_sse2, copy_avx2);
    std_dispatch_emit_avx2(abi, std_core_dispatch_runtime, std_memory_move_symbol, move_state, move_sse2, move_avx2);
    std_dispatch_emit_avx2(abi, std_core_dispatch_runtime, std_memory_fill_symbol, fill_state, fill_sse2, fill_avx2);
    std_dispatch_emit_avx2(abi, std_core_dispatch_runtime, std_memory_compare_symbol, compare_state, compare_sse2, compare_avx2);

    std_core_memory_emit_copy(abi, std_core_memory_tier_sse2, copy_sse2, std_memory_non_temporal_disabled);
    std_core_memory_emit_copy(abi, std_core_memory_tier_avx2, copy_avx2, non_temporal_threshold);
    std_core_memory_emit_move(abi, std_core_memory_tier_sse2, move_sse2);
    std_core_memory_emit_move(abi, std_core_memory_tier_avx2, move_avx2);
    std_core_memory_emit_fill(abi, std_core_memory_tier_sse2, fill_sse2);
    std_core_memory_emit_fill(abi, std_core_memory_tier_avx2, fill_avx2);
    std_core_memory_emit_compare(abi, std_core_memory_tier_sse2, compare_sse2);
    std_core_memory_emit_compare(abi, std_core_memory_tier_avx2, compare_avx2);
}

// 生成默认禁用 non-temporal store 的 SSE2/AVX2 runtime memory 入口。
fn std_memory_emit_runtime(abi: string, state_symbol: string) {
    std_memory_emit_runtime_tuned(abi, state_symbol, std_memory_avx2_non_temporal_threshold_default);
}

// 生成默认 SSE2 baseline 的四个运行时入口。
// 编译期参数：abi=std_core_abi_sysv64 或 std_core_abi_windows64。
// 运行时契约：与 std_memory_emit_tier(..., std_core_memory_tier_sse2) 相同。
// ISA：只要求 x86-64 baseline SSE2，不生成 AVX/AVX2/AVX-512 指令。
fn std_memory_emit(abi: string) {
    std_memory_emit_tier(abi, std_core_memory_tier_sse2);
}
