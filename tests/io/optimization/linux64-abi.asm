// Linux x86-64 IO ABI 真机哨兵测试。
// 覆盖 stream 的批量读写、flush/close 错误路径和 path syscall；验证
// SysV 非易失寄存器、stream 明示保留的 rdi/rsi、rsp 和 DF 契约。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

fn seed_nonvolatile() {
    mov ebx, 0x11111111
    mov ebp, 0x22222222
    mov r12d, 0x33333333
    mov r13d, 0x44444444
    mov r14d, 0x55555555
    mov r15d, 0x66666666
}

fn check_nonvolatile(failed_label: string) {
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
    cmp rsp, [rel saved_rsp]
    isa(sym.join("jne ", failed_label));
    pushfq
    pop rax
    test eax, 0x400
    isa(sym.join("jnz ", failed_label));
}

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    mov [rel saved_rsp], rsp
    seed_nonvolatile();

    lea rax, [rel stream_buffer]
    mov [rel stream_state + 8], rax
    mov qword [rel stream_state + 16], 64
    mov qword [rel stream_state + 24], 0
    mov qword [rel stream_state + 32], 0
    mov qword [rel stream_state + 40], io_stream_mode_write
    mov qword [rel stream_state + 48], 0
    mov qword [rel stream_state + 56], 0
    lea rdi, [rel stream_state]
    lea rsi, [rel source_data]
    mov edx, 16
    io_stream_write();
    cmp rax, 16
    jne failed_write
    test rdx, rdx
    jne failed_write
    lea rax, [rel stream_state]
    cmp rdi, rax
    jne failed_write
    lea rax, [rel source_data]
    cmp rsi, rax
    jne failed_write
    check_nonvolatile("failed_write");

    lea rax, [rel source_data]
    mov [rel stream_state + 8], rax
    mov qword [rel stream_state + 16], 16
    mov qword [rel stream_state + 24], 0
    mov qword [rel stream_state + 32], 16
    mov qword [rel stream_state + 40], io_stream_mode_read
    mov qword [rel stream_state + 48], 0
    mov qword [rel stream_state + 56], 0
    lea rdi, [rel stream_state]
    lea rsi, [rel read_buffer]
    mov edx, 16
    io_stream_read();
    cmp rax, 16
    jne failed_read
    test rdx, rdx
    jne failed_read
    lea rax, [rel stream_state]
    cmp rdi, rax
    jne failed_read
    lea rax, [rel read_buffer]
    cmp rsi, rax
    jne failed_read
    cmp dword [rel read_buffer], 0x44434241
    jne failed_read
    cmp dword [rel read_buffer + 12], 0x504f4e4d
    jne failed_read
    check_nonvolatile("failed_read");

    mov qword [rel stream_state + 40], io_stream_mode_closed
    lea rdi, [rel stream_state]
    io_stream_flush();
    cmp rax, -1
    jne failed_flush
    cmp rdx, io_stream_error_wrong_mode
    jne failed_flush
    check_nonvolatile("failed_flush");

    lea rdi, [rel stream_state]
    io_stream_close();
    cmp rax, -1
    jne failed_close
    cmp rdx, io_stream_error_invalid_state
    jne failed_close
    check_nonvolatile("failed_close");

    lea rsi, [rel missing_path]
    io_path_query();
    test rax, rax
    jne failed_path
    test rdx, rdx
    jne failed_path
    lea rax, [rel missing_path]
    cmp rsi, rax
    jne failed_path
    check_nonvolatile("failed_path");

    test_exit(0);
failed_write:
    test_exit(1);
failed_read:
    test_exit(2);
failed_flush:
    test_exit(3);
failed_close:
    test_exit(4);
failed_path:
    test_exit(5);
format_segment_end(image, ".text");

format_segment_begin(image, ".rodata");
source_data:
    db("ABCDEFGHIJKLMNOP");
missing_path:
    db("xio-optimization-missing-linux64", 0);
format_segment_end(image, ".rodata");

format_segment_begin(image, ".data");
saved_rsp:
    dq(0);
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
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
    dq(0);
read_buffer:
    dq(0);
    dq(0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
