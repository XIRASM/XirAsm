// Linux x86-64 失败路径测试。
// 打开确定不存在的文件必须返回 rax=-1、rdx=正数 errno。

import("format/format.inc");
import("io/linux.inc");
x86.use64();

fn test_exit(status: u64) {
    mov eax, 60
    mov edi, status
    syscall
}

const image0: map = format_elf64(
    format_elf_exec,
    list.of(
        format_segment(".text", format_load | format_readable | format_executable),
        format_segment(".rodata", format_load | format_readable)
    )
)
format_begin(image0);

format_segment_begin(image0, ".text");
start:
    io_file_open_read_label("missing_path");
    cmp rax, -1
    jne failed
    test rdx, rdx
    jz failed
    test_exit(0);
failed:
    test_exit(1);
format_segment_end(image0, ".text");

format_segment_begin(image0, ".rodata");
missing_path:
    db("xio-l64-definitely-missing.tmp", 0);
format_segment_end(image0, ".rodata");

const image: map = format_entry(image0, start)
format_finish(image);
