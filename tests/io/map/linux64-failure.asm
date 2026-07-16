// Linux x86-64 map 失败路径测试。
// 覆盖运行时零长度、缺失文件打开和关闭未打开状态。

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
    lea rdi, [rel state0]
    lea rsi, [rel missing_path]
    xor ecx, ecx
    io_map_create();
    cmp rax, -1
    jne failed
    cmp rdx, io_map_error_invalid_length
    jne failed

    io_map_open_read_label("state0", "missing_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    je failed

    io_map_close_label("state0");
    cmp rax, -1
    jne failed
    cmp rdx, io_map_error_invalid_state
    jne failed

    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image, ".text");

format_segment_begin(image, ".rodata");
missing_path:
    db("xio-map-l64-missing.tmp", 0);
format_segment_end(image, ".rodata");

format_segment_begin(image, ".data");
state0:
    dq(0, 0, 0, 0, 0, 0);
format_segment_end(image, ".data");

format_entry_mut(image, start)
format_finish(image);
