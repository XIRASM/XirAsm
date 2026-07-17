// x86-64 CPU feature 检测与纯判定内核生成器。
//
// 本文件只生成 baseline 整数、CPUID、XGETBV 和原子指令，不执行任何
// SSE/AVX 指令。classify/detect 的 feature 结果写入 R8D，供公共入口统一返回。

// 从固定 snapshot 计算独立 feature mask。
// 输入：R10=snapshot 指针，字段布局见 contract.inc；done_label 由调用方定义。
// 输出：R8=feature mask，并跳转到 done_label。
// 错误/所有权：无；snapshot 必须指向至少 24 个可读字节，只读不持有。
// 破坏：RAX、R8、flags；不使用栈、DF、向量寄存器或可选 ISA。
fn std_core_cpu_emit_classify_kernel(done_label: string) {
    const skip_sse2: string = sym.unique("__std_cpu_skip_sse2_")
    const skip_popcnt: string = sym.unique("__std_cpu_skip_popcnt_")
    const skip_osxsave: string = sym.unique("__std_cpu_skip_osxsave_")
    const skip_avx: string = sym.unique("__std_cpu_skip_avx_")
    const skip_erms: string = sym.unique("__std_cpu_skip_erms_")
    const skip_avx2: string = sym.unique("__std_cpu_skip_avx2_")

    xor r8d, r8d
    cmp dword [r10 + std_cpu_snapshot_max_basic_offset], 1
    isa(sym.join("jb ", done_label));

    test dword [r10 + std_cpu_snapshot_leaf1_edx_offset], 0x04000000
    isa(sym.join("jz ", skip_sse2));
    or r8d, std_cpu_feature_sse2
    label.define(skip_sse2);

    test dword [r10 + std_cpu_snapshot_leaf1_ecx_offset], 0x00800000
    isa(sym.join("jz ", skip_popcnt));
    or r8d, std_cpu_feature_popcnt
    label.define(skip_popcnt);

    test dword [r10 + std_cpu_snapshot_leaf1_ecx_offset], 0x08000000
    isa(sym.join("jz ", skip_osxsave));
    or r8d, std_cpu_feature_osxsave

    test dword [r10 + std_cpu_snapshot_leaf1_ecx_offset], 0x10000000
    isa(sym.join("jz ", skip_avx));
    mov eax, dword [r10 + std_cpu_snapshot_xcr0_eax_offset]
    and eax, 6
    cmp eax, 6
    isa(sym.join("jne ", skip_avx));
    or r8d, std_cpu_feature_avx
    label.define(skip_avx);
    label.define(skip_osxsave);

    cmp dword [r10 + std_cpu_snapshot_max_basic_offset], 7
    isa(sym.join("jb ", done_label));

    test dword [r10 + std_cpu_snapshot_leaf7_ebx_offset], 0x00000200
    isa(sym.join("jz ", skip_erms));
    or r8d, std_cpu_feature_erms
    label.define(skip_erms);

    test r8d, std_cpu_feature_avx
    isa(sym.join("jz ", skip_avx2));
    test dword [r10 + std_cpu_snapshot_leaf7_ebx_offset], 0x00000020
    isa(sym.join("jz ", skip_avx2));
    or r8d, std_cpu_feature_avx2
    label.define(skip_avx2);
    isa(sym.join("jmp ", done_label));
}

// 生成原始 CPUID leaf/subleaf 查询入口。
// SysV 输入：RDI=leaf、RSI=subleaf、RDX=16 字节输出；Win64：RCX/RDX/R8。
// 返回：RAX=输出地址；记录依次为 EAX、EBX、ECX、EDX 四个 u32。
// 错误/所有权：无；调用方保证输出可写并负责 leaf 合法性及记录生命周期。
// 保留：RBX、两端全部非易失寄存器、RSP、DF；破坏 RAX/RCX/RDX/R10/R11/flags。
fn std_core_cpu_emit_query(abi: string) {
    label.define(std_cpu_query_symbol);
    if abi == std_core_abi_sysv64 {
        mov eax, edi
        mov ecx, esi
        mov r11, rdx
    } else {
        mov eax, ecx
        mov ecx, edx
        mov r11, r8
    }
    mov r10, rbx
    cpuid
    mov dword [r11], eax
    mov dword [r11 + 4], ebx
    mov dword [r11 + 8], ecx
    mov dword [r11 + 12], edx
    mov rbx, r10
    mov rax, r11
    ret
}

