// Linux x86-64 文件核心运行测试。
// 覆盖：创建/截断、追加、写入、刷新、大小、SEEK_END、
// SEEK_CURRENT、回到开头、读取、EOF 和关闭。成功退出码为 0。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const first_text: string = "1234"
const second_text: string = "5678"
const first_length: u64 = len(first_text)
const second_length: u64 = len(second_text)
const total_length: u64 = first_length + second_length

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    io_file_create_truncate_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_write_label("first_data", first_length);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_flush();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_size();
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_file_open_append_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_write_label("second_data", second_length);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_flush();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_size();
    cmp rax, 8
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed

    io_file_open_read_label("file_path");
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed
    mov r12, rax

    mov rdi, r12
    io_file_size();
    cmp rax, 8
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    mov rsi, -4
    io_file_seek(io_file_seek_end);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", second_length);
    cmp rax, 4
    jne failed
    mov eax, [rel read_buffer]
    cmp eax, 0x38373635
    jne failed

    mov rdi, r12
    mov rsi, -4
    io_file_seek(io_file_seek_current);
    cmp rax, 4
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_rewind();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", total_length);
    cmp rax, 8
    jne failed
    mov rax, [rel read_buffer]
    mov r10, 0x3837363534333231
    cmp rax, r10
    jne failed

    mov rdi, r12
    io_file_read_label("read_buffer", 1);
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    mov rdi, r12
    io_file_close();
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
file_path:
    db("xio-l64.tmp", 0);
first_data:
    db(first_text);
second_data:
    db(second_text);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
read_buffer:
    dq(0);
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);
