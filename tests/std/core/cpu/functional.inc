// std/core CPU feature、缓存、调度和 ABI 跨平台真机测试体。
//
// 包装文件提供 cpu_test_abi。本文件对人工 snapshot 做确定性判定，再核对
// 本机 CPUID 蕴含关系；不把测试正确性绑定到某一台机器恰好支持 AVX2。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const cpu_test_is_windows: bool = cpu_test_abi == std_core_abi_windows64

fn cpu_test_exit(status: u64) {
    if cpu_test_is_windows {
        sub rsp, 40
        mov ecx, status
        call [rel ExitProcess]
        add rsp, 40
    } else {
        mov eax, 60
        mov edi, status
        syscall
    }
}

fn cpu_test_call(symbol: string) {
    if cpu_test_is_windows {
        sub rsp, 40
    }
    isa(sym.join("call ", symbol));
    if cpu_test_is_windows {
        add rsp, 40
    }
}

fn cpu_test_query(leaf: u64, subleaf: u64, output: string) {
    if cpu_test_is_windows {
        mov rcx, leaf
        mov rdx, subleaf
        isa(sym.join("lea r8, [rel ", output, "]"));
    } else {
        mov rdi, leaf
        mov rsi, subleaf
        isa(sym.join("lea rdx, [rel ", output, "]"));
    }
    cpu_test_call(std_cpu_query_symbol);
}

fn cpu_test_one(symbol: string, pointer: string) {
    if cpu_test_is_windows {
        isa(sym.join("lea rcx, [rel ", pointer, "]"));
    } else {
        isa(sym.join("lea rdi, [rel ", pointer, "]"));
    }
    cpu_test_call(symbol);
}

fn cpu_test_three(symbol: string, first: u64, second: u64, third: u64) {
    if cpu_test_is_windows {
        mov rcx, first
        mov rdx, second
        mov r8, third
    } else {
        mov rdi, first
        mov rsi, second
        mov rdx, third
    }
    cpu_test_call(symbol);
}

fn cpu_test_seed_nonvolatile() {
    mov ebx, 0x11111111
    mov ebp, 0x22222222
    mov r12d, 0x33333333
    mov r13d, 0x44444444
    mov r14d, 0x55555555
    mov r15d, 0x66666666
    if cpu_test_is_windows {
        mov edi, 0x77777777
        mov esi, 0x12345678
        movdqu xmm6, [rel cpu_xmm6_seed]
    }
}

fn cpu_test_check_nonvolatile(failed_label: string) {
    cmp rbx, 0x11111111
    isa(sym.join("jne ", failed_label));
    cmp rbp, 0x22222222
    isa(sym.join("jne ", failed_label));
    cmp r12, 0x33333333
    isa(sym.join("jne ", failed_label));
    cmp r13, 0x44444444
    isa(sym.join("jne ", failed_label));
    cmp r14, 0x55555555
    isa(sym.join("jne ", failed_label));
    cmp r15, 0x66666666
    isa(sym.join("jne ", failed_label));
    cmp rsp, [rel cpu_saved_rsp]
    isa(sym.join("jne ", failed_label));
    pushfq
    pop rax
    test eax, 0x400
    isa(sym.join("jnz ", failed_label));
    if cpu_test_is_windows {
        cmp rdi, 0x77777777
        isa(sym.join("jne ", failed_label));
        cmp rsi, 0x12345678
        isa(sym.join("jne ", failed_label));
        movdqu [rel cpu_xmm6_after], xmm6
        mov rax, [rel cpu_xmm6_after]
        cmp rax, [rel cpu_xmm6_seed]
        isa(sym.join("jne ", failed_label));
        mov rax, [rel cpu_xmm6_after + 8]
        cmp rax, [rel cpu_xmm6_seed + 8]
        isa(sym.join("jne ", failed_label));
    }
}

let cpu_imports: map = pe_import_new()
if cpu_test_is_windows {
    cpu_imports = pe_import_use64(cpu_imports, "KERNEL32.DLL", "ExitProcess")
}

