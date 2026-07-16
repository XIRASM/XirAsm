// Linux x86-64 缓冲流打开失败测试。
// 不存在的路径必须返回 rax=-1、rdx=正数 errno，且不取得句柄所有权。

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
        format_segment(".rodata", format_load | format_readable),
        format_segment(".data", format_load | format_readable | format_writeable)
    )
)
format_begin(image);

format_segment_begin(image, ".text");
start:
    io_stream_open_read_label(
        "stream_state",
        "missing_path",
        "stream_buffer",
        4
    );
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed
    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".rodata");
missing_path:
    db("xio-stream-l64-definitely-missing.tmp", 0);
format_segment_end(image, ".rodata");

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
    dq(0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
