// std/core memory 大容量 copy 正确性与周期矩阵。
//
// 同一产物生成 SSE2、原 compact AVX2、large temporal 与显式 NT-8MiB 四个
// 私有入口，动态分配测试区并输出 84 个小端 u64 周期总数。计时区间不含
// 分配、初始化、校验和输出；结果不是发布硬门禁。

import("format/format.inc");
import("std/core.inc");
x86.use64();

const large_is_windows: bool = test_memory_abi == std_core_abi_windows64
const large_max_size: u64 = 32 * 1024 * 1024
const large_source_base_offset: u64 = 4096
const large_destination_base_offset: u64 = 40 * 1024 * 1024 + 4096
const large_allocation_size: u64 = large_destination_base_offset + large_max_size + 8192
const large_result_count: u64 = 84
const large_result_size: u64 = large_result_count * 8

fn large_exit(status: u64) {
    if large_is_windows {
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

fn large_call_copy(symbol: string, size: u64) {
    if large_is_windows {
        mov rcx, r14
        mov rdx, r13
        mov r8, size
    } else {
        mov rdi, r14
        mov rsi, r13
        mov rdx, size
    }
    isa(sym.join("call ", symbol));
}

// 生成未启用大块策略的 compact AVX2 对照入口。
// 参数、返回、保留和破坏契约与正式 AVX2 copy 相同；仅供本 benchmark 对照。
fn large_emit_compact_copy(abi: string, entry_symbol: string) {
    label.define(entry_symbol);
    std_core_memory_map_args(abi);
    mov rax, r10
    std_core_memory_emit_forward_avx2_compact();
    vzeroupper
    ret
}

// 编译期参数：入口、长度、迭代数、源低位偏移和结果槽。
// 运行时：R13/R14 保存源/目标；依赖被测入口保持 ABI 非易失寄存器。
// 校验：每个 case 完整比较 size 字节，并检查目标前后哨兵。
fn large_benchmark_case(symbol: string, size: u64, iterations: u64, source_offset: u64, result_offset: u64) {
    const loop_label: string = sym.unique("__std_large_bench_loop_")
    const verify_label: string = sym.unique("__std_large_verify_loop_")
    const verified_label: string = sym.unique("__std_large_verified_")

    mov r13, qword [rel large_allocation_base]
    add r13, large_source_base_offset + source_offset
    mov r14, qword [rel large_allocation_base]
    add r14, large_destination_base_offset
    mov byte [r14 - 1], 0xa5
    isa(sym.join("mov byte [r14 + ", size, "], 0x5a"));

    // 一次不计时 warmup，同时验证返回原目标。
    large_call_copy(symbol, size);
    cmp rax, r14
    jne large_failed_return

    mov r12, iterations
    mfence
    lfence
    rdtsc
    lfence
    shl rdx, 32
    or rax, rdx
    mov rbp, rax

    label.define(loop_label);
    large_call_copy(symbol, size);
    sub r12, 1
    isa(sym.join("jnz ", loop_label));

    mfence
    lfence
    rdtsc
    lfence
    shl rdx, 32
    or rax, rdx
    sub rax, rbp
    isa(sym.join("mov qword [rel large_results + ", result_offset, "], rax"));

    mov r10, r13
    mov r11, r14
    mov rcx, size
    test rcx, rcx
    isa(sym.join("jz ", verified_label));
    label.define(verify_label);
    movzx eax, byte [r10]
    cmp al, byte [r11]
    jne large_failed_data
    add r10, 1
    add r11, 1
    sub rcx, 1
    isa(sym.join("jnz ", verify_label));
    label.define(verified_label);
    cmp byte [r14 - 1], 0xa5
    jne large_failed_guard
    isa(sym.join("cmp byte [r14 + ", size, "], 0x5a"));
    jne large_failed_guard
}

fn large_emit_matrix(symbol: string, result_base: u64) {
    // same-page-offset、半页错位、接近下一页的 4 KiB alias 风险三类。
    // near-4K 对正式 AVX2 验证反向 temporal 规避；NT 对齐/streaming 路径由
    // large_copy_avx2_nt_test 的 32x32 correctness 矩阵独立覆盖。
    large_benchmark_case(symbol, 4096, 8192, 0, result_base + 0);
    large_benchmark_case(symbol, 4096, 8192, 2048, result_base + 8);
    large_benchmark_case(symbol, 4096, 8192, 4063, result_base + 16);
    large_benchmark_case(symbol, 64 * 1024, 512, 0, result_base + 24);
    large_benchmark_case(symbol, 64 * 1024, 512, 2048, result_base + 32);
    large_benchmark_case(symbol, 64 * 1024, 512, 4063, result_base + 40);
    large_benchmark_case(symbol, 1024 * 1024, 32, 0, result_base + 48);
    large_benchmark_case(symbol, 1024 * 1024, 32, 2048, result_base + 56);
    large_benchmark_case(symbol, 1024 * 1024, 32, 4063, result_base + 64);
    large_benchmark_case(symbol, 8 * 1024 * 1024, 8, 0, result_base + 72);
    large_benchmark_case(symbol, 8 * 1024 * 1024, 8, 2048, result_base + 80);
    large_benchmark_case(symbol, 8 * 1024 * 1024, 8, 4063, result_base + 88);
    large_benchmark_case(symbol, 16 * 1024 * 1024, 4, 0, result_base + 96);
    large_benchmark_case(symbol, 16 * 1024 * 1024, 4, 2048, result_base + 104);
    large_benchmark_case(symbol, 16 * 1024 * 1024, 4, 4063, result_base + 112);
    large_benchmark_case(symbol, 24 * 1024 * 1024, 3, 0, result_base + 120);
    large_benchmark_case(symbol, 24 * 1024 * 1024, 3, 2048, result_base + 128);
    large_benchmark_case(symbol, 24 * 1024 * 1024, 3, 4063, result_base + 136);
    large_benchmark_case(symbol, 32 * 1024 * 1024, 2, 0, result_base + 144);
    large_benchmark_case(symbol, 32 * 1024 * 1024, 2, 2048, result_base + 152);
    large_benchmark_case(symbol, 32 * 1024 * 1024, 2, 4063, result_base + 160);
}

// 对 4097 字节大块路径运行 32x32 源/目标对齐矩阵。
// 该矩阵不计时，只验证目标范围、返回值和前后哨兵。
fn large_run_alignment_matrix(symbol: string) {
    const destination_loop: string = sym.unique("__std_large_align_destination_")
    const source_loop: string = sym.unique("__std_large_align_source_")
    const verify_loop: string = sym.unique("__std_large_align_verify_")

    xor r12d, r12d
    label.define(destination_loop);
    xor r15d, r15d
    label.define(source_loop);
    mov r13, qword [rel large_allocation_base]
    add r13, large_source_base_offset
    add r13, r15
    mov r14, qword [rel large_allocation_base]
    add r14, large_destination_base_offset
    add r14, r12
    mov byte [r14 - 1], 0xa5
    mov byte [r14 + 4097], 0x5a
    large_call_copy(symbol, 4097);
    cmp rax, r14
    jne large_failed_return

    mov r10, r13
    mov r11, r14
    mov ecx, 4097
    label.define(verify_loop);
    movzx eax, byte [r10]
    cmp al, byte [r11]
    jne large_failed_data
    add r10, 1
    add r11, 1
    sub ecx, 1
    isa(sym.join("jnz ", verify_loop));
    cmp byte [r14 - 1], 0xa5
    jne large_failed_guard
    cmp byte [r14 + 4097], 0x5a
    jne large_failed_guard

    add r15d, 1
    cmp r15d, 32
    isa(sym.join("jb ", source_loop));
    add r12d, 1
    cmp r12d, 32
    isa(sym.join("jb ", destination_loop));
}

let large_imports: map = pe_import_new()
if large_is_windows {
    large_imports = pe_import_use64_many(
        large_imports,
        "KERNEL32.DLL",
        list.of("ExitProcess", "GetCurrentThread", "SetThreadAffinityMask", "VirtualAlloc", "GetStdHandle", "WriteFile")
    )
}

let large_image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
if large_is_windows {
    large_image = format_pe64(
        format_pe_exe | format_pe_console | format_pe_nx | format_pe_aslr_auto,
        list.of(
            format_section(".text", format_code | format_readable | format_executable),
            format_section(".data", format_data | format_readable | format_writeable),
            format_section(".idata", format_imports | format_readable | format_writeable)
        )
    )
}
format_begin(large_image);

if large_is_windows {
    format_section_begin(large_image, ".text");
} else {
    format_segment_begin(large_image, ".text");
}
large_start:
    // 尽量固定到逻辑 CPU 0；失败不影响 correctness，外层仍取多样本最小值。
    if large_is_windows {
        sub rsp, 40
        call [rel GetCurrentThread]
        mov rcx, rax
        mov edx, 1
        call [rel SetThreadAffinityMask]
        add rsp, 40

        xor ecx, ecx
        mov edx, large_allocation_size
        mov r8d, 0x3000
        mov r9d, 4
        sub rsp, 40
        call [rel VirtualAlloc]
        add rsp, 40
        test rax, rax
        jz large_failed_allocate
    } else {
        mov qword [rel large_affinity_mask], 1
        xor edi, edi
        mov esi, 8
        lea rdx, [rel large_affinity_mask]
        mov eax, 203
        syscall

        xor edi, edi
        mov esi, large_allocation_size
        mov edx, 3
        mov r10d, 0x22
        mov r8, -1
        xor r9d, r9d
        mov eax, 9
        syscall
        test rax, rax
        js large_failed_allocate
    }
    mov qword [rel large_allocation_base], rax

    // 初始化覆盖最大 source 范围；模式不依赖目标旧内容。
    mov r10, rax
    add r10, large_source_base_offset
    mov rcx, large_max_size + 4096
    mov eax, 0x5d
large_initialize_source:
    mov byte [r10], al
    add eax, 0x83
    xor eax, 0x4d
    add r10, 1
    sub rcx, 1
    jnz large_initialize_source

    // fixed AVX2 只在 CPU 与 OS 都支持 YMM 状态时运行。
    if large_is_windows {
        sub rsp, 40
    }
    call std_cpu_detect
    if large_is_windows {
        add rsp, 40
    }
    test rax, std_cpu_feature_avx2
    jz large_skip_avx2

    large_run_alignment_matrix("large_copy_avx2");
    large_run_alignment_matrix("large_copy_avx2_nt_test");
    large_emit_matrix("large_copy_sse2", 0);
    large_emit_matrix("large_copy_avx2_compact", 168);
    large_emit_matrix("large_copy_avx2", 336);
    large_emit_matrix("large_copy_avx2_nt", 504);

    if large_is_windows {
        mov ecx, -11
        sub rsp, 40
        call [rel GetStdHandle]
        mov rcx, rax
        lea rdx, [rel large_results]
        mov r8d, large_result_size
        lea r9, [rel large_written]
        mov qword [rsp + 32], 0
        call [rel WriteFile]
        add rsp, 40
        test eax, eax
        jz large_failed_output
        cmp dword [rel large_written], large_result_size
        jne large_failed_output
    } else {
        mov eax, 1
        mov edi, 1
        lea rsi, [rel large_results]
        mov edx, large_result_size
        syscall
        cmp rax, large_result_size
        jne large_failed_output
    }
    large_exit(0);

large_skip_avx2:
    large_exit(77);
large_failed_allocate:
    large_exit(10);
large_failed_return:
    large_exit(11);
large_failed_data:
    large_exit(12);
large_failed_guard:
    large_exit(13);
large_failed_output:
    large_exit(14);

std_cpu_emit(test_memory_abi);
std_core_memory_emit_copy(test_memory_abi, std_core_memory_tier_sse2, "large_copy_sse2", std_memory_non_temporal_disabled);
large_emit_compact_copy(test_memory_abi, "large_copy_avx2_compact");
std_core_memory_emit_copy(test_memory_abi, std_core_memory_tier_avx2, "large_copy_avx2", std_memory_non_temporal_disabled);
std_core_memory_emit_copy(test_memory_abi, std_core_memory_tier_avx2, "large_copy_avx2_nt_test", 4096);
std_core_memory_emit_copy(test_memory_abi, std_core_memory_tier_avx2, "large_copy_avx2_nt", 8 * 1024 * 1024);

if large_is_windows {
    format_section_end(large_image, ".text");
    format_section_begin(large_image, ".data");
} else {
    format_segment_end(large_image, ".text");
    format_segment_begin(large_image, ".data");
}
large_allocation_base:
    dq(0);
large_affinity_mask:
    dq(1);
large_written:
    dd(0);
large_results:
    rq(large_result_count);
if large_is_windows {
    format_section_end(large_image, ".data");
    format_pe_import_section(large_image, ".idata", large_imports);
} else {
    format_segment_end(large_image, ".data");
}

format_entry_mut(large_image, large_start)
format_finish(large_image);