let cpu_image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if cpu_test_is_windows {
    cpu_image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".rdata", format_data | format_readable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(cpu_image);

if cpu_test_is_windows {
    format_section_begin(cpu_image, ".text");
} else {
    format_segment_begin(cpu_image, ".text");
}
cpu_test_start:
    mov [rel cpu_saved_rsp], rsp
    cpu_test_seed_nonvolatile();

    // 原始 query：leaf 0 必须存在，返回输出地址并保持 RBX。
    cpu_test_query(0, 0, "cpu_query_output");
    lea rcx, [rel cpu_query_output]
    cmp rax, rcx
    jne cpu_failed_query_pointer
    cmp dword [rel cpu_query_output], 1
    jb cpu_failed_query_leaf
    cmp rbx, 0x11111111
    jne cpu_failed_query_rbx

    // leaf 7 的不支持高 subleaf 应返回全零，验证 subleaf 确实进入 ECX。
    cmp dword [rel cpu_query_output], 7
    jb cpu_query_subleaf_done
    cpu_test_query(7, 0xffffffff, "cpu_query_subleaf_output");
    cmp qword [rel cpu_query_subleaf_output], 0
    jne cpu_failed_query_leaf
    cmp qword [rel cpu_query_subleaf_output + 8], 0
    jne cpu_failed_query_leaf
cpu_query_subleaf_done:

    // snapshot 纯判定：缺 leaf、独立位、OS 状态和 leaf 7 门控。
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_none");
    test rax, rax
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_sse2");
    cmp rax, 1
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_popcnt");
    cmp rax, 2
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_xcr0_missing_ymm");
    cmp rax, 40
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_full");
    cmp rax, 63
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_leaf6");
    cmp rax, 15
    jne cpu_failed_classify
    cpu_test_one(std_cpu_classify_symbol, "cpu_snapshot_avx_without_osxsave");
    cmp rax, 1
    jne cpu_failed_classify

    // 本机检测只检查架构不变量，不假设主机必须有 AVX2。
    cpu_test_call(std_cpu_detect_symbol);
    mov [rel cpu_detected_features], rax
    test rax, std_cpu_feature_sse2
    jz cpu_failed_detect
    test rax, std_cpu_feature_avx
    jz cpu_detect_no_avx
    test rax, std_cpu_feature_osxsave
    jz cpu_failed_detect
cpu_detect_no_avx:
    test rax, std_cpu_feature_avx2
    jz cpu_detect_no_avx2
    test rax, std_cpu_feature_avx
    jz cpu_failed_detect
cpu_detect_no_avx2:

    // feature cache 首次发布带 ready 位，公开返回值不泄漏内部位。
    cpu_test_one(std_cpu_features_cached_symbol, "cpu_direct_cache");
    cmp rax, [rel cpu_detected_features]
    jne cpu_failed_cache

    // ready 位必须能区分“已缓存零 feature”和“尚未初始化”。
    cpu_test_one(std_cpu_features_cached_symbol, "cpu_zero_feature_cache");
    test rax, rax
    jne cpu_failed_cache
    cmp qword [rel cpu_direct_cache], 0
    jns cpu_failed_cache
    mov rax, qword [rel cpu_direct_cache]
    shl rax, 1
    shr rax, 1
    cmp rax, [rel cpu_detected_features]
    jne cpu_failed_cache
    cpu_test_one(std_cpu_features_cached_symbol, "cpu_direct_cache");
    cmp rax, [rel cpu_detected_features]
    jne cpu_failed_cache

    // 三种模式与首次 runtime resolver 都必须原样传递三个非对称参数。
    cpu_test_three("cpu_dispatch_baseline", 0x1111, 0x2222, 0x3333);
    cmp eax, 0x31
    jne cpu_failed_dispatch
    cpu_test_three("cpu_dispatch_fixed", 0x1111, 0x2222, 0x3333);
    cmp eax, 0x32
    jne cpu_failed_dispatch
    cpu_test_three("cpu_dispatch_runtime", 0x1111, 0x2222, 0x3333);
    test qword [rel cpu_detected_features], std_cpu_feature_avx2
    jz cpu_expect_baseline
    cmp eax, 0x32
    jne cpu_failed_dispatch
    lea rcx, [rel cpu_target_avx2]
    jmp cpu_check_target
cpu_expect_baseline:
    cmp eax, 0x31
    jne cpu_failed_dispatch
    lea rcx, [rel cpu_target_baseline]
cpu_check_target:
    cmp qword [rel cpu_runtime_state + 8], rcx
    jne cpu_failed_dispatch
    cmp qword [rel cpu_runtime_state], 0
    jns cpu_failed_dispatch

    // 第二次必须命中 target cache 快路径，结果保持一致。
    mov [rel cpu_runtime_result], rax
    cpu_test_three("cpu_dispatch_runtime", 0x1111, 0x2222, 0x3333);
    cmp rax, [rel cpu_runtime_result]
    jne cpu_failed_dispatch

    // 预置 ready+zero feature，强制覆盖本机能力之外的 runtime baseline 选择。
    cpu_test_three("cpu_dispatch_runtime_baseline", 0x1111, 0x2222, 0x3333);
    cmp eax, 0x31
    jne cpu_failed_dispatch
    lea rcx, [rel cpu_target_baseline]
    cmp qword [rel cpu_runtime_baseline_state + 8], rcx
    jne cpu_failed_dispatch
    mov rax, qword [rel cpu_runtime_baseline_state]
    shl rax, 1
    jne cpu_failed_dispatch

    cpu_test_check_nonvolatile("cpu_failed_abi");
    cpu_test_exit(0);
cpu_failed_query_pointer:
    cpu_test_exit(11);
cpu_failed_query_leaf:
    cpu_test_exit(12);
cpu_failed_query_rbx:
    cpu_test_exit(13);
cpu_failed_classify:
    cpu_test_exit(2);
cpu_failed_detect:
    cpu_test_exit(3);
cpu_failed_cache:
    cpu_test_exit(4);
cpu_failed_dispatch:
    cpu_test_exit(5);
cpu_failed_abi:
    cpu_test_exit(6);

std_cpu_emit(cpu_test_abi);
std_dispatch_emit_avx2(cpu_test_abi, std_core_dispatch_baseline, "cpu_dispatch_baseline", "cpu_baseline_state", "cpu_target_baseline", "cpu_target_avx2");
std_dispatch_emit_avx2(cpu_test_abi, std_core_dispatch_fixed_avx2, "cpu_dispatch_fixed", "cpu_fixed_state", "cpu_target_baseline", "cpu_target_avx2");
std_dispatch_emit_avx2(cpu_test_abi, std_core_dispatch_runtime, "cpu_dispatch_runtime", "cpu_runtime_state", "cpu_target_baseline", "cpu_target_avx2");
std_dispatch_emit_avx2(cpu_test_abi, std_core_dispatch_runtime, "cpu_dispatch_runtime_baseline", "cpu_runtime_baseline_state", "cpu_target_baseline", "cpu_target_avx2");

cpu_target_baseline:
    if cpu_test_is_windows {
        cmp rcx, 0x1111
        jne cpu_target_bad
        cmp rdx, 0x2222
        jne cpu_target_bad
        cmp r8, 0x3333
        jne cpu_target_bad
    } else {
        cmp rdi, 0x1111
        jne cpu_target_bad
        cmp rsi, 0x2222
        jne cpu_target_bad
        cmp rdx, 0x3333
        jne cpu_target_bad
    }
    mov eax, 0x31
    ret
cpu_target_avx2:
    if cpu_test_is_windows {
        cmp rcx, 0x1111
        jne cpu_target_bad
        cmp rdx, 0x2222
        jne cpu_target_bad
        cmp r8, 0x3333
        jne cpu_target_bad
    } else {
        cmp rdi, 0x1111
        jne cpu_target_bad
        cmp rsi, 0x2222
        jne cpu_target_bad
        cmp rdx, 0x3333
        jne cpu_target_bad
    }
    mov eax, 0x32
    ret
cpu_target_bad:
    mov eax, 0xff
    ret

if cpu_test_is_windows {
    format_section_end(cpu_image, ".text");
    format_section_begin(cpu_image, ".rdata");
} else {
    format_segment_end(cpu_image, ".text");
    format_segment_begin(cpu_image, ".rodata");
}
cpu_snapshot_none:
    dd(0, 0xffffffff, 0xffffffff, 0xffffffff, 6, 0);
cpu_snapshot_sse2:
    dd(1, 0, 0x04000000, 0, 0, 0);
cpu_snapshot_popcnt:
    dd(1, 0x00800000, 0, 0, 0, 0);
cpu_snapshot_xcr0_missing_ymm:
    dd(7, 0x18000000, 0, 0x00000220, 2, 0);
cpu_snapshot_full:
    dd(7, 0x18800000, 0x04000000, 0x00000220, 6, 0);
cpu_snapshot_leaf6:
    dd(6, 0x18800000, 0x04000000, 0x00000220, 6, 0);
cpu_snapshot_avx_without_osxsave:
    dd(7, 0x10000000, 0x04000000, 0x00000020, 6, 0);
cpu_xmm6_seed:
    dq(0x0123456789abcdef, 0xfedcba9876543210);

if cpu_test_is_windows {
    format_section_end(cpu_image, ".rdata");
    format_section_begin(cpu_image, ".data");
} else {
    format_segment_end(cpu_image, ".rodata");
    format_segment_begin(cpu_image, ".data");
}
cpu_baseline_state:
    dq(0, 0);
cpu_fixed_state:
    dq(0, 0);
cpu_runtime_state:
    dq(0, 0);
cpu_runtime_baseline_state:
    dq(0x8000000000000000, 0);
cpu_direct_cache:
    dq(0);
cpu_zero_feature_cache:
    dq(0x8000000000000000);
cpu_detected_features:
    dq(0);
cpu_runtime_result:
    dq(0);
cpu_saved_rsp:
    dq(0);
cpu_xmm6_after:
    dq(0, 0);
cpu_query_output:
    dd(0, 0, 0, 0);
cpu_query_subleaf_output:
    dd(0, 0, 0, 0);

if cpu_test_is_windows {
    format_section_end(cpu_image, ".data");
    format_pe_import_section(cpu_image, ".idata", cpu_imports);
} else {
    format_segment_end(cpu_image, ".data");
}

format_entry_mut(cpu_image, cpu_test_start)
format_finish(cpu_image);
