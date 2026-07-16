import("format/format.inc");
import("io/linux.inc");
x86.use64();

const message_text: string = "XIRASM Linux console"
const message_length: u64 = len(message_text) + 1

// 测试退出
fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

let image: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    io_write_stdout_label("message", message_length);
    cmp rax, message_length
    jne failed
    test rdx, rdx
    jne failed

    io_write_stderr_label("message", message_length);
    cmp rax, message_length
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".rodata");
message:
    db(message_text, 10);
format_segment_end(image, ".rodata");

format_entry_mut(image, start)
format_finish(image);
