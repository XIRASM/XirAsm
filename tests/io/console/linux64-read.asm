// Linux x86-64 标准输入读取运行测试。
// 运行时从 stdin 重定向输入 4 字节 "ABCD"，验证实际读取内容和 EOF。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const input_length: u64 = 4

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
    io_read_stdin_label("input_buffer", input_length);
    cmp rax, input_length
    jne failed
    test rdx, rdx
    jne failed
    mov eax, [rel input_buffer]
    cmp eax, 0x44434241
    jne failed

    io_read_stdin_label("extra_buffer", 1);
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".data");
input_buffer:
    db(bytes.repeat(8, 0));
extra_buffer:
    db(0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
