// XIRASM std/core 三参数函数族的 AVX2 调度入口生成器。
//
// baseline/fixed_avx2 直接尾跳；runtime 使用 16 字节 dispatch state 中的
// feature cache 与 target cache，首次解析后原子发布只读函数指针。

import("cpu.inc");

// 生成 baseline/fixed AVX2/runtime 三选一的三整数参数入口。
// 编译期参数：abi、mode、公开入口标签、dispatch state 标签和两个目标标签。
// 运行时输入：SysV RDI/RSI/RDX；Win64 RCX/RDX/R8，原样传递给最终目标。
// 返回/错误/所有权：完全继承目标函数；调度器不取得参数或缓存所有权。
// runtime state：16 字节可写、至少 8 字节对齐、初始为 0 且覆盖所有调用；
// 偏移 0 为 feature cache，偏移 8 为 target cache；固定模式不读取 state。
// 保留：全部 ABI 非易失寄存器、RSP、DF；runtime 解析破坏常规易失寄存器/flags。
// 栈：Win64 resolver 提供 shadow space；SysV resolver 保持调用点 16 字节对齐。
// ISA：调度器本身不执行 AVX；fixed_avx2 由调用者保证目标可执行，AVX2 目标
// 自己负责所有返回/调用路径的 vzeroupper 边界。
fn std_dispatch_emit_avx2(
    abi: string,
    mode: string,
    entry_symbol: string,
    state_symbol: string,
    baseline_symbol: string,
    avx2_symbol: string
) {
    const resolve: string = sym.unique("__std_dispatch_resolve_")
    const choose_baseline: string = sym.unique("__std_dispatch_baseline_")
    const publish: string = sym.unique("__std_dispatch_publish_")
    const published: string = sym.unique("__std_dispatch_published_")

    std_core_assert_x86_64();
    std_core_assert_abi(abi);
    std_core_assert_dispatch_mode(mode);

    label.define(entry_symbol);
    if mode == std_core_dispatch_baseline {
        isa(sym.join("jmp ", baseline_symbol));
    } else if mode == std_core_dispatch_fixed_avx2 {
        isa(sym.join("jmp ", avx2_symbol));
    } else {
        isa(sym.join("mov rax, qword [rel ", state_symbol, " + 8]"));
        test rax, rax
        isa(sym.join("jz ", resolve));
        jmp rax

        label.define(resolve);
        if abi == std_core_abi_sysv64 {
            sub rsp, 24
            mov qword [rsp], rdi
            mov qword [rsp + 8], rsi
            mov qword [rsp + 16], rdx
            isa(sym.join("lea rdi, [rel ", state_symbol, "]"));
            isa(sym.join("call ", std_cpu_features_cached_symbol));
        } else {
            sub rsp, 72
            mov qword [rsp + 32], rcx
            mov qword [rsp + 40], rdx
            mov qword [rsp + 48], r8
            isa(sym.join("lea rcx, [rel ", state_symbol, "]"));
            isa(sym.join("call ", std_cpu_features_cached_symbol));
        }

        test rax, std_cpu_feature_avx2
        isa(sym.join("jz ", choose_baseline));
        isa(sym.join("lea r11, [rel ", avx2_symbol, "]"));
        isa(sym.join("jmp ", publish));
        label.define(choose_baseline);
        isa(sym.join("lea r11, [rel ", baseline_symbol, "]"));

        label.define(publish);
        isa(sym.join("lea r10, [rel ", state_symbol, " + 8]"));
        xor eax, eax
        lock cmpxchg qword [r10], r11
        isa(sym.join("jne ", published));
        mov rax, r11
        label.define(published);
        mov r11, rax

        if abi == std_core_abi_sysv64 {
            mov rdi, qword [rsp]
            mov rsi, qword [rsp + 8]
            mov rdx, qword [rsp + 16]
            add rsp, 24
        } else {
            mov rcx, qword [rsp + 32]
            mov rdx, qword [rsp + 40]
            mov r8, qword [rsp + 48]
            add rsp, 72
        }
        jmp r11
    }
}
