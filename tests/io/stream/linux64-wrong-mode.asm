// Linux x86-64 stream 模式错误运行测试。
// 对读模式状态调用写字节接口，必须返回 stream 自定义错误且不得触发 syscall。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

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
    lea rdi, [rel stream_state]
    mov al, 0x41
    io_stream_write_byte();
    cmp rax, -1
    jne failed
    cmp rdx, io_stream_error_wrong_mode
    jne failed
    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
stream_state:
    dq(-1);
    dq(0);
    dq(1);
    dq(0);
    dq(0);
    dq(io_stream_mode_read);
    dq(0);
    dq(0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
