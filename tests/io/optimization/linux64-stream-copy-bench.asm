// Linux x86-64 io_stream_write 内存拷贝真机基准。
// 输出五个小端 u64 周期值，对应 1/16/64/256/4096 字节；计时区间不含输出。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

fn benchmark_case(size: u64, iterations: u64, result_offset: u64, failed_label: string) {
    mov r15, iterations
    lfence
    rdtsc
    lfence
    shl rdx, 32
    or rax, rdx
    mov rbp, rax

    const loop_label: string = sym.unique("__io_bench_stream_loop_")
    label.define(loop_label);
    mov qword [rel stream_state + 24], 0
    mov qword [rel stream_state + 48], 0
    lea rdi, [rel stream_state]
    lea rsi, [rel source_buffer]
    mov rdx, size
    io_stream_write();
    cmp rax, size
    isa(sym.join("jne ", failed_label));
    test rdx, rdx
    isa(sym.join("jnz ", failed_label));
    sub r15, 1
    isa(sym.join("jnz ", loop_label));

    lfence
    rdtsc
    lfence
    shl rdx, 32
    or rax, rdx
    sub rax, rbp
    mov [rel benchmark_results + result_offset], rax
}

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    lea rax, [rel stream_buffer]
    mov [rel stream_state + 8], rax
    mov qword [rel stream_state + 16], 4096
    mov qword [rel stream_state + 32], 0
    mov qword [rel stream_state + 40], io_stream_mode_write
    mov qword [rel stream_state + 56], 0

    benchmark_case(1, 2000000, 0, "failed");
    benchmark_case(16, 500000, 8, "failed");
    benchmark_case(64, 250000, 16, "failed");
    benchmark_case(256, 100000, 24, "failed");
    benchmark_case(4096, 10000, 32, "failed");

    mov eax, 1
    mov edi, 1
    lea rsi, [rel benchmark_results]
    mov edx, 40
    syscall
    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
stream_state:
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
stream_buffer:
    rb(4096);
source_buffer:
    rb(4096);
benchmark_results:
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