// 生成 snapshot 纯判定入口。
// SysV 输入 RDI=snapshot；Win64 输入 RCX=snapshot。
// 返回：RAX=独立 feature mask；非法或缺失 leaf 由 max_basic 字段自然屏蔽。
// 错误/所有权：无；只读 24 字节 snapshot，不保存指针。
// 保留：全部 ABI 非易失寄存器、RSP、DF；破坏 RAX、R8、R10、flags。
fn std_core_cpu_emit_classify(abi: string) {
    const done: string = sym.unique("__std_cpu_classify_done_")

    label.define(std_cpu_classify_symbol);
    if abi == std_core_abi_sysv64 {
        mov r10, rdi
    } else {
        mov r10, rcx
    }
    std_core_cpu_emit_classify_kernel(done);
    label.define(done);
    mov eax, r8d
    ret
}

// 生成本机 CPUID/XGETBV feature 检测入口。
// 输入：无。返回：RAX=独立 feature mask。
// 行为：只在 CPUID.OSXSAVE=1 时执行 XGETBV(XCR0)，AVX2 还要求 XMM/YMM 状态。
// 错误/所有权：无；x86-64 保证 CPUID，函数不保存全局状态。
// 保留：RBX、全部 ABI 非易失寄存器、RSP、DF；破坏 RAX/RCX/RDX/R8-R11/flags。
// 栈：使用 32 字节私有 snapshot，不调用其他函数，不依赖 red zone/shadow space。
fn std_core_cpu_emit_detect() {
    const collect_leaf7: string = sym.unique("__std_cpu_collect_leaf7_")
    const classify: string = sym.unique("__std_cpu_detect_classify_")
    const done: string = sym.unique("__std_cpu_detect_done_")
    const skip_xgetbv: string = sym.unique("__std_cpu_skip_xgetbv_")

    label.define(std_cpu_detect_symbol);
    push rbx
    sub rsp, 32

    xor r8d, r8d
    mov qword [rsp], r8
    mov qword [rsp + 8], r8
    mov qword [rsp + 16], r8

    xor eax, eax
    xor ecx, ecx
    cpuid
    mov dword [rsp + std_cpu_snapshot_max_basic_offset], eax
    cmp eax, 1
    isa(sym.join("jb ", classify));

    mov eax, 1
    xor ecx, ecx
    cpuid
    mov dword [rsp + std_cpu_snapshot_leaf1_ecx_offset], ecx
    mov dword [rsp + std_cpu_snapshot_leaf1_edx_offset], edx
    test ecx, 0x08000000
    isa(sym.join("jz ", skip_xgetbv));
    xor ecx, ecx
    xgetbv
    mov dword [rsp + std_cpu_snapshot_xcr0_eax_offset], eax
    mov dword [rsp + std_cpu_snapshot_xcr0_edx_offset], edx
    label.define(skip_xgetbv);

    cmp dword [rsp + std_cpu_snapshot_max_basic_offset], 7
    isa(sym.join("jae ", collect_leaf7));
    isa(sym.join("jmp ", classify));
    label.define(collect_leaf7);
    mov eax, 7
    xor ecx, ecx
    cpuid
    mov dword [rsp + std_cpu_snapshot_leaf7_ebx_offset], ebx

    label.define(classify);
    lea r10, [rsp]
    std_core_cpu_emit_classify_kernel(done);
    label.define(done);
    mov eax, r8d
    add rsp, 32
    pop rbx
    ret
}

// 生成线程安全 feature cache 入口。
// SysV 输入 RDI=cache；Win64 输入 RCX=cache。cache 是调用方拥有的 8 字节槽。
// 返回：RAX=feature mask，不包含内部 ready 位。
// 错误/所有权：槽必须可写、至少 8 字节对齐并初始为 0；函数不取得所有权。
// 并发：CAS 一次发布完整 mask；竞争失败者读取获胜值，feature=0 也可缓存。
// 保留：全部 ABI 非易失寄存器、RSP、DF；破坏 RAX/RCX/RDX/R8-R11/flags。
fn std_core_cpu_emit_cached(abi: string) {
    const ready: string = sym.unique("__std_cpu_cache_ready_")
    const published: string = sym.unique("__std_cpu_cache_published_")

    label.define(std_cpu_features_cached_symbol);
    if abi == std_core_abi_sysv64 {
        mov r11, rdi
    } else {
        mov r11, rcx
    }
    mov rax, qword [r11]
    test rax, rax
    isa(sym.join("js ", ready));

    if abi == std_core_abi_sysv64 {
        sub rsp, 8
        mov qword [rsp], r11
        isa(sym.join("call ", std_cpu_detect_symbol));
        mov r11, qword [rsp]
        add rsp, 8
    } else {
        sub rsp, 40
        mov qword [rsp + 32], r11
        isa(sym.join("call ", std_cpu_detect_symbol));
        mov r11, qword [rsp + 32]
        add rsp, 40
    }

    mov r10, rax
    mov r9, 1
    shl r9, 63
    or r10, r9
    xor eax, eax
    lock cmpxchg qword [r11], r10
    isa(sym.join("jne ", published));
    mov rax, r10
    label.define(published);

    label.define(ready);
    shl rax, 1
    shr rax, 1
    ret
}
