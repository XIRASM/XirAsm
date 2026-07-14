// Linux x86-64 缓冲流核心运行测试。
// 使用 3 字节调用方缓冲区，强制覆盖自动刷新、显式刷新、关闭刷新、
// 追加、自动补充、逐字节读取和 EOF。成功退出码为 0。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

const first_text: string = "12345678"
const first_length: u64 = len(first_text)
const stream_capacity: u64 = 3

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
    io_stream_create_truncate_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    io_stream_write_label("stream_state", "first_data", first_length);
    cmp rax, first_length
    jne failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    io_stream_flush();
    cmp rax, 2
    jne failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    mov al, 0x39
    io_stream_write_byte();
    cmp rax, 1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_stream_open_append_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    lea rdi, [rel stream_state]
    mov al, 0x30
    io_stream_write_byte();
    cmp rax, 1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    io_stream_open_read_label(
        "stream_state",
        "file_path",
        "stream_buffer",
        stream_capacity
    );
    cmp rax, -1
    je failed
    test rdx, rdx
    jne failed

    io_stream_read_label("stream_state", "read_buffer", 4);
    cmp rax, 4
    jne failed_bulk_count
    test rdx, rdx
    jne failed_bulk_error
    mov eax, [rel read_buffer]
    cmp eax, 0x34333231
    jne failed_bulk_content

    lea rdi, [rel stream_state]
    io_stream_read_byte();
    cmp rax, 0x35
    jne failed_byte
    io_stream_read_byte();
    cmp rax, 0x36
    jne failed
    io_stream_read_byte();
    cmp rax, 0x37
    jne failed
    io_stream_read_byte();
    cmp rax, 0x38
    jne failed
    io_stream_read_byte();
    cmp rax, 0x39
    jne failed
    io_stream_read_byte();
    cmp rax, 0x30
    jne failed

    io_stream_read_byte();
    cmp rax, -1
    jne failed
    test rdx, rdx
    jne failed

    io_stream_close_label("stream_state");
    test rax, rax
    jne failed
    test rdx, rdx
    jne failed

    test_exit(0);
failed_bulk_count:
    test_exit(2);
failed_bulk_error:
    test_exit(4);
failed_bulk_content:
    test_exit(5);
failed_byte:
    test_exit(3);
failed:
    test_exit(1);
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
file_path:
    db("xio-stream-l64.tmp", 0);
first_data:
    db(first_text);
format_segment_end(image0, ".rodata");

format_segment_begin(image0, ".data");
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
read_buffer:
    dq(0);
format_segment_end(image0, ".data");

const image: map = format_entry(image0, start)
format_finish(image);
